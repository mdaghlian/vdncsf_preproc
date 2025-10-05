#!/usr/bin/env bash
sub_list=(ctrl02 ctrl03 ctrl04 ctrl05 ctrl06 ctrl07 ctrl08 gla01 gla02 gla03 gla04 gla05)
for sub in "${sub_list[@]}";
do 
    ./A_COPY_FILES.sh --sub $sub
done
