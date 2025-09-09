#!/bin/bash
sub=ctrl01

bids_dir=/data1/projects/dumoulinlab/Lab_members/Marcus/projects/vdNCSF/BIDS_directory
deriv_dir=$bids_dir/derivatives

# Where we put the workflow
wf_dir=/data1/projects/dumoulinlab/Lab_members/Marcus/projects/vdNCSF/wf_fmriprep_new

# Outputs...
fprep_out="$deriv_dir/fprep_new"
rm -rf "$wf_dir"
rm -rf "$fprep_out"
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
# exit 1


# # ****** FIX EPIS ******
# le_path=${bids_dir}/sub-${sub}/ses-LE
# # re_path=${bids_dir}/sub-${sub}/ses-RE/func
# if [ -d "$le_path" ]; then 
#   # replace pepolar_01 with pepolar_01L (or other numbers)
#   # find $le_path -type f -name "*.json" -exec sed -i -E 's/(pepolar_[0-9]{2})(?!L)/\1L/g' {} +



#   # JUST DELETER IT? 
#   find $le_path -type f -name "*.json" -print0 | while IFS= read -r -d '' file; do
#       # Create a temporary file
#       temp_file=$(mktemp)

#       # Use jq to remove the key and save to the temp file
#       # Extract task and run from filename
#       basename=$(basename "$file")
#       if [[ $basename =~ ses-([a-zA-Z0-9]+)_task-([a-zA-Z0-9]+)_run-([0-9]+) ]]; then
#         ses="${BASH_REMATCH[1]}"
#         task="${BASH_REMATCH[2]}"
#         run="${BASH_REMATCH[3]}"
#         new_id="ses-${ses}_task-${task}_run-${run}"
#       else
#         new_id="unknown"
#       fi
#       echo $new_id
#       jq --arg new_id "$new_id" '.B0FieldIdentifier = $new_id' "$file" > "$temp_file"
#       mv "$temp_file" "$file"
#       # If 
#       if [[ "$file" == *_bold*.json ]]; then
#         jq 'del(.IntendedFor)' "$file" > "$temp_file"
#         mv "$temp_file" "$file"
#       fi
#       # jq 'del(.B0FieldSource)' "$file" > "$temp_file"
#       # jq 'del(.IntendedFor)' "$file" > "$temp_file"

#       # Replace the original file with the modified one
      

#       echo "Processed: $file"
#   done
# fi







# *********************** FIX PEPOLAR IN EPIs *****************
# le_path=${bids_dir}/sub-${sub}/ses-LE
# # re_path=${bids_dir}/sub-${sub}/ses-RE/func
# if [ -d "$le_path" ]; then 
#   # replace pepolar_01 with pepolar_01L (or other numbers)
#   # find $le_path -type f -name "*.json" -exec sed -i -E 's/(pepolar_[0-9]{2})(?!L)/\1L/g' {} +



#   # JUST DELETER IT? 
#   find $le_path -type f -name "*.json" -print0 | while IFS= read -r -d '' file; do
#       # Create a temporary file
#       temp_file=$(mktemp)

#       # Use jq to remove the key and save to the temp file
#       jq 'del(.B0FieldIdentifier)' "$file" > "$temp_file"
#       mv "$temp_file" "$file"

#       if [[ "$file" == *_bold*.json ]]; then
#         jq 'del(.IntendedFor)' "$file" > "$temp_file"
#         mv "$temp_file" "$file"
#       fi
#       # jq 'del(.B0FieldSource)' "$file" > "$temp_file"
#       # jq 'del(.IntendedFor)' "$file" > "$temp_file"

#       # Replace the original file with the modified one
      

#       echo "Processed: $file"
#   done
# fi
# exit 1
# if [ -d "$re_path" ]; then 
#   # replace pepolar_01 with pepolar_01L (or other numbers)
#   # find $re_path -type f -name "*.json" -exec sed -i -E 's/(pepolar_[0-9]{2})(?!R)/\1R/g' {} +

#   # JUST DELETER IT? 
#   find ${re_path}/ -type f -name "*.json" -print0 | while IFS= read -r -d '' file; do
#       # Create a temporary file
#       temp_file=$(mktemp)

#       # Use jq to remove the key and save to the temp file
#       jq 'del(.B0FieldIdentifier)' "$file" > "$temp_file"
#       jq 'del(.B0FieldSource)' "$file" > "$temp_file"
#       jq 'del(.IntendedFor)' "$file" > "$temp_file"
#       # Replace the original file with the modified one
#       mv "$temp_file" "$file"

#       echo "Processed: $file"
#   done  
# fi





# ******************** RUN FMRIPREP ***************************
# fprep_ver=$bids_dir/code/fmriprep-latest.sif
fprep_ver=$bids_dir/code/fmriprep-24.0.0.sif
# fprep_ver=/packages/singularity_containers/containers_bids-fmriprep--20.2.5.simg
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
  --skip-bids-validation  \
  
  # --bids-filter-file /data/code/vdncsf_preproc/vd_fprep/F_fmriprep_config.json 

#
#   --force-bbr
# /data1/projects/dumoulinlab/Lab_members/Marcus/projects/vdNCSF/BIDS_directory/code/fmriprep-latest.sif \
# /packages/singularity_containers/containers_bids-fmriprep--20.2.5.simg \  

#   --nthreads 8 \
  
#   --mem_mb 64000 \


# singularity run --cleanenv -B /data1/projects/dumoulinlab/Lab_members/Marcus:/data1/projects/dumoulinlab/Lab_members/Marcus /packages/singularity_containers/containers_bids-fmriprep--20.2.5.simg /data1/projects/dumoulinlab/Lab_members/Marcus/projects/vdNCSF/BIDS_directory /data1/projects/dumoulinlab/Lab_members/Marcus/projects/vdNCSF/BIDS_directory/derivatives participant --participant-label ctrl04 --skip-bids-validation --md-only-boilerplate --fs-license-file /data1/projects/dumoulinlab/Lab_members/Marcus/projects/vdNCSF/BIDS_directory/code/license.txt --output-spaces fsnative func --fs-subjects-dir /data1/projects/dumoulinlab/Lab_members/Marcus/projects/vdNCSF/BIDS_directory/derivatives/freesurfer --work-dir /data1/projects/dumoulinlab/Lab_members/Marcus/projects/logs/fmriprep/vdNCSF/BIDS_directory --stop-on-first-crash      --bold2t1w-init register  --nthreads 1