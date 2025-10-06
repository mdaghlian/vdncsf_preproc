#!/usr/bin/env bash
#
# ANTs-Based fMRI Preprocessing Alignment Script (with mean-image QC stage)
# Purpose: Align all fMRIPrep BOLD runs to the first run's mean, align the
# reference mean to the T1w anatomy, compose transforms, apply to mean images
# (quick QC), then optionally apply to the full 4D BOLD runs.
# Uses: ANTs (antsRegistration, antsApplyTransforms, ComposeMultiTransform)
#
set -euo pipefail
IFS=$'\n\t'

# ---------------------- 1. Argument Parsing and Validation -----------------------

# Set default values
SUBJECT_ID=""
DERIV_DIR=${DIR_DATA_DERIV:-""}
SRC_DIR=${DIR_DATA_SOURCE:-""}
REG_VOL="rigid+affine"       # options: rigid, affine, rigid+affine, syn
REG_ANAT="rigid+affine+syn"  # options: rigid+affine, affine+syn, rigid+affine+syn, syn
FPREP_ID="fmriprep"
PRESET="precise"             # options: fast, medium, precise
MEANS_ONLY=0                 # if 1, run the mean-only (QC) stage and exit
FPREP_START="bold" # T1w
FOUT_ID=""

usage(){
    cat <<EOF
Usage: $0 [--sub SUBID] [--deriv_dir PATH] [--reg_vol PRES] [--reg_anat PRES] [--preset fast|medium|precise] [--fprep_id NAME] [--means_only]
  --sub         subject id (with or without "sub-")
  --deriv_dir   derivatives directory (overrides default)
  --reg_vol     inter-run registration (rigid|affine|rigid+affine|syn)
  --reg_anat    reference->anat registration (rigid+affine|affine+syn|rigid+affine+syn|syn)
  --preset      preset choice for iterations/shrink-factors (fast/medium/precise)
  --fprep_id    name of fMRIPrep directory (default: fmriprep)
  --means_only  run only the mean-image transform stage and exit (quick QC)
EOF
    exit 1
}

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --sub)
            SUBJECT_ID="$2"; shift 2;;
        --deriv_dir)
            DERIV_DIR="$2"; shift 2;;
        --reg_vol)
            REG_VOL="$2"; shift 2;;
        --reg_anat)
            REG_ANAT="$2"; shift 2;;
        --preset)
            PRESET="$2"; shift 2;;
        --fprep_id)
            FPREP_ID="$2"; shift 2;;
        --means_only|--qc_only)
            MEANS_ONLY=1; shift 1;;
        --fprep_start)
            FPREP_START="$2"; shift 2;;     
        --fout_id)
            FOUT_ID="$2"; shift 2;;                 
        -*)
            echo "ERROR: Unknown option: $1"; usage;;
        *)
            break;;
    esac
done

if [[ -z "$SUBJECT_ID" ]]; then
    echo "ERROR: --sub is required."
    usage
fi

# Normalize subject ID
SUBJECT_ID=${SUBJECT_ID/sub-/}
SUBJECT_ID="sub-${SUBJECT_ID}"

# sanity check ANTs existence
for cmd in antsRegistration antsApplyTransforms ComposeMultiTransform; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: $cmd not found on PATH. Please install ANTs."
        exit 1
    fi
done

# CALL THE COPY SCRIPT (assumes it defines BOLD_FILES[], RUN_MEAN[], T1W_MASKED, ALIGN_OUT_DIR, etc.)
source ./A_COPY_FILES.sh --sub "$SUBJECT_ID" --deriv_dir "$DERIV_DIR" --fprep_id "$FPREP_ID"

echo "--- ANTs Alignment Script Configuration ---"
echo "Subject ID: $SUBJECT_ID"
echo "Derivatives Dir: $DERIV_DIR"
echo "fMRIPrep Dir Name: $FPREP_ID"
echo "Inter-run registration (vol->ref): $REG_VOL"
echo "Ref->Anat registration: $REG_ANAT"
echo "Preset: $PRESET"
echo "Means-only (QC) mode: $MEANS_ONLY"
echo "------------------------------------------"

