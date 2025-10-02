#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Completed and improved script: register all BOLD runs (across sessions) to the first run's mean
# then register that run to the T1w anatomy and apply transforms to all runs.
# This version handles 4D BOLD images by using ANTs' WarpTimeSeriesImageMultiTransform
# (if available) or falls back to per-volume processing.

# USAGE: ./fmriprep_align_to_T1.sh --sub sub-01 [--fprep fmriprep] [--sessions ses-LE,ses-RE]

# ---------------------- User-configurable defaults -----------------------
FPREP_ID="fmriprep"
# Modify/add sessions you want to process, e.g. (ses-LE ses-RE)
SESSIONS=(ses-LE ses-RE)
# ------------------------------------------------------------------------

# ---------------------- Parse arguments ---------------------------------
SUBJECT_ID=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --sub)
            SUBJECT_ID="$2"
            shift 2
            ;;
        --fprep)
            FPREP_ID="$2"
            shift 2
            ;;
        --sessions)
            IFS=',' read -r -a SESSIONS <<< "$2"
            shift 2
            ;;
        --debug)
            DEBUG=1
            shift 1
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

DEBUG=${DEBUG:-0}

if [[ -z "$SUBJECT_ID" ]]; then
    echo "ERROR: --sub <subject_id> is required (e.g. --sub sub-01 or --sub 01)"
    exit 1
fi

# Normalize subject id: remove leading 'sub-' if present, then add it back
SUBJECT_ID=${SUBJECT_ID/sub-/}
SUBJECT_ID="sub-${SUBJECT_ID}"

if [[ -z "${DIR_DATA_DERIV:-}" ]]; then
    echo "ERROR: please set DIR_DATA_DERIV environment variable to your derivatives folder (e.g. /path/to/derivatives)"
    exit 1
fi

# Define key directories
FPREP_DIR="$DIR_DATA_DERIV/$FPREP_ID/$SUBJECT_ID"
ALIGN_DIR="$DIR_DATA_DERIV/${FPREP_ID}_ALIGN/$SUBJECT_ID"

# Tools required check
REQUIRED_TOOLS=(fslmaths antsRegistrationSyNQuick.sh antsApplyTransforms WarpTimeSeriesImageMultiTransform)
for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v $tool &>/dev/null; then
        echo "Warning: required tool '$tool' not found in PATH. If missing, script may fall back to slower methods or fail."
    fi
done

# Prepare alignment directory
rm -rf "$ALIGN_DIR"
mkdir -p "$ALIGN_DIR/anat"
mkdir -p "$ALIGN_DIR/func"
TMPDIR="$ALIGN_DIR/tmp"
mkdir -p "$TMPDIR"

# ---------------------- Copy and Prepare Anatomical Files ---------------------

echo "Searching for T1w and brainmask in: $FPREP_DIR"
T1_SRC=$(find "$FPREP_DIR" -type f -name "*desc-preproc_T1w.nii.gz" | head -n 1 || true)
T1_MASK_SRC=$(find "$FPREP_DIR" -type f -name "*desc-brain_mask.nii.gz" | head -n 1 || true)

if [[ -z "$T1_SRC" ]]; then
    echo "ERROR: could not find T1w preproc in $FPREP_DIR. Available T1-like files:" >&2
    find "$FPREP_DIR" -maxdepth 3 -type f -name "*T1w*.nii.gz" || true
    exit 1
fi

# Copy files
echo "Copying T1w files to $ALIGN_DIR/anat/"
cp -n "$T1_SRC" "$ALIGN_DIR/anat/"
if [[ -n "$T1_MASK_SRC" ]]; then
    cp -n "$T1_MASK_SRC" "$ALIGN_DIR/anat/"
fi

T1w_base=$(basename "$T1_SRC")
T1w_path="$ALIGN_DIR/anat/$T1w_base"
T1w_mask_path=$(find "$ALIGN_DIR/anat" -type f -name "*brain_mask*.nii.gz" | head -n 1 || true)

if [[ -n "$T1w_path" && -n "$T1w_mask_path" ]]; then
    echo "Creating masked T1w file (T1w_brain)..."
    T1w_brain_path="${T1w_path%.nii.gz}_brain.nii.gz"
    fslmaths "$T1w_path" -mas "$T1w_mask_path" "$T1w_brain_path"
    T1w_reg_target="$T1w_brain_path"
    ANAT_HAS_SKULL="no"
else
    T1w_reg_target="$T1w_path"
    ANAT_HAS_SKULL="yes"
    echo "Warning: T1 brain mask not found. Using T1 as-is for registration."
fi

# ---------------------- Process Sessions and Runs -------------------------

