#!/usr/bin/env bash
#
# AFNI-Based fMRI Preprocessing Alignment Script
# Purpose: Align all fMRIPrep BOLD runs to the first run's mean, then align the
# reference mean to the T1w anatomy, and apply the concatenated transform to all 4D BOLD runs.
# Tools used: AFNI (3dAllineate, 3dTstat/3dMean, cat_matvec)
#
set -euo pipefail
IFS=$'\n\t'

# ---------------------- 1. Argument Parsing and Validation -----------------------

SUBJECT_ID=""
DERIV_DIR=${DIR_DATA_DERIV:-}
SRC_DIR=${DIR_DATA_SOURCE:-}
DOF_VOL=12        # default inter-run registration DOF (6 -> rigid-body)
DOF_ANAT=12      # default func->anat registration DOF (12 -> affine)
FPREP_ID="fmriprep"
VALID_DOFS=(6 7 9 12) # note: AFNI maps to warp types (we'll interpret 6->shift_rotate, 12->affine_general)
SESSIONS=(ses-LE ses-RE)
FPREP_START="bold" # T1w
FOUT_ID=""

contains_element () {
  local e match="$1"
  shift
  for e; do [[ "$e" == "$match" ]] && return 0; done
  return 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --sub) SUBJECT_ID="$2"; shift 2;;
        --deriv_dir) DERIV_DIR="$2"; shift 2;;
        --dof_vol) DOF_VOL="$2"; shift 2;;
        --dof_anat) DOF_ANAT="$2"; shift 2;;
        --fprep_id) FPREP_ID="$2"; shift 2;;
        --fprep_start)
            FPREP_START="$2"; shift 2;;     
        --fout_id)
            FOUT_ID="$2"; shift 2;;             
        *) echo "ERROR: Unknown option: $1"; exit 1;;
    esac
done

# Normalize subject ID
SUBJECT_ID=${SUBJECT_ID/sub-/}
SUBJECT_ID="sub-${SUBJECT_ID}"

# CALL THE COPY SCRIPT (same as your pipeline)
source ./A_COPY_FILES.sh --sub $SUBJECT_ID --deriv_dir $DERIV_DIR --fprep_id $FPREP_ID

echo "--- AFNI Alignment Script Configuration ---"
echo "Subject ID: $SUBJECT_ID"
echo "Derivatives Dir: $DERIV_DIR"
echo "fMRIPrep Dir Name: $FPREP_ID"
echo "DOF (Vol-to-Ref): $DOF_VOL (Inter-run alignment; AFNI warp type chosen accordingly)"
echo "DOF (Ref-to-Anat): $DOF_ANAT (Functional-to-anatomical alignment)"
echo "------------------------------------------"

# Output directories (mirror your previous structure)
TALIGN_DIR="$ALIGN_OUT_DIR/afni"
COREG_DIR="$TALIGN_DIR/coreg_ref${DOF_VOL}"
XFM_DIR="$TALIGN_DIR/xfm_ref${DOF_VOL}"
mkdir -p "$COREG_DIR" "$XFM_DIR"

# ******** TAKE FIRST RUN - as reference 
REF_BOLD=${BOLD_FILES[0]}
REF_BOLD_BASE=$(basename "$REF_BOLD")
REF_ID=${REF_BOLD_BASE%%.*}
REF_MEAN=${RUN_MEAN["$REF_ID"]}

echo "Reference BOLD (first run) chosen: $REF_BOLD_BASE"

# ---------------------- Helper: map DOF -> AFNI -warp type -----------------------
# AFNI 3dAllineate warp options: shift_only (3), shift_rotate (6), shift_rotate_scale (9), affine_general (12)
warp_from_dof() {
    local dof="$1"
    case "$dof" in
        6)  echo "shift_rotate" ;;    # rigid-body
        9)  echo "shift_rotate_scale" ;;
        12) echo "affine_general" ;;
        3)  echo "shift_only" ;;
        *)  echo "affine_general" ;;   # fallback
    esac
}

WARP_VOL=$(warp_from_dof $DOF_VOL)
WARP_ANAT=$(warp_from_dof $DOF_ANAT)

# Inter-run registration: run-mean -> reference-mean using 3dAllineate
declare -A RUN2REF_MATRIX
declare -A MCOREG_RUN2REF

