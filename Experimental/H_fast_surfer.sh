#!/bin/bash

# Fix the registration problems... 

# Initialize a variable to store the subject ID
SUBJECT_ID=""
FS_ID=""
# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --sub)
      SUBJECT_ID="$2"
      shift 2
      ;;
    --fs)
      FS_ID="$2"
      shift 2
      ;;      
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done
DIR_DATA_DERIV="/data1/projects/dumoulinlab/Lab_members/Marcus/projects/vdNCSF/BIDS_directory/derivatives"
DIR_DATA_HOME="/data1/projects/dumoulinlab/Lab_members/Marcus/projects/vdNCSF/BIDS_directory"
# Clean up the subject ID to remove potential 'sub-' prefix
# This handles both 'ctrl05' and 'sub-ctrl05'
SUBJECT_ID=${SUBJECT_ID/sub-/}
SUBJECT_ID="sub-${SUBJECT_ID}"
FS_DIR=$DIR_DATA_DERIV/$FS_ID
if [ ! -d "$FS_DIR" ]; then 
    mkdir -p "$FS_DIR"
fi

fsfast_path=$DIR_DATA_HOME/code/fastsurfer-gpu.sif

T1w=$(find "$DIR_DATA_HOME/$SUBJECT_ID/ses-fprep" -type f -name "*MP2RAGE*T1w.nii.gz" | head -n 1)
T2w=$(find "$DIR_DATA_HOME/$SUBJECT_ID/ses-fprep" -type f -name "*3DTSE*T2w.nii.gz" | head -n 1)
echo $T1w
echo $T2w
singularity exec --nv --no-mount home,cwd -e \
    -B $DIR_DATA_DERIV:/data \
    -B $T1w:/t1w.nii.gz \
    -B $T2w:/t2w.nii.gz \
    -B $FS_DIR:/fsoutput \
    -B $DIR_DATA_HOME/code/license.txt:/license.txt \
    $fsfast_path \
    /fastsurfer/run_fastsurfer.sh \
    --fs_license /license.txt \
    --t1 /t1w.nii.gz --t2 /t2w.nii.gz --sid $SUBJECT_ID \
    --sd /fsoutput 
echo DONE