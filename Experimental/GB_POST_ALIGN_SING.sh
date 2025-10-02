#!/usr/bin/env bash
# run_afni_align.sh
#
# Wrapper script to run afni_align_fmriprep_to_t1.sh inside an AFNI Singularity container.
#
set -euo pipefail
IFS=$'\n\t' 

# ============================ CONFIGURATION =============================

# 1. Path to your AFNI Singularity image (or .sif file)
AFNI_SIF="/path/to/afni_latest.sif"

# 2. Path to your BIDS derivatives directory (where fmriprep outputs are)
# This directory will be set as DIR_DATA_DERIV inside the container.
HOST_DIR_DATA_DERIV="/data/bids_derivatives"

# 3. Path to your Freesurfer SUBJECTS_DIR
# This directory will be set as SUBJECTS_DIR inside the container.
HOST_SUBJECTS_DIR="/data/freesurfer/subjects"

# 4. Path to your afni_align_fmriprep_to_t1.sh script
# This path is mounted into the container for execution.
ALIGN_SCRIPT_PATH="/path/to/afni_align_fmriprep_to_t1.sh"

# 5. Define the subject and optional fMRIPrep ID to process
SUBJECT_ID="sub-01"
FPREP_ID="fmriprep"

# ========================================================================

# Check if the singularity image exists
if [[ ! -f "$AFNI_SIF" ]]; then
    echo "ERROR: Singularity image not found at: $AFNI_SIF"
    exit 1
fi

# Check if the alignment script exists
if [[ ! -f "$ALIGN_SCRIPT_PATH" ]]; then
    echo "ERROR: Alignment script not found at: $ALIGN_SCRIPT_PATH"
    exit 1
fi

# Ensure all paths exist on the host system
for dir in "$HOST_DIR_DATA_DERIV" "$HOST_SUBJECTS_DIR"; do
    if [[ ! -d "$dir" ]]; then
        echo "ERROR: Required host directory not found: $dir"
        exit 1
    fi
done

# Define the BIND mount arguments for Singularity. 
# We need to bind the derivatives, freesurfer, and the directory containing the script.
# The format is 'host_path:container_path'.
# Note: For simplicity, we are binding the HOST_DIR_DATA_DERIV and HOST_SUBJECTS_DIR
# to the same path inside the container.
BIND_MOUNTS="-B $HOST_DIR_DATA_DERIV:$HOST_DIR_DATA_DERIV"
BIND_MOUNTS="$BIND_MOUNTS -B $HOST_SUBJECTS_DIR:$HOST_SUBJECTS_DIR"

# Ensure the directory of the script is bound, so Singularity can find it.
# dirname is used to get the parent directory of the script.
SCRIPT_DIR=$(dirname "$ALIGN_SCRIPT_PATH")
BIND_MOUNTS="$BIND_MOUNTS -B $SCRIPT_DIR:$SCRIPT_DIR"

# Build the command that will be executed inside the container
CONTAINER_CMD=" \
    export DIR_DATA_DERIV='$HOST_DIR_DATA_DERIV' && \
    export SUBJECTS_DIR='$HOST_SUBJECTS_DIR' && \
    $ALIGN_SCRIPT_PATH --sub $SUBJECT_ID --fprep $FPREP_ID \
"

echo "=================================================="
echo "Starting AFNI alignment for $SUBJECT_ID with Singularity..."
echo "Container image: $AFNI_SIF"
echo "Derivatives DIR: $HOST_DIR_DATA_DERIV"
echo "Freesurfer DIR: $HOST_SUBJECTS_DIR"
echo "=================================================="

# Execute the command inside the Singularity container using 'exec'
singularity exec \
    --cleanenv \
    $BIND_MOUNTS \
    "$AFNI_SIF" \
    /bin/bash -c "$CONTAINER_CMD"

echo "=================================================="
echo "Singularity execution finished for $SUBJECT_ID."
echo "=================================================="