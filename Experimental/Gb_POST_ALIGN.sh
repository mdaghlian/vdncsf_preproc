#!/usr/bin/env bash
# afni_align_fmriprep_to_t1.sh
#
# Take motion+SDC corrected BOLD outputs from fMRIPrep and perform a final
# EPI -> T1w registration using AFNI's align_epi_anat.py.
# The script copies files, runs the alignment, applies the transform
# to the full 4D BOLD, and saves outputs in an ALIGN_DIR structure.
#
# Requirements:
#  - AFNI installed and in PATH (3dTstat, 3dAutomask, align_epi_anat.py, 3dAllineate, 3dWarp)
#  - FSL installed (fslmaths used for masking T1 if needed)
#  - Environment variables DIR_DATA_DERIV and SUBJECTS_DIR must be set.
#
# Usage:
#   DIR_DATA_DERIV=/path/to/derivatives SUBJECTS_DIR=/path/to/freesurfer ./afni_align_fmriprep_to_t1.sh --sub sub-01 [--fprep fmriprep]
#
set -euo pipefail
# Sets IFS to a more robust value for loop/variable safety (not strictly needed for this script, but good practice)
IFS=$'\n\t' 

# ---------------------- Check and set environment -----------------------

# Check required environment variables
: "${DIR_DATA_DERIV:?ERROR: Please set DIR_DATA_DERIV environment variable (BIDS derivatives dir).}"
: "${SUBJECTS_DIR:?ERROR: Please set SUBJECTS_DIR environment variable (Freesurfer SUBJECTS_DIR).}"

# Check AFNI tools exist
for exe in 3dTstat 3dAutomask align_epi_anat.py 3dAllineate 3dWarp; do
    command -v "$exe" >/dev/null 2>&1 || { echo "ERROR: $exe not found in PATH. Please install AFNI and ensure it's available."; exit 1; }
done

# ---------------------- User-configurable defaults -----------------------
FPREP_ID="fmriprep"
# Modify/add sessions you want to process, e.g. (ses-LE ses-RE)
SESSIONS=(ses-LE) 
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
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

if [[ -z "$SUBJECT_ID" ]]; then
    echo "ERROR: --sub <subject_id> is required (e.g. --sub sub-01 or --sub 01)"
    exit 1
fi

# Normalize subject id: remove leading 'sub-' if present, then add it back
SUBJECT_ID=${SUBJECT_ID/sub-/}
SUBJECT_ID="sub-${SUBJECT_ID}"

# Define key directories
FPREP_DIR="$DIR_DATA_DERIV/$FPREP_ID/$SUBJECT_ID"
ALIGN_DIR="$DIR_DATA_DERIV/${FPREP_ID}_ALIGN/$SUBJECT_ID"

# Prepare alignment directory
rm -rf "$ALIGN_DIR"
mkdir -p "$ALIGN_DIR/anat"

# ---------------------- Copy and Prepare Anatomical Files ---------------------

echo "Searching for T1w and brainmask in: $FPREP_DIR/anat"
# Use 'anat' directly as fmriprep structure changed to put anat at subject level
# Check both subject-level and a common 'ses-fprep' path for compatibility
T1_SRC=$(find "$FPREP_DIR/ses-fprep/anat/" -maxdepth 2 -type f -name "*desc-preproc_T1w.nii.gz" | grep '/anat/' | head -n 1 || true)
T1_MASK_SRC=$(find "$FPREP_DIR/ses-fprep/anat/" -maxdepth 2 -type f -name "*desc-brain_mask.nii.gz" | grep '/anat/' | head -n 1 || true)

if [[ -z "$T1_SRC" ]]; then
    echo "ERROR: could not find T1w preproc in $FPREP_DIR/anat or subfolders."
    exit 1
fi

# Copy files
echo "Copying T1w files to $ALIGN_DIR/anat/"
cp -n "$T1_SRC" "$ALIGN_DIR/anat/"
if [[ -n "$T1_MASK_SRC" ]]; then
    cp -n "$T1_MASK_SRC" "$ALIGN_DIR/anat/"
