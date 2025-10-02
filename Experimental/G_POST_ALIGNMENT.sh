#!/bin/bash

# Fix the registration problems... 

# Initialize a variable to store the subject ID
SUBJECT_ID=""
FPREP_ID="fmriprep"
# Parse arguments
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
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Clean up the subject ID to remove potential 'sub-' prefix
# This handles both 'ctrl05' and 'sub-ctrl05'
SUBJECT_ID=${SUBJECT_ID/sub-/}
SUBJECT_ID="sub-${SUBJECT_ID}"
fs_orig=$(find $SUBJECTS_DIR/$SUBJECT_ID -name "orig.mgz")

# Define paths to key files
FPREP_DIR="$DIR_DATA_DERIV/$FPREP_ID/$SUBJECT_ID"
ALIGN_DIR="$DIR_DATA_DERIV/${FPREP_ID}_ALIGN/$SUBJECT_ID"
if [ ! -d "$ALIGN_DIR" ]; then
    mkdir -p "$ALIGN_DIR"
fi

# ***** COPY OVER RELEVANT FILES
# [1] Anatomies 
mkdir -p "$ALIGN_DIR/anat"
src_file=$(find "$FPREP_DIR/ses-fprep/anat" -type f -name "*desc-preproc_T1w.nii.gz" | head -n 1)
cp -n "$src_file" "$ALIGN_DIR/anat/"

# [2] Copy the T1w brain mask
src_file=$(find "$FPREP_DIR/ses-fprep/anat" -type f -name "*desc-brain_mask.nii.gz" | head -n 1)
cp -n "$src_file" "$ALIGN_DIR/anat/"

# -> also the T1w -> fsnative transform
src_file=$(find "$FPREP_DIR/ses-fprep/anat" -type f -name "*from-T1w_to-fsnative_mode-image_xfm.txt" | head -n 1)
cp -n "$src_file" "$ALIGN_DIR/anat/"
# IMPORTANT FILES
T1w=$(find "$ALIGN_DIR/anat" -type f -name "*preproc_T1w.nii.gz")
T1w_mask=$(find "$ALIGN_DIR/anat" -type f -name "*brain_mask*.nii.gz")
T1w_to_orig=$(find "$ALIGN_DIR/anat" -type f -name "*T1w*xfm")
# Make the masked T1w
fslmaths $T1w -mas $T1w_mask ${T1w%.nii.gz}_brain.nii.gz
# exit 1
T1w=${T1w%.nii.gz}_brain.nii.gz


# [2] Functional - boldref, bold, brain mask (not aligned) 
for ses in ses-LE; do # ses-RE; do
    src_dir="$FPREP_DIR/$ses/func"
    dest_dir="$ALIGN_DIR/$ses"
    if [ -d "$src_dir" ]; then
        mkdir -p "$dest_dir"
        # BOLD 
        find "$src_dir" -type f -name "*desc-preproc_bold.nii.gz" | while read -r bold_file; do
            cp -n "$bold_file" "$dest_dir/"
        done
        # BOLD ref
        find "$src_dir" -type f -name "*desc-boldref_bold.nii.gz" | while read -r bold_file; do
            cp -n "$bold_file" "$dest_dir/"
        done
        # brain mask
        find "$src_dir" -type f -name "*desc-brain_mask.nii.gz" | while read -r bold_file; do
            cp -n "$bold_file" "$dest_dir/"
        done
        # bold ref 
        find "$src_dir" -type f -name "*desc-boldref.nii.gz" | while read -r bold_file; do
            cp -n "$bold_file" "$dest_dir/"
        done
    fi
done







# ***** COPYING DONE 
echo FINISHED COPYING.... 
echo
echo

exit 1
# *** Now use call_antsregistration 

for ses in ses-LE ses-RE; do
    al_dir="$ALIGN_DIR/$ses"    
    if [ ! -d "$al_dir" ]; then
        continue
    fi

    # Loop through runs and find the relevant files
    for task in CSF pRF; do
        for run in 1 2 3 4 5 6; do
            bold=$(find "$al_dir" -type f -name "*${ses}*${task}*run-${run}*T1w_desc-preproc_bold.nii.gz" | head -n 1)
            if [ ! -n "$bold" ]; then
                continue
            fi
            bref=$(find "$al_dir" -type f -name "*${ses}*${task}*run-${run}*T1w_boldref.nii.gz" | head -n 1)
            bmask=$(find "$al_dir" -type f -name "*ses-${ses}*run-${run}*T1w_desc-brain_mask.nii.gz" | head -n 1)
            
            breg_file=$(dirname "$bold")/${ses}_${task}_${run}_REG
            echo Running for $(basename "$bold")             
            call_antsregistration ${T1w} ${bref} ${breg_file} -x ${bmask} -j 5 --affine --verbose --itk
            exit 0
        done

    done
        
done