for bold_path in "${BOLD_FILES[@]}"; do
    base=$(basename "$bold_path" .nii.gz)
    id=${base%%.*}
    mean_path="${RUN_MEAN[$id]}"
    OUTPUT_MATRIX="$XFM_DIR/${base}_to_ref.aff12.1D"   # AFNI 12-number matrix format (text file)
    RUN2REF_MATRIX["$bold_path"]="$OUTPUT_MATRIX"
    TCOREG="$COREG_DIR/${base}_mean_in_ref.nii.gz"
    MCOREG_RUN2REF["${id}"]="$TCOREG"

    # a. Reference Run (Identity matrix)
    if [[ "$bold_path" == "$REF_BOLD" ]]; then
        if [[ ! -f "$OUTPUT_MATRIX" ]]; then
            echo "Reference run: creating identity matrix: $OUTPUT_MATRIX"
            # AFNI stores 3x4 (12 numbers) as 3 rows; create identity transform:
            cat > "$OUTPUT_MATRIX" <<'EOF'
1 0 0 0
0 1 0 0
0 0 1 0
EOF
            # copy ref mean as the aligned output
            cp "$REF_MEAN" "$TCOREG"
        fi
        continue
    fi

    # b. Other Runs (3dAllineate)
    if [[ -f "$OUTPUT_MATRIX" ]]; then
        echo "Found existing run->ref matrix for $base. Skipping 3dAllineate."
        continue
    fi

    echo "3dAllineate (Moving: ${base}_mean -> Reference: ${REF_BOLD_BASE}_mean, WARP=$WARP_VOL)"
    # For intra-EPI (same-modality) alignment, LPC is commonly used for EPI/EPI; leastsq also works.
    # Here we use lpc (local Pearson correlation) which works well for EPI contrast.
    # -final wsinc5 gives good resampling quality for the preview output; we keep the matrix saved for concatenation.
    3dAllineate -source "$mean_path" -base "$REF_MEAN" \
                -prefix "$TCOREG" \
                -1Dmatrix_save "$OUTPUT_MATRIX" \
                -cost lpc -warp "$WARP_VOL" -final wsinc5 -verb

done

# ---- CREATE GRAND MEAN of the run-means aligned in ref space
# collect all aligned mean files and average them
ALIGNED_MEANS=()
for bold_path in "${BOLD_FILES[@]}"; do
    base=$(basename "$bold_path" .nii.gz)
    id=${base%%.*}
    ALIGNED_MEANS+=( "${MCOREG_RUN2REF[$id]}" )
done

GRAND_MEAN="$COREG_DIR/A_GRAND_MEAN.nii.gz"
if [[ ! -f "$GRAND_MEAN" ]]; then
    echo "Computing GRAND_MEAN from aligned run means..."
    # 3dMean handles multiple inputs
    3dMean -prefix "$GRAND_MEAN" "${ALIGNED_MEANS[@]}"
else
    echo "Found existing GRAND_MEAN: $GRAND_MEAN"
fi

# ---------------------- Functional-to-Anatomical Registration (Reference mean -> T1w) -----------------

COREG_ANAT_DIR="$TALIGN_DIR/coreg_ref${DOF_VOL}_an${DOF_ANAT}"
XFM_TOTAL_DIR="$TALIGN_DIR/xfm${DOF_VOL}_an${DOF_ANAT}"
mkdir -p "${COREG_ANAT_DIR}" "${XFM_TOTAL_DIR}"

# We'll compute a REF->ANAT matrix, but note 3dAllineate's -1Dmatrix_save file is the base->input transform:
# if we call: 3dAllineate -source REF_MEAN -base T1 -> the saved matrix maps T1 -> REF (base -> input).
# Later we'll invert that when concatenating (see cat_matvec usage below).
REF2ANAT_MATRIX="$TALIGN_DIR/${REF_ID}_to_T1w.aff12.1D"
REF2ANAT_OUT="$COREG_ANAT_DIR/${REF_ID}_mean_in_T1w.nii.gz"

if [[ ! -f "$REF2ANAT_MATRIX" ]]; then
    echo "3dAllineate (Moving: Reference mean -> Fixed: T1w anatomical, WARP=$WARP_ANAT)"
    # cost lpc+ZZ is robust for EPI->anat cross-modal registration; giant_move/big_move options can help if
    # there are large initial offsets. We avoid automatic giant_move here but you can add -twopass or -giant_move if needed.
    3dAllineate -source "$REF_MEAN" -base "$T1W_MASKED" \
                -prefix "$REF2ANAT_OUT" \
                -1Dmatrix_save "$REF2ANAT_MATRIX" \
                -cost lpc+ZZ -warp "$WARP_ANAT" -final wsinc5 -verb
