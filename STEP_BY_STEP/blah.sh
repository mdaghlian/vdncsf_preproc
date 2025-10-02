#!/bin/bash

# ==============================================================================
# AFNI Deoblique Script for Anatomical Data
# This script processes all .nii.gz files within a specified directory,
# deobliquing them using AFNI's 3dWarp, and renames the original
# files to prevent overwriting.
# ==============================================================================

# Define the directories to process.
# Add or remove directory names from this list as needed.
SUB_DIRS=("ses-fprep" "ses-LE" "ses-RE")

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
        THIS_SUB_DIR="$fprep_ses/../$SES/$FTYPE"
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
