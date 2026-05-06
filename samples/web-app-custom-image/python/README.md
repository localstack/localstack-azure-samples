# Azure Web App With Custom Docker Image

This sample demonstrates a Python Flask web application hosted on an Azure Web App using a custom Docker image. The deployment builds the image from the local `src/Dockerfile`, creates an Azure Container Registry resource, and configures a Linux Web App to run the custom image in the LocalStack Azure emulator.

## Architecture

The sample creates the following Azure resources:

1. **Azure Resource Group**: Logical container for all resources in the sample.
2. **Azure Container Registry**: Stores the custom Docker image metadata and credentials.
3. **Azure App Service Plan**: Linux plan used by the Web App.
4. **Azure Web App**: Runs the Flask application from the custom image.

## Prerequisites

- Docker
- Azure CLI
- azlocal CLI
- jq
- LocalStack for Azure

## Deploy

Start LocalStack for Azure and configure Azure CLI interception as described in the repository root README. Then run:

```bash
cd samples/web-app-custom-image/python
bash scripts/deploy.sh
```

The script builds the Docker image from `src/`, creates the App Service resources, and configures the Web App to use the custom image.

## Validate

```bash
bash scripts/validate.sh
```

## Invoke The App

```bash
bash scripts/call-web-app.sh
```

The app exposes:

- `/` for the HTML page
- `/api/status` for a JSON health response

## Local Docker Run

You can run the same image directly with Docker:

```bash
cd src
docker build -t vacation-planner-webapp:v1 .
docker run --rm -p 8080:80 vacation-planner-webapp:v1
curl http://127.0.0.1:8080/api/status
```
