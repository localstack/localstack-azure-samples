# Web App Custom Image Scripts

These scripts deploy and validate a Python Flask application running on Azure Web App for Containers.

## Deploy

```bash
bash scripts/deploy.sh
```

The deployment script creates:

- Resource group
- Azure Container Registry with admin credentials enabled
- Custom Docker image built from `src/Dockerfile`
- Linux App Service Plan
- Web App configured to use the custom image

If pushing to the emulated registry is unavailable in the current LocalStack environment, the script falls back to the local Docker image tag.

## Validate

```bash
bash scripts/validate.sh
```

## Call The Web App

```bash
bash scripts/call-web-app.sh
```

The call script first uses the LocalStack proxy endpoint and then, when available, calls the Docker host port mapped to the emulated Web App container.
