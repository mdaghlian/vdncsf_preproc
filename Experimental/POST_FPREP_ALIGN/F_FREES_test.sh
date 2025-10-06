#!/usr/bin/env bash
#
# FreeSurfer-Based fMRI Preprocessing Alignment Script
# Purpose: Align all fMRIPrep BOLD runs to the first run's mean (inter-run),
# then align the reference mean to the T1w anatomy using FreeSurfer (bbregister or robust register),
# concatenate transforms (LTA), and apply to all 4D BOLD runs.
#
set -euo pipefail
IFS=$'\n\t'

# ---------------------- 1. Argument Parsing and Validation -----------------------
SUBJECT_ID=""
DERIV_DIR=${DIR_DATA_DERIV:-""}
SRC_DIR=${DIR_DATA_SOURCE:-""}
DOF_VOL=6          # 6 (rigid) or 12 (affine) for run->ref
DOF_ANAT=6         # 6 (bbregister) or 12 (affine) for ref->T1
FPREP_ID="fmriprep"
SESSIONS=(ses-LE ses-RE)
FS_SUBJ=""         # FreeSurfer subject name (usually matches SUBJECT_ID)
SUBJECTS_DIR=${SUBJECTS_DIR:-""}  # honor env var if set
FPREP_START="bold" # T1w
FOUT_ID=""

# helper to check membership
contains_element () {
  local e match="$1"
  shift
  for e; do [[ "$e" == "$match" ]] && return 0; done
  return 1
}

# Parse args
while [[ $# -gt 0 ]]; do
    case "$1" in
        --sub) SUBJECT_ID="$2"; shift 2;;
        --deriv_dir) DERIV_DIR="$2"; shift 2;;
        --dof_vol) DOF_VOL="$2"; shift 2;;
        --dof_anat) DOF_ANAT="$2"; shift 2;;
        --fprep_id) FPREP_ID="$2"; shift 2;;
        --subjects_dir) SUBJECTS_DIR="$2"; shift 2;;
        --fs_subj) FS_SUBJ="$2"; shift 2;;
        --target) TARGET="$2"; shift 2;;
        --fprep_start)
            FPREP_START="$2"; shift 2;;     
        --fout_id)
            FOUT_ID="$2"; shift 2;;             
        *) echo "ERROR: Unknown option: $1"; exit 1;;
    esac
done

if [[ -z "$SUBJECT_ID" ]]; then
    echo "ERROR: --sub is required"
    exit 1
fi

# Normalize
SUBJECT_ID=${SUBJECT_ID/sub-/}
SUBJECT_ID="sub-${SUBJECT_ID}"
if [[ -z "$FS_SUBJ" ]]; then
    FS_SUBJ="$SUBJECT_ID"
fi

# CALL THE COPY SCRIPT (user environment)
source ./A_COPY_FILES.sh --sub $SUBJECT_ID --deriv_dir $DERIV_DIR --fprep_id $FPREP_ID

echo "--- FreeSurfer Alignment Script Configuration ---"
echo "Subject ID: $SUBJECT_ID"
echo "FreeSurfer subject: $FS_SUBJ"
echo "Subjects dir: ${SUBJECTS_DIR:-\$SUBJECTS_DIR env var}"
echo "Derivatives Dir: $DERIV_DIR"
echo "fMRIPrep Dir Name: $FPREP_ID"
echo "DOF (Vol->Ref): $DOF_VOL"
echo "DOF (Ref->Anat): $DOF_ANAT"
echo "-----------------------------------------------"

# make output dirs (using variables from A_COPY_FILES.sh environment)
TALIGN_DIR="${ALIGN_OUT_DIR:-./align_out}/freesurfer"
COREG_DIR="$TALIGN_DIR/coreg_ref${DOF_VOL}"
XFM_DIR="$TALIGN_DIR/lta_ref${DOF_VOL}"
mkdir -p "$COREG_DIR" "$XFM_DIR"

# ******** TAKE FIRST RUN - as reference 
REF_BOLD=${BOLD_FILES[0]}
REF_BOLD_BASE=$(basename "$REF_BOLD")
REF_ID=${REF_BOLD_BASE%%.*}
REF_MEAN=${RUN_MEAN["$REF_ID"]}

