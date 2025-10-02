#!/bin/bash

# --- 0. Define Variables and Paths ---

# The root directory where your 'anat' and 'ses-LE' folders reside
ROOT_DIR=$(pwd)
SUBJ_ID="sub-ctrl02"
TASK_ID="CSF"
RUN_ID="1" # Example run: Repeat steps 2 and 3 for all other runs

# Anatomical Files
# Original fMRIPrep skull-stripped T1w (Oblique input)
T1_ANAT_OBLIQUE="${ROOT_DIR}/anat/${SUBJ_ID}_ses-fprep_acq-MP2RAGE_desc-preproc_T1w_brain.nii.gz"
# Deobliqued T1w (New target for alignment)
T1_ANAT_DEOBLIQUE="${ROOT_DIR}/anat/${SUBJ_ID}_ses-fprep_acq-MP2RAGE_desc-deoblique_T1w_brain.nii.gz"

# Functional Files
# Preprocessed BOLD in native space (Input to be realigned and resampled)
BOLD_NATIVE="${ROOT_DIR}/ses-LE/${SUBJ_ID}_ses-LE_task-${TASK_ID}_run-${RUN_ID}_desc-preproc_bold.nii.gz"
# BOLD Reference Image (First volume of the BOLD series)
BOLD_REF_VOL="${BOLD_NATIVE}[0]"

# Output Files
ALIGN_PREFIX="anat_al_new" # Prefix for the new alignment matrix and intermediate files
OUTPUT_DIR="${ROOT_DIR}/ses-LE/AFNI_FIX" # Output directory for the fixed BOLD data
mkdir -p ${OUTPUT_DIR}

echo "Starting AFNI alignment fix for ${SUBJ_ID} - Task ${TASK_ID} Run ${RUN_ID}..."
echo "--------------------------------------------------------------------------------"

# --------------------------------------------------------------------------------
# --- 1. Fix Obliquity (Crucial Step) ---
# --------------------------------------------------------------------------------

echo "1. Deobliquing the anatomical T1w image using 3dWarp..."

# This command removes the obliquity from the anatomical image, which is necessary
# for robust registration with AFNI tools.
3dWarp \
    -deoblique \
    -prefix "${T1_ANAT_DEOBLIQUE}" \
    "${T1_ANAT_OBLIQUE}"

echo "Deobliqued T1w saved to: ${T1_ANAT_DEOBLIQUE}"
echo "--------------------------------------------------------------------------------"


# --------------------------------------------------------------------------------
# --- 2. Re-Calculate the EPI-to-T1w Affine Transform ---
# --------------------------------------------------------------------------------

echo "2. Calculating new affine transformation (EPI to Deobliqued T1w)..."

# Now, we use the deobliqued T1w as the target (-dset2).
align_epi_anat.py \
    -dset1 "${BOLD_REF_VOL}" \
    -dset2 "${T1_ANAT_DEOBLIQUE}" \
    -dset1to2 \
    -cost lpc+ZZ \
    -big_move \
    -anat_has_skull no \
    -prefix "${ALIGN_PREFIX}"

# Rename and move the final matrix for proper bookkeeping
ALIGN_MATRIX="${OUTPUT_DIR}/${SUBJ_ID}_ses-LE_task-${TASK_ID}_run-${RUN_ID}_afnifix_al_mat.aff12.1D"
mv ${ALIGN_PREFIX}_al_mat.aff12.1D "${ALIGN_MATRIX}"
echo "New alignment matrix saved to: ${ALIGN_MATRIX}"
echo "--------------------------------------------------------------------------------"

# --------------------------------------------------------------------------------
# --- 3. Apply the New Transform to the Full BOLD Time Series ---
# --------------------------------------------------------------------------------

echo "3. Applying new transform to the full BOLD time series..."

# Use 3dAllineate to resample the native-space BOLD data into the DEOBLIQUED T1w space
# in a single, high-quality interpolation step (wsinc5).

OUTPUT_BOLD="${OUTPUT_DIR}/${SUBJ_ID}_ses-LE_task-${TASK_ID}_run-${RUN_ID}_space-T1w_desc-AFNIfix_bold.nii.gz"

3dAllineate \
    -base "${T1_ANAT_DEOBLIQUE}" \
    -input "${BOLD_NATIVE}" \
    -prefix "${OUTPUT_BOLD}" \
    -1Dmatrix_apply "${ALIGN_MATRIX}" \
    -interp wsinc5 \
    -overwrite

echo "New, realigned BOLD time series saved to: ${OUTPUT_BOLD}"
echo "--------------------------------------------------------------------------------"

# --------------------------------------------------------------------------------
# --- 4. Final Cleanup and Instructions ---
# --------------------------------------------------------------------------------

# Remove temporary files created by align_epi_anat.py
rm ${ALIGN_PREFIX}*

echo "AFNI Alignment Fix Complete."
echo "ACTION REQUIRED: You must visually inspect the overlay of ${OUTPUT_BOLD} and ${T1_ANAT_DEOBLIQUE} in AFNI to confirm alignment is fixed."
echo "ACTION REQUIRED: Repeat Step 2 (re-calculating the matrix) and Step 3 (applying the matrix) for all other BOLD runs (CSF runs 2-5, pRF runs 1-2)."