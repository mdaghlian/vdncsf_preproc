#!/usr/bin/env bash
#
# COPY OUT USEFUL STUFF FROM FREESURFER + FMRIPREP
#
set -euo pipefail
IFS=$'\n\t'

# ---------------------- 1. Argument Parsing and Validation -----------------------

# Set default values
SUBJECT_ID=""
DERIV_DIR=$DIR_DATA_DERIV
SRC_DIR=$DIR_DATA_SOURCE
FPREP_ID="fmriprep"
SESSIONS=(ses-LE ses-RE)
FPREP_START="bold" # T1w
FOUT_ID=""

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
        --fprep_start)
            FPREP_START="$2"; shift 2;;     
        --fout_id)
            FOUT_ID="$2"; shift 2;;                        
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
echo "fprep start L $FPREP_START"
echo "------------------------------------------"


# ---------------------- 2. Directory Setup ---------------------------------------

FPREP_IN_DIR="$DERIV_DIR/$FPREP_ID/$SUBJECT_ID"
FPREP_OUTFS="$DERIV_DIR/${FPREP_ID}_fsinject/$SUBJECT_ID"
if [ ! -d "${FPREP_OUTFS}" ]; then
    mkdir -p ${FPREP_OUTFS}
fi

SRC_IN_DIR="$SRC_DIR/$SUBJECT_ID"
if [[ ! -d "$FPREP_IN_DIR" ]]; then
    echo "ERROR: fMRIPrep input directory not found: $FPREP_IN_DIR"; exit 1
fi

# Define output directory structure
if [ "${FPREP_START}"=="bold" ]; then
    ALIGN_OUT_DIR="$DERIV_DIR/${FPREP_ID}_POST_ALIGN_bstart${FOUT_ID}/$SUBJECT_ID"
else
    ALIGN_OUT_DIR="$DERIV_DIR/${FPREP_ID}_POST_ALIGN_tstart${FOUT_ID}/$SUBJECT_ID"
fi

ANAT_DIR="$ALIGN_OUT_DIR/anat"
FUNC_DIR="$ALIGN_OUT_DIR/func"
MEAN_DIR="$ALIGN_OUT_DIR/masked_mean"

mkdir -p "$ANAT_DIR" "$FUNC_DIR" "$MEAN_DIR"


# ---------------------- 3. Anatomical Preparation --------------------------------
# [1] Mask the T1 from freesurfer
# Define FreeSurfer Source Files
T1W_ANAT_SRC="${DIR_DATA_DERIV}/freesurfer/${SUBJECT_ID}/mri/orig.mgz"
T1W_MASK_SRC="${DIR_DATA_DERIV}/freesurfer/${SUBJECT_ID}/mri/brainmask.mgz"
WM_SEG_SRC="${DIR_DATA_DERIV}/freesurfer/${SUBJECT_ID}/mri/wm.mgz"

# Define Reference Output Files (in $ANAT_DIR)
T1W_ANAT_REF="$ANAT_DIR/T1w_preproc.nii.gz"
T1W_MASK_REF="$ANAT_DIR/T1w_mask.nii.gz"
WM_MASK_REF="$ANAT_DIR/T1w_wm_mask.nii.gz"  # NEW: Binarized White Matter Mask
T1W_MASKED="$ANAT_DIR/T1w_preproc_masked.nii.gz"

# ==============================================================================
# STAGE 1: Copy Anatomical and Brainmask (Original Stage)
# ==============================================================================
if [ ! -f "$T1W_ANAT_REF" ]; then
    echo "Copying FreeSurfer anatomical and brainmask volumes..."
    # Copy and convert anatomical to NIfTI (mri_convert is implicitly used by cp -n across filesystems)
    # Since FreeSurfer files are typically mgz, it is safer to use mri_convert if they are not already NIfTI
    mri_convert "$T1W_ANAT_SRC" "$T1W_ANAT_REF"
    mri_convert "$T1W_MASK_SRC" "$T1W_MASK_REF"
    mri_mask ${T1W_ANAT_REF} ${T1W_MASK_REF} ${T1W_MASKED}    
fi

# ==============================================================================
# STAGE 2: Generate Binarized White Matter Mask (New Stage)
# ==============================================================================
if [ ! -f "$WM_MASK_REF" ]; then
    echo "Generating binarized white matter mask: $WM_MASK_REF"
    # Temporary output file for the binarized MGZ

    WM_BIN_TMP="${DIR_DATA_DERIV}/freesurfer/${SUBJECT_ID}/mri/wm_bin.mgz"

    # 1. Binarize the wm.mgz file. --wm uses the internal knowledge of FreeSurfer 
    # WM values to create a binary mask (WM voxels = 1, others = 0).
    # mri_binarize --i "$WM_SEG_SRC" --o "$WM_BIN_TMP" --wm

    # 2. Convert the temporary binary MGZ mask to NIfTI (.nii.gz)
    mri_convert "$WM_SEG_SRC" "$WM_MASK_REF"
    fslmaths "$WM_MASK_REF" -thr 110 -uthr 110 -bin "$WM_MASK_REF"

    # 3. Clean up the temporary file 
    rm -f "$WM_BIN_TMP"

    echo "White matter mask generated successfully and saved as $WM_MASK_REF"
fi

# (Additional stages like T1W_MASKED generation would go here)
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
    if [ "${FPREP_START}"=="bold" ]; then
        find "$src_dir" -type f \
            -name "*desc-preproc_bold.nii.gz" ! -name "*space-T1w*" \
            -exec cp -n {} "$ALIGN_OUT_DIR/func/" \;

        find "$src_dir" -type f \
            -name "*desc-brain_mask.nii.gz" ! -name "*space-T1w*" \
            -exec cp -n {} "$ALIGN_OUT_DIR/func/" \;
    else
        find "$src_dir" -type f \
            \( -name "*space-T1w*desc-preproc_bold.nii.gz" -o -name "*space-T1w*desc-boldref_bold.nii.gz"  \) \
            -exec cp -n {} "$ALIGN_OUT_DIR/func/" \;

        find "$src_dir" -type f \
            \( -name "*space-T1w_desc-brain_mask.nii.gz"  \) \
            -exec cp -n {} "$ALIGN_OUT_DIR/func/" \;        
    fi
done

# ALSO -> copy over func only files
# ---------------------- 4. Functional File Discovery -----------------------------
for ses in "${SESSIONS[@]}"; do
    src_dir="$FPREP_IN_DIR/$ses/func"    
    trg_dir="$FPREP_OUTFS/$ses/"
    if [[ ! -d "$src_dir" ]]; then
        echo "Skipping session $ses: source directory not found: $src_dir"
        continue
    fi
    if [[ ! -d "$FPREP_OUTFS/$ses" ]]; then
        mkdir -p "$FPREP_OUTFS/$ses"
    fi
    rsync -av --exclude '*space-T1w*' --exclude '*space-fsaverage*'\
        --exclude '*func.gii' --exclude '*.nii.gz' \
        ${src_dir} ${trg_dir}

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