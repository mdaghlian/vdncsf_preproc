#!/bin/bash
wf_dir="/data1/projects/dumoulinlab/Lab_members/Marcus/projects/vdNCSF/wf_fmriprep_new"
fprep_out="/data1/projects/dumoulinlab/Lab_members/Marcus/projects/vdNCSF/BIDS_directory/derivatives/fprep_new"
rm -rf "$wf_dir"
rm -rf "$fprep_out"
sub=ctrl-02
deriv_dir="/data1/projects/dumoulinlab/Lab_members/Marcus/projects/vdNCSF/BIDS_directory/derivatives"
if [ ! -d "$wf_dir" ]; then
  mkdir -p "$wf_dir"
fi
if [ ! -d "$fprep_out" ]; then
  mkdir -p "$fprep_out"
fi
fprep_ver=/data1/projects/dumoulinlab/Lab_members/Marcus/projects/vdNCSF/BIDS_directory/code/fmriprep-latest.sif
# fprep_ver=/packages/singularity_containers/containers_bids-fmriprep--20.2.5.simg
singularity run --cleanenv \
  -B /data1/projects/dumoulinlab/Lab_members/Marcus/projects/vdNCSF/BIDS_directory:/data \
  -B $fprep_out:/out \
  -B /data1/projects/dumoulinlab/Lab_members/Marcus/projects/vdNCSF/BIDS_directory/derivatives/freesurfer:/fs \
  -B /data1/projects/dumoulinlab/Lab_members/Marcus/projects/vdNCSF/BIDS_directory/code/license.txt:/license.txt \
  -B $wf_dir:/wf \
  $fprep_ver \
  /data /out participant \
  --participant-label ctrl02 \
  --fs-license-file /license.txt \
  --fs-subjects-dir /fs \
  --output-spaces T1w fsnative fsaverage func \
  --bold2anat-init t2w \
  --verbose \
  --md-only-boilerplate --stop-on-first-crash --nthreads 8 \
  --work-dir /wf \
  --skip-bids-validation --verbose \
  # --bids-filter-file /data/code/vdncsf_preproc/vd_fprep/F_fmriprep_config.json 

#
#   --force-bbr
# /data1/projects/dumoulinlab/Lab_members/Marcus/projects/vdNCSF/BIDS_directory/code/fmriprep-latest.sif \
# /packages/singularity_containers/containers_bids-fmriprep--20.2.5.simg \  

#   --nthreads 8 \
#   --omp-nthreads 8 \
#   --mem_mb 64000 \


# singularity run --cleanenv -B /data1/projects/dumoulinlab/Lab_members/Marcus:/data1/projects/dumoulinlab/Lab_members/Marcus /packages/singularity_containers/containers_bids-fmriprep--20.2.5.simg /data1/projects/dumoulinlab/Lab_members/Marcus/projects/vdNCSF/BIDS_directory /data1/projects/dumoulinlab/Lab_members/Marcus/projects/vdNCSF/BIDS_directory/derivatives participant --participant-label ctrl04 --skip-bids-validation --md-only-boilerplate --fs-license-file /data1/projects/dumoulinlab/Lab_members/Marcus/projects/vdNCSF/BIDS_directory/code/license.txt --output-spaces fsnative func --fs-subjects-dir /data1/projects/dumoulinlab/Lab_members/Marcus/projects/vdNCSF/BIDS_directory/derivatives/freesurfer --work-dir /data1/projects/dumoulinlab/Lab_members/Marcus/projects/logs/fmriprep/vdNCSF/BIDS_directory --stop-on-first-crash      --bold2t1w-init register  --nthreads 1