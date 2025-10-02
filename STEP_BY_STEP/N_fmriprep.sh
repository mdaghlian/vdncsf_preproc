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
wf_dir=/data1/projects/dumoulinlab/Lab_members/Marcus/projects/vdNCSF/wf_fmriprep

# Outputs...
fprep_out="$deriv_dir"
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
else
  echo "$fprep_ses already exists - removing contents"
  rm -rf $fprep_ses/*
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

# DEOBLIQUE STAGE
#!/bin/bash

# ==============================================================================
# AFNI Deoblique Script for Anatomical Data
# This script processes all .nii.gz files within a specified directory,
# deobliquing them using AFNI's 3dWarp, and renames the original
# files to prevent overwriting.
# ==============================================================================

# Define the directories to process.
# Add or remove directory names from this list as needed.
SUB_DIRS=("ses-fprep") # "ses-LE" "ses-RE")

# Define the file suffix for the original, non-deobliqued files.
NONDEOBLIQUE_SUFFIX="_nondeob.nii.gz"

# Loop through each specified directory.
for SES in "${SUB_DIRS[@]}"
do
    echo "=================================================="
    echo "Processing directory: $THIS_SUB_DIR"
    echo "=================================================="
    for FTYPE in "anat" "func" "fmap"
    do
        THIS_SUB_DIR="$bids_dir/sub-$sub/$SES/$FTYPE"
        # Check if the specified directory exists.
        if [ ! -d "$THIS_SUB_DIR" ]; then
            echo "Error: Directory '$THIS_SUB_DIR' not found. Skipping."
            continue
        fi

        # Loop through all files in the current directory ending with .nii.gz.
        for f in "$THIS_SUB_DIR"/*.nii.gz
        do
            # Check if the file is a regular file and not a directory or if the glob finds nothing.
            if [ -f "$f" ]; then
                echo "Processing file: $f"

                # Extract the base filename without the .nii.gz extension.
                BASE_NAME=$(basename "$f" .nii.gz)
                
                # Define the new full path for the original (non-deobliqued) file.
                ORIGINAL_RENAMED="$THIS_SUB_DIR/${BASE_NAME}${NONDEOBLIQUE_SUFFIX}"

                # Check if a previously deobliqued version of this file already exists.
                if [[ "$(basename "$f")" == *"$NONDEOBLIQUE_SUFFIX" ]] || [ -f "$ORIGINAL_RENAMED" ]; then
                    echo "  Skipping file as it appears to have been processed already."
                    continue
                fi
                
                # Define the full path for the output deobliqued file.
                DEOBLIQUED_FILE="$f"
                
                # Rename the original file first to avoid any accidental overwriting issues.
                mv "$f" "$ORIGINAL_RENAMED"
                echo "  Original file renamed to $(basename "$ORIGINAL_RENAMED")"

                # Deoblique the renamed original file and save the output with the original name.
                3dWarp -deoblique -prefix "$DEOBLIQUED_FILE" "$ORIGINAL_RENAMED" &> "$THIS_SUB_DIR/log_${BASE_NAME}.txt"

                # Check the exit status of the 3dWarp command.
                if [ $? -eq 0 ]; then
                    echo "  Successfully deobliqued to $(basename "$DEOBLIQUED_FILE")"
                else
                    echo "  Error: 3dWarp failed for $(basename "$f"). Check the log file for details: log_${BASE_NAME}.txt"
                    # Move the original file back in case of an error to prevent data loss.
                    mv "$ORIGINAL_RENAMED" "$f"
                fi
            fi
        done
    done
done
echo "Script finished."


# ******************** RUN FMRIPREP ***************************
# fprep_ver=$bids_dir/code/fmriprep-latest.sif
# fprep_ver=$bids_dir/code/fmriprep-24.0.0.sif
fprep_ver=$bids_dir/code/fmriprep-20.2.7.sif
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
  --bold2t1w-init register --bold2t1w-dof 12 --use-syn-sdc \
  --md-only-boilerplate --stop-on-first-crash --nthreads 8 \
  --work-dir /wf \
  --verbose \
  --omp-nthreads 8 \
  --skip-bids-validation  \
  --bids-filter-file /data/code/vdncsf_preproc/STEP_BY_STEP/N_bids_filter_file.json  


# # NEWER FMRIPREP
# singularity run --cleanenv \
#   -B $bids_dir:/data \
#   -B $fprep_out:/out \
#   -B $deriv_dir/freesurfer:/fs \
#   -B $bids_dir/code/license.txt:/license.txt \
#   -B $wf_dir:/wf \
#   $fprep_ver \
#   /data /out participant \
#   --participant-label $sub \
#   --fs-license-file /license.txt \
#   --fs-subjects-dir /fs \
#   --output-spaces T1w fsnative fsaverage func \
#   --bold2anat-init t2w \
#   --verbose \
#   --md-only-boilerplate --stop-on-first-crash --nthreads 8 \
#   --work-dir /wf \
#   --verbose \
#   --omp-nthreads 8 \
#   --bold2anat-dof 12 \
#   --skip-bids-validation  \
#   --bids-filter-file /data/code/vdncsf_preproc/vd_fprep/bids_filter_file.json --level minimal