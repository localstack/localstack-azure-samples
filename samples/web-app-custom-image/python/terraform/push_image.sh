#!/bin/bash

LOCAL_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"
FULL_IMAGE="${ACR_LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG}"

echo "Logging into Azure Container Registry [$ACR_NAME]..."
az acr login --name "$ACR_NAME" --only-show-errors

if [ $? -eq 0 ]; then
	echo "Logged into Azure Container Registry [$ACR_NAME] successfully."
else
	echo "Failed to log into Azure Container Registry [$ACR_NAME]."
	exit 1
fi

echo "Building custom Docker image [$LOCAL_IMAGE]..."
docker build -t "$LOCAL_IMAGE" ../src/

if [ $? -eq 0 ]; then
	echo "Docker image [$LOCAL_IMAGE] built successfully."
else
	echo "Failed to build Docker image [$LOCAL_IMAGE]."
	exit 1
fi

echo "Tagging Docker image [$LOCAL_IMAGE] as [$FULL_IMAGE]..."
docker tag "$LOCAL_IMAGE" "$FULL_IMAGE"

if [ $? -eq 0 ]; then
	echo "Docker image [$LOCAL_IMAGE] tagged as [$FULL_IMAGE] successfully."
else
	echo "Failed to tag Docker image [$LOCAL_IMAGE] as [$FULL_IMAGE]."
	exit 1
fi

echo "Pushing image [$FULL_IMAGE] to ACR..."
docker push "$FULL_IMAGE"

if [ $? -eq 0 ]; then
	echo "Docker image [$FULL_IMAGE] pushed to ACR successfully."
else
	echo "Failed to push Docker image [$FULL_IMAGE] to ACR."
	exit 1
fi