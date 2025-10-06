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
DOF_VOL=6
DOF_ANAT=12
FPREP_ID="fmriprep"
VALID_DOFS=(6 7 9 12)
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

# CALL THE COPY SCRIPT
source ./A_COPY_FILES.sh --sub $SUBJECT_ID --deriv_dir $DERIV_DIR --fprep_id $FPREP_ID

# Print summary
echo "--- GREEDY Alignment Script Configuration ---"
echo "Subject ID: $SUBJECT_ID"
echo "Derivatives Dir: $DERIV_DIR"
echo "fMRIPrep Dir Name: $FPREP_ID"
echo "DOF (Vol-to-Ref): $DOF_VOL (Inter-run alignment)"
echo "DOF (Ref-to-Anat): $DOF_ANAT (Functional-to-anatomical alignment)"
echo "------------------------------------------"

# Define output directory structure
TALIGN_DIR="$ALIGN_OUT_DIR/greedy"
COREG_DIR="$TALIGN_DIR/coreg_ref"
XFM_DIR="$TALIGN_DIR/xfm_ref"

mkdir -p "$COREG_DIR" "$XFM_DIR"

# ******** TAKE FIRST RUN - as reference 
REF_BOLD=${BOLD_FILES[0]}
REF_BOLD_BASE=$(basename "$REF_BOLD")
REF_ID=${REF_BOLD_BASE%%.*}
REF_MEAN=${RUN_MEAN["$REF_ID"]}

echo "Reference BOLD (first run) chosen: $REF_BOLD_BASE"

# Single declaration (removed duplicate)
declare -A RUN2REF_PREFIX

# helper: run greedy affine registration (fixed -> moving -> output matrix)
greedy_affine(){
    local fixed="$1"
    local moving="$2"
    local output_matrix="$3"

    # If already exists return
    if [[ -f "$output_matrix" ]]; then
        echo "Matrix exists: $output_matrix"
        return 0
    fi

    echo "Running greedy affine: fixed=$fixed moving=$moving out=$output_matrix"
    # basic invocation; tweak -m / -n / -ia-image-centers as needed for your data
    greedy -d 3 -a \
        -i "$fixed" "$moving" \
        -o "$output_matrix" \
        -ia-image-centers \
        -m WNCC 2x2x2 \
        -n 100x50x10
}
for bold in "${BOLD_FILES[@]}"; do
    base=$(basename "$bold")
    id=${base%%.*}
    mean=${RUN_MEAN[$id]}

    outpref="${XFM_DIR}/run2ref_${id}_"
    OUTPUT_MATRIX="${outpref}affine.mat"

    # If this is the reference run, create identity matrix
    if [[ "$bold" == "$REF_BOLD" ]]; then
        if [[ ! -f "$OUTPUT_MATRIX" ]]; then
            echo "Identity registration for $id. Creating identity matrix: $OUTPUT_MATRIX"
            cat > "$OUTPUT_MATRIX" <<'EOF'
1 0 0 0
0 1 0 0
0 0 1 0
0 0 0 1
EOF
        else
            echo "Identity matrix already exists for $id: $OUTPUT_MATRIX"
        fi
        continue
    fi

    # run greedy affine
    greedy_affine "$REF_MEAN" "$mean" "$OUTPUT_MATRIX"
done

# ---------------------- Register reference mean to T1w anatomy -----------------
REF2ANAT_PREF="$XFM_DIR/ref2anat_"
REF2ANAT_MATRIX="${REF2ANAT_PREF}affine.mat"

if [[ ! -f "$REF2ANAT_MATRIX" ]]; then
    echo "Registering reference mean ($REF_MEAN) -> T1w anatomy ($T1W_MASKED) --> matrix: $REF2ANAT_MATRIX"
    greedy_affine "$T1W_MASKED" "$REF_MEAN" "$REF2ANAT_MATRIX"
else
    echo "Already have ref->anat matrix: $REF2ANAT_MATRIX"
fi
# ---------------------- Apply transforms (quick checks + full 4D option) -----------------
# Helper: reslice a single 3D image (mean) into T1 space for quick visual check
reslice_mean_to_anat(){
    local mean_img="$1"
    local out_img="$2"
    local run2ref_matrix="$3"
    local ref2anat_matrix="$4"

    # Ensure matrices exist
    if [[ ! -f "$run2ref_matrix" || ! -f "$ref2anat_matrix" ]]; then
        echo "Missing transform matrix: $run2ref_matrix or $ref2anat_matrix"
        return 1
    fi

    # If output exists, skip
    if [[ -f "$out_img" ]]; then
        echo "Quick coreg exists: $out_img"
        return 0
    fi

    echo "Reslicing mean $mean_img -> $T1W_MASKED as $out_img"

    # Apply: transforms listed left->right as applied (greedy applies right-most first),
    # so provide ref2anat then run2ref (so moving->ref->anat)
    greedy -d 3 \
        -rf "$T1W_MASKED" \
        -rm "$mean_img" "$out_img" \
        -r "$ref2anat_matrix" "$run2ref_matrix"
}

# Helper: apply (affine) transforms to an entire 4D BOLD using ANTs WarpTimeSeriesImageMultiTransform
apply_transforms_4d_with_ants(){
    local input4d="$1"
    local out4d="$2"
    local ref_image="$3"
    shift 3
    local transforms=("$@")

    if ! command -v WarpTimeSeriesImageMultiTransform &>/dev/null; then
        echo "WarpTimeSeriesImageMultiTransform not available. Skipping 4D warp with ANTs."
        return 1
    fi

    echo "Applying transforms to 4D: $input4d -> $out4d"
    # Example usage: WarpTimeSeriesImageMultiTransform 4 input4d out4d ref -R ref transforms...
    # Provide reference with -R, then list transforms in order from last-to-first as expected by ANTs
    WarpTimeSeriesImageMultiTransform 4 "$input4d" "$out4d" -R "$ref_image" "${transforms[@]}"
}

# Now run quick checks and optionally apply to 4D
for bold in "${BOLD_FILES[@]}"; do
    base=$(basename "$bold")
    id=${base%%.*}
    mean=${RUN_MEAN[$id]}

    run2ref_matrix="$XFM_DIR/run2ref_${id}_affine.mat"
    ref2anat_matrix="$REF2ANAT_MATRIX"

    coreg_quick="$COREG_DIR/${id}_Qcoreg.nii.gz"

    # Quick 3D reslice check
    reslice_mean_to_anat "$mean" "$coreg_quick" "$run2ref_matrix" "$ref2anat_matrix" || true

    # # If user wants a full 4D reslice (and ANTs tool is available), create a resliced 4D file
    # out4d="$ALIGN_DIR/coreg/${id}_resliced_to_T1.nii.gz"
    # if [[ ! -f "$out4d" && -f "$bold" ]]; then
    #     # Compose transforms for ANTs: ANTs expects transforms from moving->fixed as a list;
    #     # here moving is original BOLD's space -> (run->ref) -> (ref->anat). Provide matrices in the right order.
    #     # Note: Depending on your ANTs version, you may need to prepend 'AffineTransform' or similar. Adjust as needed.
    #     transforms_for_ants=("$run2ref_matrix" "$ref2anat_matrix")
    #     apply_transforms_4d_with_ants "$bold" "$out4d" "$T1_masked_nii" "${transforms_for_ants[@]}" || true
    # fi
done

echo "DONE QUICK COREG CHECKS !!!"