for ses in "${SESSIONS[@]}"; do
    src_dir="$FPREP_DIR/$ses/func"
    if [[ ! -d "$src_dir" ]]; then
        echo "Skipping session $ses: source directory not found: $src_dir"
        continue
    fi
    echo "Copying functional files for $ses..."
    find "$src_dir" -type f \
        \( -name "*space-T1w*desc-preproc_bold.nii.gz" -o -name "*space-T1w*desc-boldref_bold.nii.gz" -o -name "*space-T1w*desc-brain_mask.nii.gz" \) \
        -exec cp -n {} "$ALIGN_DIR/func/" \;
done

mapfile -t BOLD_FILES < <(find "$ALIGN_DIR/func" -maxdepth 1 -type f -name "*desc-preproc_bold.nii.gz" | sort)

if [[ ${#BOLD_FILES[@]} -eq 0 ]]; then
    echo "ERROR: No preproc BOLD files found in $ALIGN_DIR/func"
    exit 1
fi

REF_BOLD=${BOLD_FILES[0]}
REF_BOLD_BASE=$(basename "$REF_BOLD")
REF_ID=${REF_BOLD_BASE%%.*}

echo "Reference BOLD (first run) chosen: $REF_BOLD_BASE"

REF_MEAN="$TMPDIR/${REF_ID}_mean.nii.gz"
if [[ ! -f "$REF_MEAN" ]]; then
    echo "Computing mean of reference BOLD..."
    fslmaths "$REF_BOLD" -Tmean "$REF_MEAN"
fi

declare -A RUN_MEAN
for bold in "${BOLD_FILES[@]}"; do
    base=$(basename "$bold")
    id=${base%%.*}
    mean_path="$TMPDIR/${id}_mean.nii.gz"
    if [[ ! -f "$mean_path" ]]; then
        echo "Computing mean for $base"
        fslmaths "$bold" -Tmean "$mean_path"
    fi
    RUN_MEAN["$id"]="$mean_path"
done

# ---------------------- Register run means to reference mean -----------------

REG_OUTDIR="$ALIGN_DIR/regs"
mkdir -p "$REG_OUTDIR"

declare -A RUN2REF_PREFIX
for bold in "${BOLD_FILES[@]}"; do
    base=$(basename "$bold")
    id=${base%%.*}
    mean=${RUN_MEAN[$id]}
    if [[ "$bold" == "$REF_BOLD" ]]; then
        echo "Skipping registration for reference run $id (identity transform)"
        RUN2REF_PREFIX["$id"]="IDENTITY"
        continue
    fi

    outpref="$REG_OUTDIR/run2ref_${id}_"
    echo "Registering run mean ($mean) -> reference mean ($REF_MEAN) --> prefix: $outpref"
    antsRegistrationSyNQuick.sh -d 3 -f "$REF_MEAN" -m "$mean" -o "$outpref" -t s

    # Check that expected outputs exist
    if [[ ! -f "${outpref}0GenericAffine.mat" || ! -f "${outpref}1Warp.nii.gz" ]]; then
        echo "ERROR: antsRegistrationSyNQuick.sh did not produce expected files for $id (prefix $outpref)." >&2
        ls -l "$REG_OUTDIR" || true
        exit 1
    fi
    RUN2REF_PREFIX["$id"]="$outpref"
done

# ---------------------- Register reference mean to T1w anatomy -----------------
REF2ANAT_PREF="$REG_OUTDIR/ref2anat_"
if [[ ! -f "${REF2ANAT_PREF}0GenericAffine.mat" || ! -f "${REF2ANAT_PREF}1Warp.nii.gz" ]]; then
    echo "Registering reference mean to T1w: $REF_MEAN -> $T1w_reg_target"
    antsRegistrationSyNQuick.sh -d 3 -f "$T1w_reg_target" -m "$REF_MEAN" -o "$REF2ANAT_PREF" -t s
fi

if [[ ! -f "${REF2ANAT_PREF}0GenericAffine.mat" || ! -f "${REF2ANAT_PREF}1Warp.nii.gz" ]]; then
    echo "ERROR: Registration REF->ANAT failed or output not found: ${REF2ANAT_PREF}*" >&2
    ls -l "$REG_OUTDIR" || true
    exit 1
fi

# ---------------------- Helper: apply transforms to (possibly 4D) images ------------
apply_transforms() {
    # args: input_image reference_image out_image transform_list...
    local input_image="$1"; shift
    local ref_image="$1"; shift
    local out_image="$1"; shift
    local transforms=("$@")

    # detect 4D (number of volumes > 1)
    local vols=1
    if command -v fslval &>/dev/null; then
        vols=$(fslval "$input_image" dim4 2>/dev/null || echo 1)
    else
        # fallback using nib-ls? assume 4D if filename suggests 'bold'
        vols=1
    fi

    if [[ -n "${transforms[*]}" ]]; then
        echo "Will apply transforms: ${transforms[*]}"
    fi

    # prefer WarpTimeSeriesImageMultiTransform for 4D images
    if [[ "$vols" -gt 1 && command -v WarpTimeSeriesImageMultiTransform &>/dev/null ]]; then
        echo "Using WarpTimeSeriesImageMultiTransform for 4D input: $input_image -> $out_image"
        # ImageDimension '3' works for 4D moving time-series where each volume is 3D scalar.
        WarpTimeSeriesImageMultiTransform 3 "$input_image" "$out_image" -R "$ref_image" ${transforms[*]} Linear
        return $?
    fi

    # else fall back to antsApplyTransforms (works for 3D inputs)
    if [[ "$vols" -gt 1 ]]; then
        echo "WarpTimeSeriesImageMultiTransform not available; falling back to splitting 4D into volumes and processing individually (slower)."
        # create temporary folder
        local splitdir="$TMPDIR/split_${RANDOM}"
        mkdir -p "$splitdir"
        # split and process
        local n=0
        local parts=()
        while true; do
            part="$splitdir/vol_${n}.nii.gz"
            if ! fslroi "$input_image" "$part" $n 1 &>/dev/null; then
                break
            fi
            parts+=("$part")
            n=$((n+1))
        done
        for p in "${parts[@]}"; do
            idx=$(basename "$p" | sed -e 's/vol_//; s/.nii.gz//')
            outp="$splitdir/out_vol_${idx}.nii.gz"
            antsApplyTransforms -d 3 -i "$p" -r "$ref_image" -o "$outp" ${transforms[*]}
        done
        # concatenate
        fslmerge -t "$out_image" "$splitdir/out_vol_*.nii.gz"
        rm -rf "$splitdir"
        return $?
    else
        echo "Applying antsApplyTransforms (3D image)"
        antsApplyTransforms -d 3 -i "$input_image" -r "$ref_image" -o "$out_image" ${transforms[*]}
        return $?
    fi
}

# ---------------------- Apply transforms to all BOLD runs (two-step) ------------

echo "Applying transforms to all BOLD runs. Outputs will go to $ALIGN_DIR/func/aligned_to_T1/"
OUT_FUNC_DIR="$ALIGN_DIR/func/aligned_to_T1"
mkdir -p "$OUT_FUNC_DIR"

for bold in "${BOLD_FILES[@]}"; do
    base=$(basename "$bold")
    id=${base%%.*}

    run_to_ref="$TMPDIR/${id}_to-ref.nii.gz"
    if [[ "${RUN2REF_PREFIX[$id]}" == "IDENTITY" ]]; then
        echo "Copying reference run to run_to_ref for $id (no run->ref registration needed)"
        cp -f "$bold" "$run_to_ref"
    else
        pref=${RUN2REF_PREFIX[$id]}
        aff="${pref}0GenericAffine.mat"
        warp="${pref}1Warp.nii.gz"
        if [[ ! -f "$aff" || ! -f "$warp" ]]; then
            echo "ERROR: expected run->ref transforms missing for $id: $aff or $warp" >&2
            exit 1
        fi
        echo "Applying run->ref transforms for $id using prefix $pref"
        apply_transforms "$bold" "$REF_MEAN" "$run_to_ref" "$warp" "$aff"
        if [[ $? -ne 0 || ! -f "$run_to_ref" ]]; then
            echo "ERROR: transform application failed for run->ref for $id" >&2
            exit 1
        fi
    fi

    # Now apply ref->anat transforms to run_to_ref
    ref_aff="${REF2ANAT_PREF}0GenericAffine.mat"
    ref_warp="${REF2ANAT_PREF}1Warp.nii.gz"
    if [[ ! -f "$ref_aff" || ! -f "$ref_warp" ]]; then
        echo "ERROR: expected ref->anat transforms missing: $ref_aff or $ref_warp" >&2
        exit 1
    fi

    out_final="$OUT_FUNC_DIR/${id}_space-T1w_alignedToT1.nii.gz"
    echo "Applying ref->anat transforms for $id -> $out_final"
    apply_transforms "$run_to_ref" "$T1w_reg_target" "$out_final" "$ref_warp" "$ref_aff"
    if [[ $? -ne 0 || ! -f "$out_final" ]]; then
        echo "ERROR: transform application failed for ref->anat for $id or output not found: $out_final" >&2
        ls -l "$OUT_FUNC_DIR" || true
        exit 1
    fi

    echo "Finished: $id -> $out_final"
done

# ---------------------- Cleanup and report -------------------------
rm -rf "$TMPDIR"

echo "All done. Aligned BOLDs (T1w-space) are in: $OUT_FUNC_DIR"
echo "Useful outputs and registration prefixes are in: $REG_OUTDIR"

echo "Notes:"
echo " - For 4D inputs the script prefers WarpTimeSeriesImageMultiTransform (part of ANTs) to apply 3D warps to each volume efficiently."
echo " - If WarpTimeSeriesImageMultiTransform is not available, the script will split the 4D series and apply antsApplyTransforms per-volume (slow)."
echo " - In rare ANTs builds WarpTimeSeriesImageMultiTransform has had historical issues for very large numbers of volumes; if you see artifacts, try the per-volume fallback or split into chunks."

exit 0