# Output directories (mirror your original structure)
TALIGN_DIR="${ALIGN_OUT_DIR}/ants"
COREG_DIR="${TALIGN_DIR}/coreg_ref_${REG_VOL}"
XFM_DIR="${TALIGN_DIR}/xfm_ref_${REG_VOL}"
mkdir -p "$COREG_DIR" "$XFM_DIR"

# ******** TAKE FIRST RUN - as reference
REF_BOLD=${BOLD_FILES[0]}
REF_BOLD_BASE=$(basename "$REF_BOLD")
REF_ID=${REF_BOLD_BASE%%.*}
REF_MEAN=${RUN_MEAN["$REF_ID"]}

echo "Reference BOLD (first run) chosen: $REF_BOLD_BASE"
echo "Reference mean: $REF_MEAN"

# ---------------------- Preset parameter sets -----------------------
case "$PRESET" in
    fast)
        SHRINK_FACTORS="8x4x2"
        SMOOTHING_SIGMAS="3x2x1"
        CONVERGE="100x50x20"
        SYNS="20x10x5"
        ;;
    medium)
        SHRINK_FACTORS="8x4x2x1"
        SMOOTHING_SIGMAS="3x2x1x0"
        CONVERGE="1000x500x200x50"
        SYNS="50x40x20x10"
        ;;
    precise|*)
        SHRINK_FACTORS="8x4x2x1"
        SMOOTHING_SIGMAS="3x2x1x0"
        CONVERGE="2000x1000x500x100"
        SYNS="100x70x50x20"
        ;;
esac

MATTES_SAMPLES=32
CC_RADIUS=4

# ---------------------- 5. Step 1: Inter-Run Registration (BOLD mean → Reference mean) -----------------

declare -A RUN2REF_AFFINE
declare -A RUN2REF_WARP

for bold_path in "${BOLD_FILES[@]}"; do
    base=$(basename "$bold_path" .nii.gz)
    id=${base%%.*}
    mean_path="${RUN_MEAN[$id]}"
    PREFIX="${XFM_DIR}/${base}_to_ref_"
    RUN2REF_AFFINE["$bold_path"]="${PREFIX}0GenericAffine.mat"
    RUN2REF_WARP["$bold_path"]="${PREFIX}1Warp.nii.gz"

    # a. Reference Run (identity)
    if [[ "$bold_path" == "$REF_BOLD" ]]; then
        echo "Reference run: copying mean to coreg dir"
        cp -n "$REF_MEAN" "$COREG_DIR/${base}_mean_in_ref.nii.gz" || true
        unset RUN2REF_AFFINE["$bold_path"]
        unset RUN2REF_WARP["$bold_path"]
        continue
    fi

    # b. Other Runs (ANTs)
    if [[ -f "${RUN2REF_AFFINE[$bold_path]}" || -f "${RUN2REF_WARP[$bold_path]}" ]]; then
        echo "Found existing run->ref transform(s) for $base. Skipping registration."
        continue
    fi

    echo "ANTs registration (Moving: ${base}_mean -> Reference: ${REF_BOLD_BASE}_mean) REG_VOL=$REG_VOL"

    ARGS=( --dimensionality 3 --float 0 --output [${PREFIX},${COREG_DIR}/${base}_mean_in_ref.nii.gz] \
           --interpolation Linear --winsorize-image-intensities [0.005,0.995] --use-histogram-matching 0 )

    if [[ "$REG_VOL" == "rigid" ]]; then
        ARGS+=( --transform Rigid[0.1] \
                --metric CC["$REF_MEAN","$mean_path",1,${CC_RADIUS}] \
                --convergence [${CONVERGE}] --shrink-factors ${SHRINK_FACTORS} --smoothing-sigmas ${SMOOTHING_SIGMAS} )
    elif [[ "$REG_VOL" == "affine" ]]; then
        ARGS+=( --transform Affine[0.1] \
                --metric Mattes["$REF_MEAN","$mean_path",1,${MATTES_SAMPLES}] \
                --convergence [${CONVERGE}] --shrink-factors ${SHRINK_FACTORS} --smoothing-sigmas ${SMOOTHING_SIGMAS} )
    elif [[ "$REG_VOL" == "rigid+affine" ]]; then
        ARGS+=( --transform Rigid[0.1] \
                --metric CC["$REF_MEAN","$mean_path",1,${CC_RADIUS}] \
                --convergence [${CONVERGE}] --shrink-factors ${SHRINK_FACTORS} --smoothing-sigmas ${SMOOTHING_SIGMAS} )
        ARGS+=( --transform Affine[0.1] \
                --metric Mattes["$REF_MEAN","$mean_path",1,${MATTES_SAMPLES}] \
                --convergence [${CONVERGE}] --shrink-factors ${SHRINK_FACTORS} --smoothing-sigmas ${SMOOTHING_SIGMAS} )
    elif [[ "$REG_VOL" == "syn" ]]; then
        ARGS+=( --transform Affine[0.1] \
                --metric Mattes["$REF_MEAN","$mean_path",1,${MATTES_SAMPLES}] \
                --convergence [1000x500x250,1e-6,10] --shrink-factors 8x4x2 --smoothing-sigmas 3x2x1 )
        ARGS+=( --transform SyN[0.1,3,0] \
                --metric CC["$REF_MEAN","$mean_path",1,${CC_RADIUS}] \
                --convergence [${SYNS}] --shrink-factors ${SHRINK_FACTORS} --smoothing-sigmas ${SMOOTHING_SIGMAS} )
    else
        echo "Unknown REG_VOL option: $REG_VOL"
        exit 1
    fi

    echo "Running antsRegistration for run->ref: ${PREFIX}"
    break
    antsRegistration "${ARGS[@]}"
    
    echo "Finished antsRegistration for $base"

