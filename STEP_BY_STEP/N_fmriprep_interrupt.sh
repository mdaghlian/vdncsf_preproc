#!/bin/bash
source /etc/profile.d/modules.sh
module load freesurfer/7.4.1 
sub=$1
# exit 


# ***** CHANGE THIS PATH *******
bids_dir=/data1/projects/dumoulinlab/Lab_members/Marcus/projects/vdNCSF/BIDS_directory
deriv_dir=$bids_dir/derivatives

# Where we put the workflow (must be outside of bids dir)
# ***** CHANGE THIS PATH *******
wf_dir=/data1/projects/dumoulinlab/Lab_members/Marcus/projects/vdNCSF/wf_fmriprep_r1/$sub

# Outputs...
fprep_out="$deriv_dir/fprepmini"
if [ ! -d "$wf_dir" ]; then
  mkdir -p "$wf_dir"
fi
if [ ! -d "$fprep_out" ]; then
  mkdir -p "$fprep_out"
fi

# ******************* DOUBLE CHECKING BIDS FOR ANATOMIES *******************************
# [1] Create a new directory for the "fmriprep safe anatomies" -> make everything perfect
# -> ignore the mess inside ses-A...
fprep_ses=$bids_dir/sub-$sub/ses-fprep/anat
fprep_t1w=$fprep_ses/sub-${sub}_ses-fprep_acq-MP2RAGE_T1w.nii.gz
fprep_t2w=$fprep_ses/sub-${sub}_ses-fprep_acq-3DTSE_T2w.nii.gz

a_ses=$bids_dir/sub-$sub/ses-A/anat
if [ ! -d "$fprep_ses" ]; then
  mkdir -p $fprep_ses
fi
# Copy T2w in nice way... 
if [ ! -f "$fprep_t2w" ]; then   
  t2w_file=$(find "$a_ses" -name "*T2w*.nii.gz" | head -n 1)
  if [ -n "$t2w_file" ]; then
    cp ${t2w_file} ${fprep_t2w}
  fi
fi

# Copy T1w in nice way... 
if [ ! -f "$fprep_t1w" ]; then   
  # Now copy T1w in nice way 
  mri_convert --in_type mgz --out_type nii ${deriv_dir}/freesurfer/sub-${sub}/mri/rawavg.mgz ${fprep_t1w}
fi
# Copy geometry
# fslcpgeom ${fprep_t2w} ${fprep_t1w}

# ******************** RUN FMRIPREP ***************************
fprep_ver=$bids_dir/code/fmriprep-latest.sif
# fprep_ver=$bids_dir/code/fmriprep-24.0.0.sif
# fprep_ver=$bids_dir/code/fmriprep-20.2.7.sif
# NEWER FMRIPREP
singularity run --cleanenv \
  -B $bids_dir:/data \
  -B $fprep_out:/out \
  -B $deriv_dir/freesurfer:/fs \
  -B $bids_dir/code/license.txt:/license.txt \
  -B $wf_dir:/wf \
  $fprep_ver \
  /data /out participant \
  --participant-label $sub \
  --fs-license-file /license.txt \
  --fs-subjects-dir /fs \
  --output-spaces T1w fsnative fsaverage func \
  --bold2anat-init t2w \
  --verbose \
  --md-only-boilerplate --stop-on-first-crash --nthreads 8 \
  --work-dir /wf \
  --verbose \
  --omp-nthreads 8 \
  --bold2anat-dof 12 \
  --skip-bids-validation  \
  --bids-filter-file /data/code/vdncsf_preproc/STEP_BY_STEP/N_bids_filter_file.json