# Azure CLI Deployment

This directory includes Bash scripts for deploying and testing the Container Apps Guestbook sample using the `lstk` CLI. Refer to the [Container Apps Blob Storage](../README.md) guide for details about the sample application.

## Prerequisites

- [LocalStack for Azure](https://docs.localstack.cloud/azure/): Local Azure cloud emulator for development and testing
- [Docker](https://docs.docker.com/get-docker/): Container runtime required for LocalStack
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli): Azure command-line interface
- [lstk CLI](https://docs.localstack.cloud/aws/developer-tools/running-localstack/lstk/): LocalStack command-line interface (proxies the Azure CLI via `lstk az`)

### Installing lstk CLI

```bash
brew install localstack/tap/lstk   # or: npm install -g @localstack/lstk
```

## Architecture Overview

The [deploy.sh](deploy.sh) script creates the following Azure resources using Azure CLI commands:

1. [Azure Storage Account](https://learn.microsoft.com/en-us/azure/storage/common/storage-account-overview): Provides blob storage for guestbook entries.
2. [Azure Container Registry](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-intro): Hosts the Docker container image for the Flask web app.
3. [Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/overview): Runs the containerized Flask application behind the managed environment's HTTP ingress, with secrets, revisions and scale rules.

For more information on the sample application, see [Container Apps Blob Storage](../README.md).

## Deployment

```bash
cd samples/container-apps-blob-storage/python
bash scripts/deploy.sh
```

## Validation

```bash
bash scripts/validate.sh
```

## Cleanup

```bash
bash scripts/cleanup.sh
```

## Related Documentation

- [Azure CLI Documentation](https://docs.microsoft.com/en-us/cli/azure/)
- [LocalStack for Azure Documentation](https://docs.localstack.cloud/azure/)
- [lstk CLI](https://docs.localstack.cloud/aws/developer-tools/running-localstack/lstk/)
- [lstk GitHub repository](https://github.com/localstack/lstk)