echo "Reference BOLD (first run) chosen: $REF_BOLD_BASE"

# ---------------------- Inter-Run Registration (BOLD mean → Reference mean) -----------------
declare -A RUN2REF_LTA
declare -A MCOREG_RUN2REF

for bold_path in "${BOLD_FILES[@]}"; do
    base=$(basename "$bold_path" .nii.gz)
    id=${base%%.*}
    mean_path="${RUN_MEAN[$id]}"
    OUTPUT_LTA="$XFM_DIR/${base}_to_ref.lta"
    RUN2REF_LTA["$bold_path"]="$OUTPUT_LTA"
    TCOREG="$COREG_DIR/${base}_mean_in_ref.nii.gz"
    MCOREG_RUN2REF["${id}"]="$TCOREG"

    if [[ "$bold_path" == "$REF_BOLD" ]]; then
        # create identity LTA for reference -> reference (header-only)
        if [[ ! -f "$OUTPUT_LTA" ]]; then
            echo "Reference run: creating identity LTA: $OUTPUT_LTA"
            lta_convert --inlta identity.nofile --src "$REF_MEAN" --trg "$REF_MEAN" --outlta "$OUTPUT_LTA"
            cp "$REF_MEAN" "$TCOREG"
        else
            echo "Found existing identity LTA: $OUTPUT_LTA"
        fi
        continue
    fi

    if [[ -f "$OUTPUT_LTA" ]]; then
        echo "Found existing run->ref LTA for $base. Skipping mri_robust_register."
    else
        echo "mri_robust_register (Moving: ${base}_mean -> Reference: ${REF_BOLD_BASE}_mean)"
        # choose affine flag based on DOF_VOL
        AFFINE_FLAG=""
        if [[ "$DOF_VOL" -eq 12 ]]; then
            AFFINE_FLAG="--affine"
        fi
        mri_robust_register --mov "$mean_path" --dst "$REF_MEAN" --lta "$OUTPUT_LTA" $AFFINE_FLAG --satit --iscale
    fi

    # Resample moving mean into reference FOV (create per-run mean in ref space)
    if [[ ! -f "$TCOREG" ]]; then
        echo "Resampling mean to reference space: $mean_path -> $TCOREG"
        # Use mri_vol2vol (uses the .lta to resample)
        mri_vol2vol --mov "$mean_path" --targ "$REF_MEAN" --lta "$OUTPUT_LTA" --o "$TCOREG" --no-save-reg
    else
        echo "Found existing resampled mean in ref space: $TCOREG"
    fi
done
exit 1
# ---- CREATE GRAND MEAN using FreeSurfer tools (mri_concat --mean)
GRAND_MEAN="$COREG_DIR/A_GRAND_MEAN.nii.gz"
echo "Creating GRAND_MEAN -> $GRAND_MEAN"
# collect resampled mean files into an array for mri_concat
concat_inputs=()
for bold_path in "${BOLD_FILES[@]}"; do
    base=$(basename "$bold_path" .nii.gz)
    id=${base%%.*}
    TCOREG="${MCOREG_RUN2REF[$id]}"
    concat_inputs+=("$TCOREG")
done

