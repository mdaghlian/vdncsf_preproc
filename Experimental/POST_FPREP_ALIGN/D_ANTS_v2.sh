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
FPREP_ID="fmriprep"
MEANS_ONLY=0                 # if 1, run the mean-only (QC) stage and exit
FPREP_START="bold" # T1w
FOUT_ID=""
REG_ANAT="T1w"
usage(){
    cat <<EOF
Usage: $0 [--sub SUBID] [--deriv_dir PATH] [--reg_vol PRES] [--reg_anat PRES] [--preset fast|medium|precise] [--fprep_id NAME] [--means_only]
  --sub         subject id (with or without "sub-")
  --deriv_dir   derivatives directory (overrides default)
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
        --fprep_id)
            FPREP_ID="$2"; shift 2;;
        --means_only|--qc_only)
            MEANS_ONLY=1; shift 1;;
        --fprep_start)
            FPREP_START="$2"; shift 2;;     
        --fout_id)
            FOUT_ID="$2"; shift 2;;     
        --reg_anat)
            REG_ANAT="$2"; shift 2;;                             
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

echo "--- ANTs (JURJEN) Alignment Script Configuration ---"
echo "Subject ID: $SUBJECT_ID"
echo "Derivatives Dir: $DERIV_DIR"
echo "fMRIPrep Dir Name: $FPREP_ID"
echo "Ref->Anat registration: $REG_ANAT"
echo "Means-only (QC) mode: $MEANS_ONLY"
echo "------------------------------------------"

# Output directories (mirror your original structure)
TALIGN_DIR="${ALIGN_OUT_DIR}/JHants"
COREG_DIR="${TALIGN_DIR}/coreg_ref0"
XFM_DIR="${TALIGN_DIR}/xfm_ref0"
mkdir -p "$COREG_DIR" "$XFM_DIR"

# ******** TAKE FIRST RUN - as reference
REF_BOLD=${BOLD_FILES[0]}
REF_BOLD_BASE=$(basename "$REF_BOLD")
REF_ID=${REF_BOLD_BASE%%.*}
REF_MEAN=${RUN_MEAN["$REF_ID"]}

echo "Reference BOLD (first run) chosen: $REF_BOLD_BASE"
echo "Reference mean: $REF_MEAN"

# ---------------------- 5. Step 1: Inter-Run Registration (BOLD mean → Reference mean) -----------------

declare -A RUN2REF_MATRIX
declare -A MCOREG_RUN2REF

for bold_path in "${BOLD_FILES[@]}"; do
    base=$(basename "$bold_path" .nii.gz)
    id=${base%%.*}
    TMEAN="${RUN_MEAN[$id]}"
    PREFIX="${XFM_DIR}/${base}_to_ref_"
    TMATRIX="${PREFIX}genaff.mat"
    RUN2REF_MATRIX["${id}"]="${TMATRIX}"
    TCOREG="$COREG_DIR/${base}_mean_in_ref.nii.gz"
    MCOREG_RUN2REF["${id}"]="$TCOREG"
    # a. Reference Run (identity)
    # if [[ "$bold_path" == "$REF_BOLD" ]]; then
    #     call_antsregistration --affine -j 10 $REF_MEAN $mean_path $PREFIX 
    #     continue
    # fi

    # b. Other Runs (ANTs)
    # if [[ -f "${RUN2REF_AFFINE[$bold_path]}" || -f "${RUN2REF_WARP[$bold_path]}" ]]; then
    #     echo "Found existing run->ref transform(s) for $base. Skipping registration."
    #     continue
    # fi
    if [[ ! -f "${TMATRIX}" ]]; then 
        call_antsregistration --rigid -j 10 $REF_MEAN $TMEAN $PREFIX 
    fi
    if [[ ! -f "${TCOREG}" ]]; then 
        call_antsapplytransforms $REF_MEAN $TMEAN $TCOREG $TMATRIX
    fi
    

done