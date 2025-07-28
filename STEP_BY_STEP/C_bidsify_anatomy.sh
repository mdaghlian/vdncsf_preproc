#!/bin/bash
# Initialize variables
SUB_VAR=""
SES_VAR="ses-A"

# Parse command-line arguments
# The colon after 's' and 'n' indicates that these options require an argument.
while getopts "s:n:" opt; do
  case $opt in
    s)
      SUB_VAR="sub-$OPTARG"
      ;;
    n)
      SES_VAR="ses-$OPTARG"
      ;;
  esac
done

ANAT_IN_PATH=${DIR_DATA_SOURCE}/${SUB_VAR}/${SES_VAR}
ANAT_OUT_PATH=${DIR_DATA_HOME}/${SUB_VAR}/${SES_VAR}/anat
if [ ! -d "$ANAT_OUT_PATH" ]; then
  echo "Directory '$ANAT_OUT_PATH' does not exist. Creating it..."
  mkdir -p "$ANAT_OUT_PATH"
else
  echo "Directory '$ANAT_OUT_PATH' already exists."
fi
# Use call_dcm2niix -> force to work with dcm
call_dcm2niix -i ${ANAT_IN_PATH} --force-dcm

# This script renames files with the pattern *_mp2rage* based on specific rules.
# It iterates through files, extracts parts of their names, and constructs new names.

echo "Starting file renaming process..."

# Find files matching the pattern *_mp2rage* recursively in the current directory.
# Using 'find' ensures we can handle files in subdirectories as well.
find ${ANAT_IN_PATH} -type f -name "*mp2rage*" | while read -r filepath; do
    if [[ "$filepath" =~ \.PAR$ ]] || [[ "$filepath" =~ \.REC$ ]]; then
        echo "Skipping $filepath"
        continue # Skip to the next iteration of the loop
    fi    
    # Get the base filename (e.g., "subjectA_mp2rage_t1.nii.gz")
    filename=$(basename "$filepath")
    # Get the directory path (e.g., "./data/raw")
    dirname=$(dirname "$filepath")

    echo "Processing file: $filename"

    # 1. Extract everything up to *_mp2rage
    # Using bash parameter expansion to get the part of the string before the first occurrence of "_mp2rage".
    prefix="${filename%%_mp2rage*}"

    # Check if a prefix was found. If not, skip this file to avoid errors.
    if [ -z "$prefix" ]; then
        echo "  Warning: Could not determine prefix for '$filename'. Skipping."
        continue
    fi

    # Initialize variables for the new parts of the filename
    inv_part=""
    part_suffix=""

    # 2. Determine "inv" part: "1" if ends in t1*, "2" if ends in t2*
    # We use case-insensitive matching for robustness.
    # Updated regex to correctly match 't1' or 't2' followed by any digits before the extension,
    # now including .json as a possible extension.
    if [[ "$filename" =~ t1[0-9]*(\.nii\.gz|\.nii|\.json)?$ ]]; then
        inv_part="1"
    elif [[ "$filename" =~ t2[0-9]*(\.nii\.gz|\.nii|\.json)?$ ]]; then
        inv_part="2"
    else
        echo "  Warning: Could not determine 'inv' part (t1/t2) for '$filename'. Skipping."
        continue # Skip if neither t1 nor t2 pattern is found at the end
    fi

    # 3. Determine "part" suffix: "_part-mag" if "_ph_" or "phase" not in filename, else "_part-phase"
    # Added check for "phase" as inspired by your snippet for more robustness.
    if [[ "$filename" == *"_ph_"* || "$filename" == *"phase"* ]]; then
        part_suffix="_part-phase"
    else
        part_suffix="_part-mag"
    fi

    # Construct the new filename
    # We need to preserve the original file extension (e.g., .nii.gz, .nii, .json)
    # Extract the extension from the original filename
    extension="${filename##*.}"
    # If the extension is just "gz", it's likely part of ".nii.gz"
    if [ "$extension" == "gz" ]; then
        # Re-evaluate to get ".nii.gz"
        extension="${filename##*.nii}"
        extension=".nii${extension}"
    fi

    # Ensure the extension starts with a dot, or is empty if no extension
    if [[ -n "$extension" && "${extension:0:1}" != "." ]]; then
        extension=".$extension"
    fi

    # Construct the new filename without the original extension first
    new_filename_base="${prefix}_acq-MP2RAGE_inv-${inv_part}${part_suffix}"
    # Add the extension back
    new_filename="${new_filename_base}${extension}"

    # Construct the full new path
    new_filepath="${dirname}/${new_filename}"
    # Check if the new filename is different from the original to avoid unnecessary renames
    if [ "$filename" != "$new_filename" ]; then
        echo "  Renaming '$filename' to '$new_filename'"
        mv "$filepath" "$new_filepath"
        cp "$new_filepath" ${ANAT_OUT_PATH}/
    else
        echo "  No change needed for '$filename'."
    fi

    # 
done



find ${ANAT_IN_PATH} -type f -name "*T2w*" | while read -r filepath; do
    if [[ "$filepath" =~ \.PAR$ ]] || [[ "$filepath" =~ \.REC$ ]]; then
        echo "Skipping $filepath"
        continue # Skip to the next iteration of the loop
    fi    
    # Get the base filename (e.g., "subjectA_mp2rage_t1.nii.gz")
    filename=$(basename "$filepath")
    # Get the directory path (e.g., "./data/raw")
    dirname=$(dirname "$filepath")

    # Construct the full new path
    filepath="${dirname}/${filename}"
    # Check if the new filename is different from the original to avoid unnecessary renames
    cp "$filepath" ${ANAT_OUT_PATH}/
    # 
done



echo "File renaming process completed."