else
    echo "Found existing ref->anat matrix: $REF2ANAT_MATRIX. Skipping 3dAllineate."
fi

# *********************** Compose transforms and test-apply ***********************
# For each run: total transform mapping RUN -> T1 = (REF2ANAT)^(-1) * (RUN2REF)^(-1)
# AFNI cat_matvec can invert matrices with -I and concatenate them; this follows AFNI examples.
# See cat_matvec docs and 3dAllineate -1Dmatrix_apply usage. (We invert both because saved mats are base->input.)
#
# order used here (per AFNI examples):
#   cat_matvec -ONELINE -I REF2ANAT_MATRIX -I RUN2REF_MATRIX > XFM_TOTAL
#
# Then apply via 3dAllineate -1Dmatrix_apply XFM_TOTAL -master T1 -> output in T1 grid.

for bold_path in "${BOLD_FILES[@]}"; do
    base=$(basename "$bold_path" .nii.gz)
    id=${base%%.*}
    mean_path="${RUN_MEAN[$id]}"

    XFM_I_TO_REF="${RUN2REF_MATRIX[$bold_path]}"               # saved by 3dAllineate (base=REF, source=RUN) => REF -> RUN (base->input)
    XFM_REF_TO_ANAT="$REF2ANAT_MATRIX"                        # saved by 3dAllineate (base=T1, source=REF) => T1 -> REF (base->input)
    XFM_TOTAL="$XFM_TOTAL_DIR/${base}_to_T1w_total.aff12.1D"  # final concatenated matrix (one-line 12 numbers)
    R_I_T1W="$COREG_ANAT_DIR/${base}_AFNI_T1w_MEAN.nii.gz"

    if [[ ! -f "$XFM_TOTAL" ]]; then
        echo "Composing total transform for $base: (REF2ANAT)^(-1) * (RUN2REF)^(-1) -> $XFM_TOTAL"
        # Use -ONELINE for a single-line 12-number file (convenient for -1Dmatrix_apply).
        # We invert both saved matrices (they are base->input); inverting yields input->base as needed.
        cat_matvec -ONELINE -I "$XFM_REF_TO_ANAT" -I "$XFM_I_TO_REF" > "$XFM_TOTAL"
    else
        echo "Found existing total transform: $XFM_TOTAL. Skipping concatenation."
    fi

    if [[ ! -f "$R_I_T1W" ]]; then
        echo "Applying total transform to reference mean (test): $mean_path -> $R_I_T1W"
        # apply the composed matrix and write output on the T1 grid using -master
        3dAllineate -1Dmatrix_apply "$XFM_TOTAL" \
                    -source "$mean_path" -master "$T1W_MASKED" \
                    -prefix "$R_I_T1W" -final wsinc5 -verb
    else
        echo "Final resliced mean already exists: $R_I_T1W. Skipping application."
    fi
done

# ---------------------- Apply concatenated transforms to full 4D BOLD runs -------------------------
echo "--- Applying Concatenated Transforms to 4D BOLD Runs ---"

for bold_path in "${BOLD_FILES[@]}"; do
    base=$(basename "$bold_path" .nii.gz)
    XFM_TOTAL="$XFM_TOTAL_DIR/${base}_to_T1w_total.aff12.1D"
    R_I_T1W="$COREG_ANAT_DIR/${base}_AFNI_T1w.nii.gz"

    if [[ ! -f "$XFM_TOTAL" ]]; then
        echo "Missing total matrix for $base: $XFM_TOTAL. Skipping."
        continue
    fi

    if [[ ! -f "$R_I_T1W" ]]; then
        echo "Applying total transform to 4D BOLD: $bold_path -> $R_I_T1W"
        # Use 3dAllineate's -1Dmatrix_apply to apply same affine to all sub-bricks; set -master to T1 grid
        3dAllineate -1Dmatrix_apply "$XFM_TOTAL" \
                    -source "$bold_path" -master "$T1W_MASKED" \
                    -prefix "$R_I_T1W" -final wsinc5 -verb
    else
        echo "Final resliced 4D BOLD already exists: $R_I_T1W. Skipping."
    fi
done

echo "--- AFNI Script Complete ---"
echo "Final resliced BOLD files are located in: $COREG_ANAT_DIR"
echo "Transformation matrices are located in: $XFM_TOTAL_DIR"