done

# ---------------------- 6. Step 2: Functional-to-Anatomical Registration (Reference mean → T1w) -----------------

COREG_ANAT_DIR="${TALIGN_DIR}/coreg_ref${REG_VOL}_an_${REG_ANAT}"
XFM_TOTAL_DIR="${TALIGN_DIR}/xfm${REG_VOL}_an${REG_ANAT}"
mkdir -p "${COREG_ANAT_DIR}" "${XFM_TOTAL_DIR}"

REF2ANAT_PREFIX="${TALIGN_DIR}/${REF_ID}_to_T1w_"
REF2ANAT_AFFINE="${REF2ANAT_PREFIX}0GenericAffine.mat"
REF2ANAT_WARP="${REF2ANAT_PREFIX}1Warp.nii.gz"
REF2ANAT_OUT="${COREG_ANAT_DIR}/${REF_ID}_mean_in_T1w.nii.gz"

if [[ -f "$REF2ANAT_AFFINE" || -f "$REF2ANAT_WARP" ]]; then
    echo "Found existing ref->anat transforms. Skipping registration."
else
    echo "ANTs registration (Moving: Reference mean -> Fixed: T1w anatomical) REG_ANAT=$REG_ANAT"
    ARGS=( --dimensionality 3 --float 0 --output [${REF2ANAT_PREFIX},${REF2ANAT_OUT}] \
           --interpolation Linear --winsorize-image-intensities [0.005,0.995] --use-histogram-matching 1 )

    if [[ "$REG_ANAT" == "rigid+affine" ]]; then
        ARGS+=( --transform Rigid[0.1] \
                --metric Mattes["$T1W_MASKED","$REF_MEAN",1,${MATTES_SAMPLES}] \
                --convergence [${CONVERGE}] --shrink-factors ${SHRINK_FACTORS} --smoothing-sigmas ${SMOOTHING_SIGMAS} )
        ARGS+=( --transform Affine[0.1] \
                --metric Mattes["$T1W_MASKED","$REF_MEAN",1,${MATTES_SAMPLES}] \
                --convergence [${CONVERGE}] --shrink-factors ${SHRINK_FACTORS} --smoothing-sigmas ${SMOOTHING_SIGMAS} )
    elif [[ "$REG_ANAT" == "affine+syn" ]]; then
        ARGS+=( --transform Affine[0.1] \
                --metric Mattes["$T1W_MASKED","$REF_MEAN",1,${MATTES_SAMPLES}] \
                --convergence [${CONVERGE}] --shrink-factors ${SHRINK_FACTORS} --smoothing-sigmas ${SMOOTHING_SIGMAS} )
        ARGS+=( --transform SyN[0.1,3,0] \
                --metric CC["$T1W_MASKED","$REF_MEAN",1,${CC_RADIUS}] \
                --convergence [${SYNS}] --shrink-factors ${SHRINK_FACTORS} --smoothing-sigmas ${SMOOTHING_SIGMAS} )
    elif [[ "$REG_ANAT" == "rigid+affine+syn" || "$REG_ANAT" == "rigid+affine+SyN" ]]; then
        ARGS+=( --transform Rigid[0.1] \
                --metric Mattes["$T1W_MASKED","$REF_MEAN",1,${MATTES_SAMPLES}] \
                --convergence [${CONVERGE}] --shrink-factors ${SHRINK_FACTORS} --smoothing-sigmas ${SMOOTHING_SIGMAS} )
        ARGS+=( --transform Affine[0.1] \
                --metric Mattes["$T1W_MASKED","$REF_MEAN",1,${MATTES_SAMPLES}] \
                --convergence [${CONVERGE}] --shrink-factors ${SHRINK_FACTORS} --smoothing-sigmas ${SMOOTHING_SIGMAS} )
        ARGS+=( --transform SyN[0.1,3,0] \
                --metric CC["$T1W_MASKED","$REF_MEAN",1,${CC_RADIUS}] \
                --convergence [${SYNS}] --shrink-factors ${SHRINK_FACTORS} --smoothing-sigmas ${SMOOTHING_SIGMAS} )
    elif [[ "$REG_ANAT" == "syn" ]]; then
        ARGS+=( --transform SyN[0.1,3,0] \
                --metric CC["$T1W_MASKED","$REF_MEAN",1,${CC_RADIUS}] \
                --convergence [${SYNS}] --shrink-factors ${SHRINK_FACTORS} --smoothing-sigmas ${SMOOTHING_SIGMAS} )
    else
        echo "Unknown REG_ANAT option: $REG_ANAT"
        exit 1
    fi

    echo "Running antsRegistration for REF->T1w: prefix=${REF2ANAT_PREFIX}"
    antsRegistration "${ARGS[@]}"
    echo "Finished REF->T1w registration"
