call_pybest -s ctrl02 -n LE -o \
    /data1/projects/dumoulinlab/Lab_members/Marcus/projects/vdNCSF/BIDS_directory/derivatives/pybest -r newfsnat -f /data1/projects/dumoulinlab/Lab_members/Marcus/projects/vdNCSF/BIDS_directory/derivatives/fmriprep \
    -c 1 -p 20 -t pRF --pre-only



call_pybest -s sub-ctrl02 -n ses-RE -o -c 1 \
    -p 20 -t pRF,CSF \
    --fprepdir     