# mri_concat accepts multiple inputs and can compute mean with --mean
if [[ ${#concat_inputs[@]} -gt 0 ]]; then
    # build command
    cmd=(mri_concat --mean)
    for f in "${concat_inputs[@]}"; do cmd+=("$f"); done
    # cmd+=("$GRAND_MEAN")
    if [[ ! -f "$GRAND_MEAN" ]]; then
        echo "Running: ${cmd[*]}"
        "${cmd[@]}" --o "${GRAND_MEAN}"
    else
        echo "Grand mean already exists, skipping."
    fi
else
    echo "No resampled means found to create GRAND_MEAN; skipping."
fi
# ---------------------- Functional-to-Anatomical Registration (Reference mean → T1w) -----------------
COREG_ANAT_DIR="$TALIGN_DIR/coreg_ref${DOF_VOL}_an${DOF_ANAT}"
XFM_TOTAL_DIR="$TALIGN_DIR/lta${DOF_VOL}_an${DOF_ANAT}"
mkdir -p "${COREG_ANAT_DIR}" "${XFM_TOTAL_DIR}"
REF2ANAT_LTA="$TALIGN_DIR/${REF_ID}_to_T1w.lta"
REF2ANAT_OUT="$COREG_ANAT_DIR/${REF_ID}_mean_in_T1w.nii.gz"

if [[ -f "$REF2ANAT_LTA" ]]; then
    echo "Found existing ref->anat LTA: $REF2ANAT_LTA. Skipping registration."
else
    if [[ "$DOF_ANAT" -eq 6 ]]; then
        # bbregister requires recon-all output in SUBJECTS_DIR
        if [[ -z "${SUBJECTS_DIR:-}" ]]; then
            echo "ERROR: SUBJECTS_DIR must be set (pass with --subjects_dir or export SUBJECTS_DIR)."
            exit 1
        fi
        if [[ ! -d "$SUBJECTS_DIR/$FS_SUBJ" ]]; then
            echo "ERROR: FreeSurfer subject directory not found: $SUBJECTS_DIR/$FS_SUBJ"
            exit 1
        fi
        echo "bbregister (Boundary-Based Registration): Reference mean -> T1w (6 DOF, BBR)"
        # output LTA and (optionally) a register.dat (tkregister style)
        bbregister --s "$FS_SUBJ" --mov "$REF_MEAN" --lta "$REF2ANAT_LTA" --bold --init-coreg
        # (optionally resample)
        mri_vol2vol --mov "$REF_MEAN" --targ "$SUBJECTS_DIR/$FS_SUBJ/mri/orig.mgz" --lta "$REF2ANAT_LTA" --o "$REF2ANAT_OUT" --no-save-reg
    else
        # 12 DOF affine: use mri_robust_register --affine against the (masked) T1
        echo "mri_robust_register (affine) Reference mean -> T1w (12 DOF)"
        mri_robust_register --mov "$REF_MEAN" --dst "$T1W_MASKED" --lta "$REF2ANAT_LTA" --affine --satit --iscale
        mri_vol2vol --mov "$REF_MEAN" --targ "$T1W_MASKED" --lta "$REF2ANAT_LTA" --o "$REF2ANAT_OUT" --no-save-reg
    fi
fi

# *********************** Compose and apply transforms per-run
for bold_path in "${BOLD_FILES[@]}"; do
    base=$(basename "$bold_path" .nii.gz)
    id=${base%%.*}
    RUN_LTA="${RUN2REF_LTA[$bold_path]}"         # run->ref LTA
    XFM_REF_TO_ANAT="$REF2ANAT_LTA"              # ref->anat LTA
    XFM_TOTAL="$XFM_TOTAL_DIR/${base}_to_T1w_total.lta"
    R_I_T1W="$COREG_ANAT_DIR/${base}_FS_T1w.nii.gz"

    if [[ ! -f "$XFM_TOTAL" ]]; then
        echo "Composing total transform for $base: total = ref2anat * run2ref"
        # mri_concatenate_lta <lta1> <lta2> <out.lta> where out = lta2 * lta1
        mri_concatenate_lta "$RUN_LTA" "$XFM_REF_TO_ANAT" "$XFM_TOTAL"
    else
        echo "Found existing total LTA: $XFM_TOTAL"
    fi

    if [[ ! -f "$R_I_T1W" ]]; then
        echo "Applying total transform to 4D BOLD: $bold_path -> $R_I_T1W"
        # mri_convert supports --apply_transform (-at), which can resample 4D NIfTI with an LTA
        # alternative: loop over frames and use mri_vol2vol if needed.
        mri_convert --apply_transform "$XFM_TOTAL" "$bold_path" "$R_I_T1W"
    else
        echo "Final resliced BOLD already exists: $R_I_T1W"
    fi
done

echo "--- Script Complete ---"
echo "Final resliced BOLD files are located in: $COREG_ANAT_DIR"
echo "LTA transforms are located in: $XFM_TOTAL_DIR"
