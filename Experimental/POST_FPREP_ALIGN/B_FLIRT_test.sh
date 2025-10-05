#!/usr/bin/env bash
#
# FLIRT-Based fMRI Preprocessing Alignment Script
# Purpose: Align all fMRIPrep BOLD runs to the first run's mean, then align the
# reference mean to the T1w anatomy, and apply the concatenated transform to all 4D BOLD runs.
# Requires: FSL (flirt, fslmaths, convert_xfm)
#
set -euo pipefail
IFS=$'\n\t'

# ---------------------- 1. Argument Parsing and Validation -----------------------

# Set default values
SUBJECT_ID=""
DERIV_DIR=$DIR_DATA_DERIV
SRC_DIR=$DIR_DATA_SOURCE
DOF_VOL=6
DOF_ANAT=12
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
        --dof_vol)
            DOF_VOL="$2"; shift 2;;
        --dof_anat)
            DOF_ANAT="$2"; shift 2;;
        --fprep_id)
            FPREP_ID="$2"; shift 2;;
        *)
            echo "ERROR: Unknown option: $1"; exit 1;;
    esac
done

# Normalize subject ID
SUBJECT_ID=${SUBJECT_ID/sub-/}
SUBJECT_ID="sub-${SUBJECT_ID}"

# CALL THE COPY SCRIPT
source ./A_COPY_FILES.sh --sub $SUBJECT_ID --deriv_dir $DERIV_DIR --fprep_id $FPREP_ID

# Print summary
echo "--- FLIRT Alignment Script Configuration ---"
echo "Subject ID: $SUBJECT_ID"
echo "Derivatives Dir: $DERIV_DIR"
echo "fMRIPrep Dir Name: $FPREP_ID"
echo "DOF (Vol-to-Ref): $DOF_VOL (Inter-run alignment)"
echo "DOF (Ref-to-Anat): $DOF_ANAT (Functional-to-anatomical alignment)"
echo "------------------------------------------"

# Define output directory structure
TALIGN_DIR="$ALIGN_OUT_DIR/flirt"
COREG_DIR="$TALIGN_DIR/coreg_ref${DOF_VOL}"
XFM_DIR="$TALIGN_DIR/xfm_ref${DOF_VOL}"

mkdir -p "$COREG_DIR" "$XFM_DIR"

# ******** TAKE FIRST RUN - as reference 
REF_BOLD=${BOLD_FILES[0]}
REF_BOLD_BASE=$(basename "$REF_BOLD")
REF_ID=${REF_BOLD_BASE%%.*}
REF_MEAN=${RUN_MEAN["$REF_ID"]}

echo "Reference BOLD (first run) chosen: $REF_BOLD_BASE"

# ---------------------- 5. Step 1: Inter-Run Registration (BOLD mean → Reference mean) -----------------

declare -A RUN2REF_MATRIX

for bold_path in "${BOLD_FILES[@]}"; do
    base=$(basename "$bold_path" .nii.gz)
    id=${base%%.*}
    mean_path="${RUN_MEAN[$id]}"
    OUTPUT_MATRIX="$XFM_DIR/${base}_to_ref.mat"
    RUN2REF_MATRIX["$bold_path"]="$OUTPUT_MATRIX"
    
    # a. Reference Run (Identity Matrix)
    if [[ "$bold_path" == "$REF_BOLD" ]]; then
        if [[ ! -f "$OUTPUT_MATRIX" ]]; then
            echo "Reference run: creating identity matrix: $OUTPUT_MATRIX"
            cp $REF_MEAN $COREG_DIR/${base}_mean_in_ref.nii.gz
            cat > "$OUTPUT_MATRIX" <<'EOF'
1 0 0 0
0 1 0 0
0 0 1 0
0 0 0 1
EOF
        fi
        continue
    fi

    # b. Other Runs (FLIRT)
    if [[ -f "$OUTPUT_MATRIX" ]]; then
        echo "Found existing run->ref matrix for $base. Skipping FLIRT."
        continue
    fi

    echo "FLIRT (Moving: ${base}_mean -> Reference: ${REF_BOLD_BASE}_mean, DOF=$DOF_VOL)"
    # flirt -in <moving> -ref <fixed> -out <transformed> -omat <matrix> -dof <dof>
    flirt -in "$mean_path" -ref "$REF_MEAN" -out "$COREG_DIR/${base}_mean_in_ref.nii.gz" \
          -omat "$OUTPUT_MATRIX" -dof "$DOF_VOL" -interp trilinear -cost normcorr

done

# ---------------------- 6. Step 2: Functional-to-Anatomical Registration (Reference mean → T1w) -----------------

COREG_ANAT_DIR="$TALIGN_DIR/coreg_ref${DOF_VOL}_an${DOF_ANAT}"
XFM_TOTAL_DIR="$TALIGN_DIR/xfm${DOF_VOL}_an${DOF_ANAT}"
mkdir -p "${COREG_ANAT_DIR}" "${XFM_TOTAL_DIR}"
REF2ANAT_MATRIX="$TALIGN_DIR/${REF_ID}_an${DOF_ANAT}_to_T1w.mat"
REF2ANAT_OUT="$COREG_ANAT_DIR/${REF_ID}_mean_in_T1w.nii.gz"

