#!/bin/bash
#$ -S /bin/bash
#$ -cwd
#$ -j Y
#$ -V

# Set the freesurfer directory
PROJ_DIR=/data1/projects/dumoulinlab/Lab_members/Marcus/projects/csf/
DERIV_DIR=/data1/projects/dumoulinlab/Lab_members/Marcus/projects/csf/derivatives
export SUBJECTS_DIR=/data1/projects/dumoulinlab/Lab_members/Marcus/projects/csf/derivatives/freesurfer

# sub id is argument 1
sub_id=$1

# Get path to t1w image
t1w=$(find $DERIV_DIR/MrVista_copies/sub-$sub_id -name "anatomy_N3.nii.gz")
# Get path to orig.mgz image
fs_orig=$(find $SUBJECTS_DIR/sub-$sub_id -name "orig.mgz")

# Make a folder where we are going to put the transformations etc...
# if it doesn't exist already
if [ ! -d $DERIV_DIR/surface_transform_files/sub-$sub_id ]; then
    mkdir -p $DERIV_DIR/surface_transform_files/sub-$sub_id
fi
sub_surf_transform_dir=$DERIV_DIR/surface_transform_files/sub-$sub_id

# Run antsregistration to get transform from t1w to fsnative
echo "Running antsRegistration for sub-$sub_id"
# output is a .mat file
mat_trans_file="$sub_surf_transform_dir/sub-${sub_id}_from-T1w_to-fsnative_desc-genaff.mat"
# Check if it exists already, if so skip this stage
if [ -e "$mat_trans_file" ]; then
    echo "${mat_trans_file} already exists, skipping antsRegistration"
else
    echo "Running antsRegistration for sub-$sub_id"
    call_antsregistration $fs_orig $t1w $sub_surf_transform_dir/sub-${sub_id}_from-T1w_to-fsnative_desc-
fi

# Convert transform from .mat to .tfm
echo "Converting .mat transform to .tfm"
tfm_trans_file=$sub_surf_transform_dir/sub-${sub_id}_from-T1w_to-fsnative_desc-genaff.tfm
ConvertTransformFile 3 $mat_trans_file $tfm_trans_file

# Now loop through the runs and transform them into anatomy space, using identity matrix (i.e., not a proper transform)
# These files will be in T1w space, so we can use the antsregistration file to transform them to fsnative space
# if sub is 12112020, tasks=("csf" "prf")
# else tasks=("csf")
if [ "$sub_id" == "12112020" ]; then
    tasks=("csf" "prf")
else
    tasks=("csf")
fi
for task in "${tasks[@]}"; do
    # Find the runs
    # If sub is 12112020 and task is prf then naming is different
    if [ "$sub_id" == "12112020" ] && [ "$task" == "prf" ]; then
        runs=$(find $DERIV_DIR/MrVista_copies/sub-$sub_id/${task}_coreg_runs/ -name "CORRECT_SPACE_run_*_Coreg.nii.gz")
    else
        runs=$(find $DERIV_DIR/MrVista_copies/sub-$sub_id/${task}_coreg_runs/ -name "run_*_Coreg.nii.gz")
    fi    
    # Loop through runs
    for run in $runs; do
        # Get the run number (i.e., the number after "run_")
        run_num=$(echo $run | grep -oE 'run_[0-9]+' | grep -oE '[0-9]+')
        run_num=$(printf "%02d" $run_num)
        echo "Processing run $run_num"
        # call_antsapplytransforms from Jurjen Heijs linescanning toolbox
        # -> put functional into T1w space, using identity matrix
        run_in_t1w_space=$sub_surf_transform_dir/sub-${sub_id}_task-${task}_run-${run_num}_space-T1w_bold.nii.gz
        # Check if it exists already, if so skip this stage
        if [ -e "$run_in_t1w_space" ]; then
            echo "${run_in_t1w_space} already exists, skipping call_antsapplytransforms"
        else
            echo "Running call_antsapplytransforms for run $run_num"
            call_antsapplytransforms --verbose $t1w $run $run_in_t1w_space identity
        fi
        # Create accompanying LTA file
        # This is the same transformation, for every run but we need the ".lta" file to point to the correct source images (i.e., the functional in T1w space, which we just made)
        # the target is the fs orig.mgz file
        echo "Creating accompanying LTA file for run $run_num"
        lta_trans_file=$sub_surf_transform_dir/sub-${sub_id}_task-${task}_run-${run_num}_space-T1w_bold.lta
        lta_convert --initk $tfm_trans_file --outlta $lta_trans_file --src $run_in_t1w_space --trg $fs_orig

        # Now use mri_vol2surf to sample the functional data onto the fsaverage surface
        # Loop through hemispheres lh rh    
        hemis=("lh" "rh")
        for hemi in "${hemis[@]}"; do
            surf_ts_file=$sub_surf_transform_dir/sub-${sub_id}_task-${task}_run-${run_num}_hemi-${hemi}_fsnative.gii
            # Check if it exists already, if so skip this stage
            if [ -e "$surf_ts_file" ]; then
                echo "${surf_ts_file} already exists, skipping mri_vol2surf"
                continue
            fi
            mri_vol2surf --cortex --hemi $hemi --interp trilinear --o $surf_ts_file  --srcsubject sub-$sub_id --reg $lta_trans_file --projfrac-avg 0.000 1.000 0.200 --mov $run_in_t1w_space --trgsubject sub-$sub_id
        done        
    done
done