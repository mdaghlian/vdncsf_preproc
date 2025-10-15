#!/usr/bin/env bash
sub_list=(ctrl02 ctrl03 ctrl04 ctrl05 ctrl06 ctrl07 ctrl08 gla01 gla02 gla03 gla04 gla05)
logs=/data1/projects/dumoulinlab/Lab_members/Marcus/projects/vdNCSF/BIDS_directory/code/vdncsf_preproc/Experimental/POST_FPREP_ALIGN/logs
for sub in "${sub_list[@]}";
do 
    qsub -q long.q@zeus -pe smp 1 -V -wd  ${logs} -N ${sub} -o ${logs}/${sub}.txt B_FLIRT_test.sh --sub $sub
    # exit 1
done