if [[ ! -f "$REF2ANAT_MATRIX" ]]; then
    echo "FLIRT (Moving: Reference mean -> Fixed: T1w anatomical, DOF=$DOF_ANAT)"
    # Use a robust cost function like Normalized Mutual Information for cross-modal registration
    # flirt -in <moving> -ref <fixed> -out <transformed> -omat <matrix> -dof <dof> -cost normmi
    flirt -in "$REF_MEAN" -ref "$T1W_MASKED" -out "$REF2ANAT_OUT" \
          -omat "$REF2ANAT_MATRIX" -dof 6 -cost normmi -interp trilinear
else
    echo "Found existing ref->anat matrix: $REF2ANAT_MATRIX. Skipping FLIRT."
fi


# *********************** TEST ---- transform
for bold_path in "${BOLD_FILES[@]}"; do
    base=$(basename "$bold_path" .nii.gz)
    id=${base%%.*}
    mean_path="${RUN_MEAN[$id]}"
    # Transformation matrices
    XFM_I_TO_REF="${RUN2REF_MATRIX[$bold_path]}"         # XFMi→ref
    XFM_REF_TO_ANAT="$REF2ANAT_MATRIX"                  # XFMref→anat
    XFM_TOTAL="$XFM_TOTAL_DIR/${base}_to_T1w_total.mat"       # XFMtotal
    XFM_TOTAL_ITK="$XFM_TOTAL_DIR/${base}_to_T1w_total_itk.txt"       # XFMtotal

    # Output file path
    R_I_T1W="$COREG_ANAT_DIR/${base}_FLIRT_T1w_MEAN.nii.gz"

    # a. Calculate the concatenated transform: XFMtotal = XFMref→anat * XFMi→ref
    if [[ ! -f "$XFM_TOTAL" || ! -f "$XFM_TOTAL_ITK" ]]; then
        echo "Composing total transform for $base: XFMtotal = XFMref→anat * XFMi→ref"
        # convert_xfm -omat <output> -concat <pre-transform> <post-transform> (FSL convention is post-concat)
        convert_xfm -omat "$XFM_TOTAL" -concat "$XFM_REF_TO_ANAT" "$XFM_I_TO_REF"
        # echo c3d_affine_tool "$XFM_TOTAL" -ref $T1W_MASK_REF -src $bold_path -fsl2ras -oitk "$XFM_TOTAL_ITK"
        # exit 1
    else
        echo "Found existing total transform: $XFM_TOTAL. Skipping concatenation."
    fi

    # b. Apply the total transform to the 4D BOLD run
    if [[ ! -f "$R_I_T1W" ]]; then
        echo "Applying total transform to 4D BOLD: $bold_path -> $R_I_T1W"
        # flirt -in <input 4D> -ref <target T1w> -out <output 4D> -applyxfm -init <total matrix> -interp trilinear
        flirt -in "$mean_path" -ref "$T1W_MASKED" -out "$R_I_T1W" \
              -applyxfm -init "$XFM_TOTAL" -interp trilinear
    else
        echo "Final resliced BOLD already exists: $R_I_T1W. Skipping application."
    fi

done

exit 1
# ---------------------- 7. Step 3: Transformation Application -----------------------------------------

echo "--- Applying Concatenated Transforms to 4D BOLD Runs ---"
# exit 1 
for bold_path in "${BOLD_FILES[@]}"; do
    base=$(basename "$bold_path" .nii.gz)
    
    # Transformation matrices
    XFM_I_TO_REF="${RUN2REF_MATRIX[$bold_path]}"         # XFMi→ref
    XFM_REF_TO_ANAT="$REF2ANAT_MATRIX"                  # XFMref→anat
    XFM_TOTAL="$XFM_TOTAL_DIR/${base}_to_T1w_total.mat"       # XFMtotal
    XFM_TOTAL_ITK="$XFM_TOTAL_DIR/${base}_to_T1w_total_itk.txt"       # XFMtotal

    # Output file path
    R_I_T1W="$COREG_ANAT_DIR/${base}_FLIRT_T1w.nii.gz"

    # a. Calculate the concatenated transform: XFMtotal = XFMref→anat * XFMi→ref
    if [[ ! -f "$XFM_TOTAL" || ! -f "$XFM_TOTAL_ITK" ]]; then
        echo "Composing total transform for $base: XFMtotal = XFMref→anat * XFMi→ref"
        # convert_xfm -omat <output> -concat <pre-transform> <post-transform> (FSL convention is post-concat)
        convert_xfm -omat "$XFM_TOTAL" -concat "$XFM_REF_TO_ANAT" "$XFM_I_TO_REF"
        echo c3d_affine_tool "$XFM_TOTAL" -ref $T1W_MASK_REF -src $bold_path -fsl2ras -oitk "$XFM_TOTAL_ITK"
        exit 1
    else
        echo "Found existing total transform: $XFM_TOTAL. Skipping concatenation."
    fi

    # b. Apply the total transform to the 4D BOLD run
    if [[ ! -f "$R_I_T1W" ]]; then
        echo "Applying total transform to 4D BOLD: $bold_path -> $R_I_T1W"
        # flirt -in <input 4D> -ref <target T1w> -out <output 4D> -applyxfm -init <total matrix> -interp trilinear
        flirt -in "$bold_path" -ref "$T1W_MASKED" -out "$R_I_T1W" \
              -applyxfm -init "$XFM_TOTAL" -interp trilinear
    else
        echo "Final resliced BOLD already exists: $R_I_T1W. Skipping application."
    fi

done

echo "--- Script Complete ---"
echo "Final resliced BOLD files are located in: $COREG_ANAT_DIR"
echo "Transformation matrices are located in: $XFM_TOTAL_DIR"