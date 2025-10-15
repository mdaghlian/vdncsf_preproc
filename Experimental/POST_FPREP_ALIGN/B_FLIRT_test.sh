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
DOF_VOL=12
DOF_ANAT=12
FPREP_ID="fmriprep"
VALID_DOFS=(6 7 9 12)
SESSIONS=(ses-LE ses-RE)
TARGET="T1w"
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
        --dof_vol)
            DOF_VOL="$2"; shift 2;;
        --dof_anat)
            DOF_ANAT="$2"; shift 2;;
        --fprep_id)
            FPREP_ID="$2"; shift 2;;
        --fprep_start)
            FPREP_START="$2"; shift 2;;     
        --fout_id)
            FOUT_ID="$2"; shift 2;;           
        --target)
            TARGET="$2"; shift 2;;                             
        *)
            echo "ERROR: Unknown option: $1"; exit 1;;
    esac
done

# Normalize subject ID
SUBJECT=${SUBJECT_ID/sub-/}
SUBJECT_ID="sub-${SUBJECT}"
# CALL THE COPY SCRIPT
# source ${PWD}/../A_COPY_FILES.sh --sub $SUBJECT_ID --deriv_dir $DERIV_DIR --fprep_id $FPREP_ID --fprep_start $FPREP_START
source ./A_COPY_FILES.sh --sub $SUBJECT_ID --deriv_dir $DERIV_DIR --fprep_id $FPREP_ID --fprep_start $FPREP_START

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
declare -A MCOREG_RUN2REF
for bold_path in "${BOLD_FILES[@]}"; do
    base=$(basename "$bold_path" .nii.gz)
    id=${base%%.*}
    mean_path="${RUN_MEAN[$id]}"
    OUTPUT_MATRIX="$XFM_DIR/${base}_to_ref.mat"
    RUN2REF_MATRIX["$bold_path"]="$OUTPUT_MATRIX"
    TCOREG="$COREG_DIR/${base}_mean_in_ref.nii.gz"
    MCOREG_RUN2REF["${id}"]="$TCOREG"
    # a. Reference Run (Identity Matrix)
    if [[ "$bold_path" == "$REF_BOLD" ]]; then
        if [[ ! -f "$OUTPUT_MATRIX" ]]; then
            echo "Reference run: creating identity matrix: $OUTPUT_MATRIX"
            cp $REF_MEAN $TCOREG
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

# ---- CREATE GRAN MEAN
GRAND_MEAN="$COREG_DIR/A_GRAND_MEAN.nii.gz"
for bold_path in "${BOLD_FILES[@]}"; do
    base=$(basename "$bold_path" .nii.gz)
    id=${base%%.*}
    TCOREG="${MCOREG_RUN2REF[$id]}"

    if [ id==REF_ID ]; then
        cp $TCOREG $GRAND_MEAN
        continue
    fi 

    fslmaths $TCOREG -add $GRAND_MEAN $GRAND_MEAN    
done


# ---------------------- 6. Step 2: Functional-to-Anatomical Registration (Reference mean → T1w) -----------------

COREG_ANAT_DIR="$TALIGN_DIR/coreg_ref${DOF_VOL}_an${TARGET}${DOF_ANAT}"
XFM_TOTAL_DIR="$TALIGN_DIR/xfm${DOF_VOL}_an${TARGET}${DOF_ANAT}"
mkdir -p "${COREG_ANAT_DIR}" "${XFM_TOTAL_DIR}"

if [ "$TARGET" = "T1w" ]; then    
    TARGET_PATH=${T1W_MASKED}    
else
    TARGET_PATH=${T2W_MASKED}
fi

REF2ANAT_MATRIX="$TALIGN_DIR/${REF_ID}_an${DOF_ANAT}_to_${TARGET}.mat"
REF2ANAT_OUT="$COREG_ANAT_DIR/${REF_ID}_mean_in_${TARGET}.nii.gz"

if [[ ! -f "$REF2ANAT_MATRIX" ]]; then
    echo "FLIRT (Moving: Reference mean -> Fixed: ${TARGET_PATH} anatomical, DOF=$DOF_ANAT)"
    # Use a robust cost function like Normalized Mutual Information for cross-modal registration
    # flirt -in <moving> -ref <fixed> -out <transformed> -omat <matrix> -dof <dof> -cost normmi
    flirt -in "$REF_MEAN" -ref "$TARGET_PATH" -out "$REF2ANAT_OUT" -omat "$REF2ANAT_MATRIX" -dof "${DOF_ANAT}" -cost normmi -interp trilinear
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
    XFM_TOTAL="$XFM_TOTAL_DIR/${base}_to_${TARGET}_total.mat"       # XFMtotal
    XFM_TOTAL_ITK="$XFM_TOTAL_DIR/${base}_to_${TARGET}_total_itk.txt"       # XFMtotal

    # Output file path
    R_I_TARGET="$COREG_ANAT_DIR/${base}_FLIRT_${TARGET}_MEAN.nii.gz"

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
    
    if [[ ! -f "$R_I_TARGET" ]]; then
        echo "Applying total transform to 4D BOLD: $bold_path -> $R_I_TARGET"
        # flirt -in <input 4D> -ref <target T1w> -out <output 4D> -applyxfm -init <total matrix> -interp trilinear
        flirt -in "$mean_path" -ref "$TARGET_PATH" -out "$R_I_TARGET" \
              -applyxfm -init "$XFM_TOTAL" -interp trilinear
    else
        echo "Final resliced BOLD already exists: $R_I_TARGET. Skipping application."
    fi

