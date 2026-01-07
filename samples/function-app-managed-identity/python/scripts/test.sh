#!/bin/bash

# Variables
PREFIX='local'
SUFFIX='test'
FILE_PATH="input.txt"
INPUT_CONTAINER_NAME="input"
OUTPUT_CONTAINER_NAME="output"
STORAGE_ACCOUNT_NAME="${PREFIX}storage${SUFFIX}"
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENVIRONMENT=$(az account show --query environmentName --output tsv)

# Change the current directory to the script's directory
cd "$CURRENT_DIR" || exit

# Choose the appropriate CLI based on the environment
if [[ $ENVIRONMENT == "LocalStack" ]]; then
	echo "Using azlocal for LocalStack emulator environment."
	azlocal start_interception
else
	echo "Using standard az for AzureCloud environment."
fi

AZ="az"

# Generate a timestamp in the format YYYY-MM-DD-HH-MM-SS
TIMESTAMP=$(date +"%Y-%m-%d-%H-%M-%S")

# Extract the file name and extension
FILE_NAME=$(basename -- "$FILE_PATH")
FILE_BASE_NAME="${FILE_NAME%.*}"  # File name without extension
FILE_EXTENSION="${FILE_NAME##*.}" # File extension

# Construct the blob name with the timestamp
BLOB_NAME="${FILE_BASE_NAME}-${TIMESTAMP}.${FILE_EXTENSION}"

# Check whether the input container already exists
CONTAINER_EXISTS=$($AZ storage container exists \
	--name "$INPUT_CONTAINER_NAME" \
	--account-name "$STORAGE_ACCOUNT_NAME" \
	--auth-mode login | jq .exists)

if [ "$CONTAINER_EXISTS" == "true" ]; then
	echo "Container [$INPUT_CONTAINER_NAME] already exists."
else
	echo "Container [$INPUT_CONTAINER_NAME] does not exist."

	# Create the input container if it doesn't exist
	$AZ storage container create \
		--name $INPUT_CONTAINER_NAME \
		--account-name $STORAGE_ACCOUNT_NAME \
		--auth-mode login
fi

# Check whether the output container already exists
CONTAINER_EXISTS=$($AZ storage container exists \
	--name "$OUTPUT_CONTAINER_NAME" \
	--account-name "$STORAGE_ACCOUNT_NAME" \
	--auth-mode login | jq .exists)

if [ "$CONTAINER_EXISTS" == "true" ]; then
	echo "Container [$OUTPUT_CONTAINER_NAME] already exists."
else
	echo "Container [$OUTPUT_CONTAINER_NAME] does not exist."

	# Create the output container if it doesn't exist
	$AZ storage container create \
		--name $OUTPUT_CONTAINER_NAME \
		--account-name $STORAGE_ACCOUNT_NAME \
		--auth-mode login
fi

# Upload the file to the container
$AZ storage blob upload \
	--container-name $INPUT_CONTAINER_NAME \
	--file "$FILE_PATH" \
	--name "$BLOB_NAME" \
	--account-name $STORAGE_ACCOUNT_NAME \
	--auth-mode login 1>/dev/null

echo "[$BLOB_NAME] file uploaded successfully to the [$INPUT_CONTAINER_NAME] container."

# Verify the upload by checking if the blob exists in the input container
BLOB_EXISTS=$($AZ storage blob exists \
	--container-name "$INPUT_CONTAINER_NAME" \
	--name "$BLOB_NAME" \
	--account-name "$STORAGE_ACCOUNT_NAME" \
	--auth-mode login \
	--query "exists" \
	--output tsv)

if [ "$BLOB_EXISTS" == "true" ]; then
	echo "Blob [$BLOB_NAME] exists in container [$INPUT_CONTAINER_NAME]. Upload verified."
else
	echo "Blob [$BLOB_NAME] does not exist in container [$INPUT_CONTAINER_NAME]. Upload failed."
	exit 1
fi

# Loop n times to check whether the function app processed the input file and generated the result file in the output container
n=10
seconds=5

for ((i=1; i<=n; i++)); do
	echo "Checking for [$BLOB_NAME] file in the [$OUTPUT_CONTAINER_NAME] container (Attempt $i of $n)..."
	
	BLOB_EXISTS=$($AZ storage blob exists \
		--container-name "$OUTPUT_CONTAINER_NAME" \
		--name "$BLOB_NAME" \
		--account-name "$STORAGE_ACCOUNT_NAME" \
		--auth-mode login \
		--query "exists" \
		--output tsv)

	if [ "$BLOB_EXISTS" == "true" ]; then
		echo "Processed file [$BLOB_NAME] found in the [$OUTPUT_CONTAINER_NAME] container."
		exit 0
	fi

	echo "Processed file not found yet. Waiting for $seconds seconds before retrying..."
	sleep $seconds
done

echo "Processed file was not found in the [$OUTPUT_CONTAINER_NAME] container after $n attempts. Exiting with failure."
exit 1
