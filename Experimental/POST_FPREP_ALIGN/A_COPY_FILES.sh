#!/usr/bin/env bash
#
# FLIRT-Based fMRI Preprocessing Alignment Script
# Purpose: Align all fMRIPrep BOLD runs to the first run's mean, then align the
# reference mean to the T1w anatomy, and apply the concatenated transform to all 4D BOLD runs.
#
# Usage:
#   ./fmriprep_flirt_align.sh --sub <subject_id> --deriv_dir <path/to/derivatives> \
#     [--dof_vol <6|7|9|12>] [--dof_anat <6|7|9|12>] \
#     [--fprep_id <fmriprep_dir_name>] [--sessions <ses-01,ses-02>]
#
# Requires: FSL (flirt, fslmaths, convert_xfm)
#
set -euo pipefail
IFS=$'\n\t'

# ---------------------- 1. Argument Parsing and Validation -----------------------

# Set default values
SUBJECT_ID=""
DERIV_DIR=$DIR_DATA_DERIV
SRC_DIR=$DIR_DATA_SOURCE
FPREP_ID="fmriprep"
VALID_DOFS=(6 7 9 12)
SESSIONS=(ses-LE ses-RE)

# Function to check if a value is in an array
contains_element () {
  local e match="$1"
  shift
  for e; do [[ "$e" == "$match" ]] && return 0; done
  return 1
}

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --sub)
            SUBJECT_ID="$2"; shift 2;;
        --deriv_dir)
            DERIV_DIR="$2"; shift 2;;
        --fprep_id)
            FPREP_ID="$2"; shift 2;;
        *)
            echo "ERROR: Unknown option: $1"; exit 1;;
    esac
done

# Normalize subject ID
SUBJECT_ID=${SUBJECT_ID/sub-/}
SUBJECT_ID="sub-${SUBJECT_ID}"

# Print summary
echo "Subject ID: $SUBJECT_ID"
echo "Derivatives Dir: $DERIV_DIR"
echo "fMRIPrep Dir Name: $FPREP_ID"
echo "------------------------------------------"


# ---------------------- 2. Directory Setup ---------------------------------------

FPREP_IN_DIR="$DERIV_DIR/$FPREP_ID/$SUBJECT_ID"
SRC_IN_DIR="$SRC_DIR/$SUBJECT_ID"
# if [[ ! -d "$FPREP_IN_DIR" ]]; then
#     echo "ERROR: fMRIPrep input directory not found: $FPREP_IN_DIR"; exit 1
# fi

# Define output directory structure
ALIGN_OUT_DIR="$DERIV_DIR/${FPREP_ID}_POST_ALIGN/$SUBJECT_ID"
ANAT_DIR="$ALIGN_OUT_DIR/anat"
FUNC_DIR="$ALIGN_OUT_DIR/func"
MEAN_DIR="$ALIGN_OUT_DIR/masked_mean"

mkdir -p "$ANAT_DIR" "$FUNC_DIR" "$MEAN_DIR"


# ---------------------- 3. Anatomical Preparation --------------------------------
# [1] Mask the T1 from freesurfer
T1W_ANAT_SRC="${DIR_DATA_DERIV}/freesurfer/${SUBJECT_ID}/mri/orig.mgz"
T1W_MASK_SRC="${DIR_DATA_DERIV}/freesurfer/${SUBJECT_ID}/mri/brainmask.mgz"
T1W_ANAT_REF="$ANAT_DIR/T1w_preproc.nii.gz"
T1W_MASK_REF="$ANAT_DIR/T1w_mask.nii.gz"
T1W_MASKED="$ANAT_DIR/T1w_preproc_masked.nii.gz"
if [ ! -f "$T1W_ANAT_REF" ]; then 
    cp -n "$T1W_ANAT_SRC" "$T1W_ANAT_REF"
    cp -n "$T1W_MASK_SRC" "$T1W_MASK_REF"
fi

T1W_MASKED_mgz="${ALIGN_OUT_DIR}/anat/T1_masked.mgz"
if [ ! -f "$T1W_MASKED" ]; then   
    mri_mask ${T1W_ANAT_SRC} ${T1W_MASK_SRC} ${T1W_MASKED_mgz}
    mri_convert --in_type mgz --out_type nii ${T1W_MASKED_mgz} ${T1W_MASKED}
    rm -rf $T1W_MASKED_mgz
fi

# T2W_ANAT_SRC="${DIR_DATA_DERIV}/freesurfer/${SUBJECT_ID}/mri/T2.mgz"
# T2W_ANAT_REF="$ANAT_DIR/T2w_preproc.nii.gz"
# T2W_MASKED="$ANAT_DIR/T2w_preproc_masked.nii.gz"
# T2W_MASKED_mgz="${ALIGN_OUT_DIR}/anat/T2_masked.mgz"
# if [ ! -f "$T2W_MASKED" ]; then   
#     mri_mask ${T2W_ANAT_SRC} ${T1W_MASK_SRC} ${T2W_MASKED_mgz}
#     mri_convert --in_type mgz --out_type nii ${T2W_MASKED_mgz} ${T2W_MASKED}
#     rm -rf $T2W_MASKED_mgz
# fi

# ---------------------- 4. Functional File Discovery -----------------------------
for ses in "${SESSIONS[@]}"; do
    src_dir="$FPREP_IN_DIR/$ses/func"
    if [[ ! -d "$src_dir" ]]; then
        echo "Skipping session $ses: source directory not found: $src_dir"
        continue
    fi
    echo "Copying functional files for $ses..."
    find "$src_dir" -type f \
        \( -name "*space-T1w*desc-preproc_bold.nii.gz" -o -name "*space-T1w*desc-boldref_bold.nii.gz"  \) \
        -exec cp -n {} "$ALIGN_OUT_DIR/func/" \;

    find "$src_dir" -type f \
        \( -name "*space-T1w_desc-brain_mask.nii.gz"  \) \
        -exec cp -n {} "$ALIGN_OUT_DIR/func/" \;        
done

mapfile -t BOLD_FILES < <(find "$ALIGN_OUT_DIR/func" -maxdepth 1 -type f -name "*desc-preproc_bold.nii.gz" | sort)
mapfile -t BMASK_FILES < <(find "$ALIGN_OUT_DIR/func" -maxdepth 1 -type f -name "*desc-brain_mask.nii.gz" | sort)
if [[ ${#BOLD_FILES[@]} -eq 0 ]]; then
    echo "ERROR: No preproc BOLD files found in $ALIGN_OUT_DIR/func"
    exit 1
fi

# ***** MASK & MEAN BOLD
declare -A RUN_MEAN
for i in "${!BOLD_FILES[@]}"; do
    bold=${BOLD_FILES[$i]}
    mask=${BMASK_FILES[$i]}
    base=$(basename "$bold")
    id=${base%%.*}
    mean_path="$MEAN_DIR/${id}_mean.nii.gz"
    if [[ ! -f "$mean_path" ]]; then
        echo "Computing mean for $base"
        fslmaths "$bold" -Tmean "$MEAN_DIR/tmp.nii.gz"
        fslmaths "$MEAN_DIR/tmp.nii.gz" -mas "$mask" "$mean_path"
    fi
    RUN_MEAN["$id"]="$mean_path"
done