fi

# Set variables pointing to the copied files
T1w_base=$(basename "$T1_SRC")
T1w_path="$ALIGN_DIR/anat/$T1w_base"
T1w_mask_path=$(find "$ALIGN_DIR/anat" -type f -name "*brain_mask*.nii.gz" | head -n 1 || true)

# Create skullstripped T1w file (T1w_brain.nii.gz) if mask is available
if [[ -n "$T1w_path" && -n "$T1w_mask_path" ]]; then
    echo "Creating masked T1w file (T1w_brain)..."
    # Use fslmaths to mask the T1w
    T1w_brain_path="${T1w_path%.nii.gz}_brain.nii.gz"
    fslmaths "$T1w_path" -mas "$T1w_mask_path" "$T1w_brain_path"
    T1w_reg_target="$T1w_brain_path"
    ANAT_HAS_SKULL="no"
else
    T1w_reg_target="$T1w_path"
    ANAT_HAS_SKULL="yes"
    echo "Warning: T1 brain mask not found. Using T1 as-is for registration (align_epi_anat.py -anat_has_skull yes)."
fi

# Deoblique the T1 registration target
echo "Deobliquing T1w registration target..."
T1w_deob_path="${T1w_reg_target%.nii.gz}_deob.nii.gz"
3dWarp -deoblique -prefix "$T1w_deob_path" "$T1w_reg_target" || { echo "ERROR: 3dWarp -deoblique failed for T1"; exit 1; }
# Keep the original file, just update the target variable
T1w_reg_target="$T1w_deob_path"

# ---------------------- Process Sessions and Runs -------------------------

