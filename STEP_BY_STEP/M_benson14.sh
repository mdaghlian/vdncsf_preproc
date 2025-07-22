#!/bin/bash
# Initialize variables
sub=""

# Parse command-line arguments
# The colon after 's' and 'n' indicates that these options require an argument.
while getopts "s:n:" opt; do
  case $opt in
    s)
        sub="${OPTARG}"
        ;;
  esac
done

export SUBJECTS_DIR="/data1/projects/dumoulinlab/Lab_members/Marcus/projects/vdNCSF/BIDS_directory/derivatives/freesurfer"

# Check
export SURF_DIR=$SUBJECTS_DIR/sub-$sub
# Use find to check if any file contains "benson14" in the SURF_DIR
if find "${SURF_DIR}/surf" -type f -name "*benson14*mgz" -print -quit | grep -q .; then
    echo "Found 'benson14' file for $subject"
else
    echo "No 'benson14' file found in $subject"
    python -m neuropythy atlas sub-$sub --verbose 
fi

# Check if "b14" folder exists, if not, create it
if [ ! -d "${SURF_DIR}/label/b14" ]; then
    mkdir "${SURF_DIR}/label/b14"
    echo "Created 'b14' label folder for $subject"
fi
# Now convert to labels
for hemi in lh rh
do
    mri_surfcluster --in ${SURF_DIR}/surf/${hemi}.benson14_eccen.mgz --subject sub-$sub --hemi ${hemi} --thmin 0 --sign pos --no-adjust --olab ${SURF_DIR}/label/b14/${hemi}.benson14_eccen 
    mri_surfcluster --in ${SURF_DIR}/surf/${hemi}.benson14_sigma.mgz --subject sub-$sub --hemi ${hemi} --thmin 0 --sign pos --no-adjust --olab ${SURF_DIR}/label/b14/${hemi}.benson14_sigma 
    mri_surfcluster --in ${SURF_DIR}/surf/${hemi}.benson14_angle.mgz --subject sub-$sub --hemi ${hemi} --thmin 0 --sign pos --no-adjust --olab ${SURF_DIR}/label/b14/${hemi}.benson14_angle 
    mri_surfcluster --in ${SURF_DIR}/surf/${hemi}.benson14_varea.mgz --subject sub-$sub --hemi ${hemi} --thmin 0 --sign pos --no-adjust --olab ${SURF_DIR}/label/b14/${hemi}.benson14_varea
    # mri_surf2surf --srcsubject fsaverage --trgsubject $subject --hemi ${hemi} --sval ${SURF_DIR}/surf/${hemi}.benson14_varea.mgz --tval ${SURF_DIR}/surf/${hemi}.benson14_varea_native.mgz
done