fi
exit 1
# ---------------- Compose transforms and apply to MEAN images (Quick QC) ------------------------

echo "--- Composing transforms and applying to MEAN images (quick QC) ---"

for bold_path in "${BOLD_FILES[@]}"; do
    base=$(basename "$bold_path" .nii.gz)
    id=${base%%.*}
    mean_path="${RUN_MEAN[$id]}"

    RUN_PREFIX="${XFM_DIR}/${base}_to_ref_"
    RUN_AFFINE="${RUN_PREFIX}0GenericAffine.mat"
    RUN_WARP="${RUN_PREFIX}1Warp.nii.gz"

    REF_AFFINE="${REF2ANAT_AFFINE}"
    REF_WARP="${REF2ANAT_WARP}"

    COMPOSITE="${XFM_TOTAL_DIR}/${base}_to_T1w_Composed.h5"
    MEAN_IN_T1W="${COREG_ANAT_DIR}/${base}_ANTs_mean_T1w.nii.gz"

    # Build ComposeMultiTransform args: run->ref first, then ref->anat
    COMPOSE_ARGS=(3 "${COMPOSITE}" -R "$T1W_MASKED")
    if [[ "$bold_path" != "$REF_BOLD" ]]; then
        [[ -f "$RUN_WARP" ]] && COMPOSE_ARGS+=( "$RUN_WARP" )
        [[ -f "$RUN_AFFINE" ]] && COMPOSE_ARGS+=( "$RUN_AFFINE" )
    fi
    [[ -f "$REF_WARP" ]] && COMPOSE_ARGS+=( "$REF_WARP" )
    [[ -f "$REF_AFFINE" ]] && COMPOSE_ARGS+=( "$REF_AFFINE" )

    if [[ ${#COMPOSE_ARGS[@]} -le 3 ]]; then
        echo "No transforms available to compose for $base. Skipping mean."
        continue
    fi

    if [[ ! -f "$COMPOSITE" ]]; then
        echo "Composing transforms for $base -> $COMPOSITE"
        ComposeMultiTransform "${COMPOSE_ARGS[@]}"
    else
        echo "Found existing composite transform for $base: $COMPOSITE"
    fi

    # Apply composite to the mean image (quick QC)
    if [[ ! -f "$MEAN_IN_T1W" ]]; then
        echo "Applying composite transform to mean image: $mean_path -> $MEAN_IN_T1W"
        antsApplyTransforms -d 3 -i "$mean_path" -r "$T1W_MASKED" -o "$MEAN_IN_T1W" -t "$COMPOSITE" --interpolation Linear
    else
        echo "Found existing mean-in-T1w for $base: $MEAN_IN_T1W"
    fi

done

echo "Mean-image QC outputs are in: $COREG_ANAT_DIR"
if [[ $MEANS_ONLY -eq 1 ]]; then
    echo "Exiting after mean-image QC stage (means_only mode). Inspect outputs before resampling full 4D."
    exit 0
fi

# ---------------- Apply composite transforms to full 4D BOLD runs ------------------------

echo "--- Applying composite transforms to full 4D BOLD runs ---"

for bold_path in "${BOLD_FILES[@]}"; do
    base=$(basename "$bold_path" .nii.gz)
    COMPOSITE="${XFM_TOTAL_DIR}/${base}_to_T1w_Composed.h5"
    R_I_T1W="${COREG_ANAT_DIR}/${base}_ANTs_T1w.nii.gz"

    if [[ ! -f "$COMPOSITE" ]]; then
        echo "Composite transform missing for $base. Attempting to compose now."

        RUN_PREFIX="${XFM_DIR}/${base}_to_ref_"
        RUN_AFFINE="${RUN_PREFIX}0GenericAffine.mat"
        RUN_WARP="${RUN_PREFIX}1Warp.nii.gz"
        REF_AFFINE="${REF2ANAT_AFFINE}"
        REF_WARP="${REF2ANAT_WARP}"

        COMPOSE_ARGS=(3 "${COMPOSITE}" -R "$T1W_MASKED")
        if [[ "$bold_path" != "$REF_BOLD" ]]; then
            [[ -f "$RUN_WARP" ]] && COMPOSE_ARGS+=( "$RUN_WARP" )
            [[ -f "$RUN_AFFINE" ]] && COMPOSE_ARGS+=( "$RUN_AFFINE" )
        fi
        [[ -f "$REF_WARP" ]] && COMPOSE_ARGS+=( "$REF_WARP" )
        [[ -f "$REF_AFFINE" ]] && COMPOSE_ARGS+=( "$REF_AFFINE" )

        if [[ ${#COMPOSE_ARGS[@]} -le 3 ]]; then
            echo "No transforms available to compose for $base. Skipping full 4D resampling."
            continue
        fi

        ComposeMultiTransform "${COMPOSE_ARGS[@]}"
    fi

    if [[ ! -f "$R_I_T1W" ]]; then
        echo "Applying composite transform to 4D BOLD: $bold_path -> $R_I_T1W"
        antsApplyTransforms -d 3 -i "$bold_path" -r "$T1W_MASKED" -o "$R_I_T1W" -t "$COMPOSITE" --interpolation Linear
    else
        echo "Found existing resliced BOLD: $R_I_T1W. Skipping."
    fi
done

echo "--- Script Complete ---"
echo "Mean-image QC files: $COREG_ANAT_DIR (files named *_ANTs_mean_T1w.nii.gz)"
echo "Final resliced BOLD files: $COREG_ANAT_DIR (files named *_ANTs_T1w.nii.gz)"
echo "Composite transforms: $XFM_TOTAL_DIR"
exit 0