for ses in "${SESSIONS[@]}"; do
    src_dir="$FPREP_DIR/$ses/func"
    dest_dir="$ALIGN_DIR/$ses"
    
    if [[ ! -d "$src_dir" ]]; then
        echo "Skipping session $ses: source directory not found: $src_dir"
        continue
    fi
    mkdir -p "$dest_dir"

    echo "Copying functional files for $ses..."
    # Copy preproc BOLD, boldref, and brain mask, explicitly excluding 'space-' files (already resampled)
    find "$src_dir" -type f \( -name "*desc-preproc_bold.nii.gz" -o -name "*desc-boldref_bold.nii.gz" -o -name "*desc-brain_mask.nii.gz" \) \
        -not -name "*space-*" -exec cp -n {} "$dest_dir/" \;

    # Iterate over preproc BOLD files in dest_dir
    find "$dest_dir" -maxdepth 1 -type f -name "*desc-preproc_bold.nii.gz" | while read -r BOLD_PATH; do
        echo ""
        echo "---- Processing BOLD: $(basename "$BOLD_PATH") ----"

        base=$(basename "$BOLD_PATH" .nii.gz)
        run_outdir="$dest_dir/${base}_ALIGN"
        mkdir -p "$run_outdir"
        
        # Define BOLD paths relative to the current run
        BOLD_DEOB_PATH="$run_outdir/${base}_deob.nii.gz"
        
        # Deoblique the full BOLD volume
        echo "Deobliquing full BOLD volume (3dWarp -deoblique)..."
        3dWarp -deoblique -prefix "$BOLD_DEOB_PATH" "$BOLD_PATH" || { echo "Warning: 3dWarp -deoblique failed for BOLD: $BOLD_PATH"; continue; }

        # --- Prepare Mean EPI and Mask ---
        
        # Make mean EPI (3dTstat) from the deobliqued BOLD
        echo "Making mean EPI..."
        mean_epi_base="${base}_mean"
        mean_epi_path="$run_outdir/${mean_epi_base}.nii.gz"
        3dTstat -prefix "$mean_epi_path" -mean "$BOLD_DEOB_PATH"

        # Find the corresponding BOLD mask in the session folder
        BOLD_MASK_PATH=$(find "$dest_dir" -maxdepth 1 -type f -name "${base/desc-preproc/desc-brain_mask}*" -print -quit || true)

        # Make EPI mask: prefer provided BOLD_MASK, else compute from mean
        if [[ -n "$BOLD_MASK_PATH" ]]; then
            echo "Using provided BOLD brain mask."
            # Copy and deoblique the mask for consistency, but AFNI can handle non-deobliqued mask
            cp -n "$BOLD_MASK_PATH" "$run_outdir/"
            mean_epi_mask_path="$run_outdir/$(basename "$BOLD_MASK_PATH")"
        else
            echo "Computing EPI mask from mean EPI..."
            mean_epi_mask_path="$run_outdir/${mean_epi_base}_mask.nii.gz"
            3dAutomask -clfrac 0.5 -apply_prefix "$mean_epi_mask_path" "$mean_epi_path" || { echo "Warning: 3dAutomask failed; proceeding without EPI mask."; mean_epi_mask_path=""; }
        fi

        # --- Run Alignment (Mean EPI -> T1) ---
        
        echo "Running align_epi_anat.py: mean EPI -> T1..."
        pushd "$run_outdir" >/dev/null

        align_epi_anat.py \
            -anat "$T1w_reg_target" \
            -anat_has_skull "no" \
            -epi "$(basename "$mean_epi_path")" \
            -epi_base 0 \
            -epi2anat \
            -cost lpc+ZZ \
            -suffix _al \
            -giant_move \
            -volreg off \
            || { echo "ERROR: align_epi_anat.py failed for $mean_epi_path"; popd >/dev/null; continue; }
            
        # Find the produced 1D affine matrix
        MAT_FILE=$(ls -t *aff12.1D 2>/dev/null | head -n 1 || true)
        
        if [[ -z "$MAT_FILE" ]]; then
            echo "WARNING: could not find an affine 1D matrix produced by align_epi_anat.py. Skipping applying transform."
            popd >/dev/null
            continue
        fi
        echo "Found matrix: $MAT_FILE"

        # --- Apply Transform to Full BOLD ---
        
        OUT_BOLD_IN_T1="${base}_in-T1w.nii.gz"
        echo "Applying transform to full BOLD -> $OUT_BOLD_IN_T1"
        3dAllineate \
            -base "$T1w_reg_target" \
            -input "$BOLD_DEOB_PATH" \
            -1Dmatrix_apply "$MAT_FILE" \
            -master "$T1w_reg_target" \
            -prefix "$OUT_BOLD_IN_T1" \
            -final wsinc5 \
            || { echo "ERROR: 3dAllineate failed for $BOLD_DEOB_PATH"; popd >/dev/null; continue; }

        # Transform the mean EPI for QC
        QC_MEAN_EPI="mean_epi_in_T1.nii.gz"
        3dAllineate -base "$T1w_reg_target" -input "$(basename "$mean_epi_path")" -1Dmatrix_apply "$MAT_FILE" -master "$T1w_reg_target" -prefix "$QC_MEAN_EPI" -final wsinc5

        # Copy matrix and QC mean to top-level align dir for convenience
        cp -n "$MAT_FILE" "$ALIGN_DIR/"
        cp -n "$QC_MEAN_EPI" "$ALIGN_DIR/"

        popd >/dev/null

        echo "Finished alignment for $(basename "$BOLD_PATH"). Outputs in: $run_outdir"
        echo "  - BOLD in T1 space: $run_outdir/$OUT_BOLD_IN_T1"
        echo "  - QC mean_epi_in_T1: $run_outdir/$QC_MEAN_EPI"
    done
done

# ---------------------- Final messages / QC tips -------------------------
echo ""
echo "=================================================="
echo "ALL DONE. Key outputs are placed under: $ALIGN_DIR"
echo "=================================================="

echo "For QC, launch AFNI and load the T1 registration target and the aligned mean EPI to visually inspect:"
echo ""
echo "  afni $T1w_reg_target $ALIGN_DIR/*/*_ALIGN/*mean_epi_in_T1.nii.gz &"
echo ""