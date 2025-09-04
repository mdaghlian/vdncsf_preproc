#!/bin/bash

log_dir=$DIR_DATA_HOME/code/vdncsf_preproc/STEP_BY_STEP/logs
qsub_cmd="qsub -q cuda.q@zeus -pe smp 4 -wd $log_dir -N fsfast${SUBJECT_ID} -o $log_dir/fsfast${SUBJECT_ID}.txt "
${qsub_cmd} H_fast_surfer.sh --sub ${SUBJECT_ID}