#!/bin/bash
VDNCSF_DIR=
singularity run --cleanenv \
  -B /data1/projects/dumoulinlab/Lab_members/Marcus/projects/vdNCSF/BIDS_directory:/data \
  -B /data1/projects/dumoulinlab/Lab_members/Marcus/projects/vdNCSF/BIDS_directory/derivatives/newfprep:/out \
  -B /data1/projects/dumoulinlab/Lab_members/Marcus/projects/vdNCSF/BIDS_directory/derivatives/freesurfer:/fs \
  -B /data1/projects/dumoulinlab/Lab_members/Marcus/projects/vdNCSF/BIDS_directory/code/license.txt:/license.txt \
  -B /data1/projects/dumoulinlab/Lab_members/Marcus/projects/vdNCSF/wf_fmriprep_new:/wf \
  /data1/projects/dumoulinlab/Lab_members/Marcus/projects/vdNCSF/BIDS_directory/code/fmriprep-latest.sif \
  /data /out participant \
  --participant-label ctrl04 \
  --fs-license-file /license.txt \
  --fs-subjects-dir /fs \
  --output-spaces T1w fsnative fsaverage func \
  --verbose \
  --md-only-boilerplate --stop-on-first-crash --nthreads 8 \
  --work-dir /wf \

#
#   --force-bbr
# /data1/projects/dumoulinlab/Lab_members/Marcus/projects/vdNCSF/BIDS_directory/code/fmriprep-latest.sif \
# /packages/singularity_containers/containers_bids-fmriprep--20.2.5.simg \  

#   --nthreads 8 \
#   --omp-nthreads 8 \
#   --mem_mb 64000 \


# singularity run --cleanenv -B /data1/projects/dumoulinlab/Lab_members/Marcus:/data1/projects/dumoulinlab/Lab_members/Marcus /packages/singularity_containers/containers_bids-fmriprep--20.2.5.simg /data1/projects/dumoulinlab/Lab_members/Marcus/projects/vdNCSF/BIDS_directory /data1/projects/dumoulinlab/Lab_members/Marcus/projects/vdNCSF/BIDS_directory/derivatives participant --participant-label ctrl04 --skip-bids-validation --md-only-boilerplate --fs-license-file /data1/projects/dumoulinlab/Lab_members/Marcus/projects/vdNCSF/BIDS_directory/code/license.txt --output-spaces fsnative func --fs-subjects-dir /data1/projects/dumoulinlab/Lab_members/Marcus/projects/vdNCSF/BIDS_directory/derivatives/freesurfer --work-dir /data1/projects/dumoulinlab/Lab_members/Marcus/projects/logs/fmriprep/vdNCSF/BIDS_directory --stop-on-first-crash      --bold2t1w-init register  --nthreads 1