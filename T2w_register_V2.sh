#!/bin/bash
# Initialize variables
SUB_VAR=""
SES_VAR="ses-A"

# Parse command-line arguments
# The colon after 's' and 'n' indicates that these options require an argument.
while getopts "s:n:" opt; do
  case $opt in
    s)
      SUB_VAR="sub-$OPTARG"
      ;;
    n)
      SES_VAR="ses-$OPTARG"
      ;;
  esac
done

# [1] Create the T1w image from the MP2RAGE data, using call_mp2rage
echo "First creating T1w image from MP2RAGE data (call_mp2rage)"
mp2rage_input_dir="${DIR_DATA_HOME}/${SUB_VAR}/${SES_VAR}"
mp2rage_output_dir="${DIR_DATA_DERIV}/pymp2rage/${SUB_VAR}/${SES_VAR}"
mp2rage_name="${SUB_VAR}_${SES_VAR}_acq-MP2RAGE"
if [ ! -d "${mp2rage_output_dir}" ]; then
    mkdir -p "${mp2rage_output_dir}"    
fi
cmd=(
    call_mp2rage
    --inputdir "${mp2rage_input_dir}"
    --outputdir "${mp2rage_output_dir}"
    --name "${mp2rage_name}"
)
echo "${cmd[@]}"
echo
eval "${cmd[@]}"

ANAT_PATH=${DIR_DATA_HOME}/${SUB_VAR}/${SES_VAR}/anat
PYMP2RAGE_PATH=${DIR_DATA_DERIV}/pymp2rage/${SUB_VAR}/${SES_VAR}

# Check for T2w and T2w not coreg 
ANAT_T2=$(find ${ANAT_PATH} -type f -name "*T2w*" -and -name "*.nii.gz" -and -not -name "*notcoreg*")
ANAT_NOTCOREG_T2=$(find ${ANAT_PATH} -type f -name "*T2w_notcoreg*" -and -name "*.nii.gz")
# If one of the above doesn't exists, create the name by replacing relevant part

if [ -z $ANAT_T2 ]; then
    ANAT_T2="${ANAT_NOTCOREG_T2/T2w_notcoreg/T2w}"
else
    ANAT_NOTCOREG_T2="${ANAT_T2/T2w/T2w_notcoreg}"
fi
PYMP_T2=$(find ${PYMP2RAGE_PATH} -type f -name "*T2w" -and -name "*.nii.gz")
PYMP_T1=$(find ${PYMP2RAGE_PATH} -type f -name "*acq-MP2RAGE_T1w.nii.gz")

if [[ -f "$ANAT_T2" && -f "$ANAT_NOTCOREG_T2" ]]; then
    echo "Both ${ANAT_T2} and ${ANAT_NOTCOREG_T2} exist" 
else
    # [1] rename ANAT T2 
    # Find the T2W files -> rename them to "uncoreg"
    if [ ! -f ${ANAT_NOTCOREG_T2} ]; then
        for file in "${ANAT_PATH}"/*T2w*; do          
            mv "$file" "${file/T2w/T2w_notcoreg}"
        done
    fi
    # [2] Coregister
    if [ ! -f "${ANAT_PATH}/T1to2_coreg_genaff.mat" ]; then
        echo Doing registration
        call_antsregistration ${PYMP_T1} ${ANAT_NOTCOREG_T2} ${ANAT_PATH}/T1to2_coreg_ rigid
    fi

    echo Applying transform
    call_antsapplytransforms ${PYMP_T1} ${ANAT_NOTCOREG_T2} ${ANAT_T2} ${ANAT_PATH}/T1to2_coreg_genaff.mat

fi

echo "Updating T2 in pymp2rage" 
if [ ! -z ${PYMP_T2} ]; then
    rm ${PYMP_T2}
fi

if [ -f ${ANAT_T2} ]; then
    cp ${ANAT_T2} ${PYMP2RAGE_PATH}/
fi

# Finally - run the full spinoza_qmri pipeline
echo "Running spinoza_qmri pipeline"
master -m 04 -s ${SUB_VAR} -n ${SES_VAR}