done

# ---------------------- 7. Step 3: Transformation TO FSNATIVE -----------------------------------------
for bold_path in "${BOLD_FILES[@]}"; do
    base=$(basename "$bold_path" .nii.gz)
    id=${base%%_desc*}
    XFM_TOTAL="$XFM_TOTAL_DIR/${base}_to_${TARGET}_total.mat"       # XFMtotal    
    LTA_TOTAL="$XFM_TOTAL_DIR/${base}_to_${TARGET}_total.lta"       # XFMtotal    
    
    # Now project BOLD directly to surface (no intermediate flirt)
    # We'll use projfrac-avg sampling across cortical ribbon as a common default.
    for hemi in lh rh; do
        if [ "${hemi}" = "lh" ]; then
            hemi_str="L"
        else
            hemi_str="R"
        fi
        lta_convert --infsl "$XFM_TOTAL" --outlta "$LTA_TOTAL" --src "$bold_path" --trg "$T1W_MASKED"
        out_name="${id}_space-fsnative_hemi-${hemi_str}_bold.func.gii"
        if [[ "${id}" == *ses-LE* ]]; then
            ses="ses-LE"
        else    
            ses="ses-RE"
        fi

        out="${COREG_ANAT_DIR}/${out_name}"
        echo "Running mri_vol2surf for ${hemi} -> ${out}"
        if [ ! -f "${out}" ]; then
            mri_vol2surf --cortex --hemi $hemi \
                --interp trilinear --o $out \
                --srcsubject $SUBJECT_ID \
                --reg $LTA_TOTAL \
                --projfrac-avg 0.000 1.000 0.200 \
                --mov $bold_path --trgsubject $SUBJECT_ID
        fi
        echo INJECTING INTO FPREP

        tfprep="${FPREP_OUTFS}/${ses}/func/${out_name}"
        cp -n ${out} ${tfprep}        

    done
done

# PYBEST 
PYB_OUT="${DIR_DATA_DERIV}/pybest_fsinject"
if [[ ! -d "$PYB_OUT" ]]; then
    mkdir $PYB_OUT
fi

for tses in "${SESSIONS[@]}"; do
    ses=${tses/ses-/}
    src_dir="$FPREP_IN_DIR/$tses/func"    
    if [[ ! -d "$src_dir" ]]; then
        echo "Skipping session $ses: source directory not found: $src_dir"
        continue
    fi
    
    call_pybest -s $SUBJECT -n $ses -o ${PYB_OUT} -c 1 -p 20 -t pRF,CSF -f $DERIV_DIR/${FPREP_ID}_fsinject -r fsnative

done











































# ---------------------- 7. Step 3: Transformation Application -----------------------------------------
echo "--- Applying Concatenated Transforms to 4D BOLD Runs ---"
exit 1 
for bold_path in "${BOLD_FILES[@]}"; do
    base=$(basename "$bold_path" .nii.gz)
    
    # Transformation matrices
    XFM_I_TO_REF="${RUN2REF_MATRIX[$bold_path]}"         # XFMi→ref
    XFM_REF_TO_ANAT="$REF2ANAT_MATRIX"                  # XFMref→anat
    XFM_TOTAL="$XFM_TOTAL_DIR/${base}_to_${TARGET}_total.mat"       # XFMtotal
    XFM_TOTAL_ITK="$XFM_TOTAL_DIR/${base}_to_${TARGET}_total_itk.txt"       # XFMtotal

    # Output file path
    R_I_TARGET="$COREG_ANAT_DIR/${base}_FLIRT_${TARGET}.nii.gz"

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
    if [[ ! -f "$R_I_TARGET" ]]; then
        echo "Applying total transform to 4D BOLD: $bold_path -> $R_I_TARGET"
        # flirt -in <input 4D> -ref <target T1w> -out <output 4D> -applyxfm -init <total matrix> -interp trilinear
        flirt -in "$bold_path" -ref "$TARGET_PATH" -out "$R_I_TARGET" \
              -applyxfm -init "$XFM_TOTAL" -interp trilinear
    else
        echo "Final resliced BOLD already exists: $R_I_TARGET. Skipping application."
    fi

done

echo "--- Script Complete ---"
echo "Final resliced BOLD files are located in: $COREG_ANAT_DIR"
echo "Transformation matrices are located in: $XFM_TOTAL_DIR"