# [1] Download .sif image
singularity build fastsurfer-gpu.sif docker://deepmi/fastsurfer:latest

# [2] Write bash file "runs_fs.sh"


#!/bin/bash
# Initialize a variable to store the subject ID
SUBJECT_ID="" # sub-01
OUTPUT="" # 
T1w="" #
LICENSE=""
FSIMG=""

singularity exec --nv --no-mount home,cwd -e \
    -B $T1w:/t1w.nii.gz \
    -B $OUTPUT:/fsoutput \
    -B $LICENSE:/license.txt \
    $FSIMG \
    /fastsurfer/run_fastsurfer.sh \
    --fs_license /license.txt \
    --t1 /t1w.nii.gz --sid $SUBJECT_ID \
    --sd /fsoutput 



# Write qsub comand 
#!/bin/bash

log_dir=$DIR_DATA_HOME/code/vdncsf_preproc/STEP_BY_STEP/logs
qsub_cmd="qsub -q cuda.q@zeus -pe smp 4 -wd $log_dir -N fsfast${SUBJECT_ID} -o $log_dir/fsfast${SUBJECT_ID}.txt "
${qsub_cmd} H_fast_surfer.sh --sub ${SUBJECT_ID}