# Bicep Deployment

This directory contains the Bicep template and a deployment script for provisioning Azure services in LocalStack for Azure. Refer to the [Container Apps Blob Storage](../README.md) guide for details about the sample application.

## Prerequisites

- [LocalStack for Azure](https://docs.localstack.cloud/azure/): Local Azure cloud emulator for development and testing
- [Docker](https://docs.docker.com/get-docker/): Container runtime required for LocalStack
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli): Azure command-line interface
- [Bicep extension](https://marketplace.visualstudio.com/items?itemName=ms-azuretools.vscode-bicep): VS Code extension for Bicep language support
- [lstk CLI](https://docs.localstack.cloud/aws/developer-tools/running-localstack/lstk/): LocalStack command-line interface (proxies the Azure CLI via `lstk az`)
- [jq](https://jqlang.org/): JSON processor for scripting

### Installing lstk CLI

```bash
brew install localstack/tap/lstk   # or: npm install -g @localstack/lstk
```

## Architecture Overview

The [deploy.sh](deploy.sh) script first builds and pushes the Docker image to ACR, then the [main.bicep](main.bicep) template creates the following Azure resources:

1. [Azure Storage Account](https://learn.microsoft.com/en-us/azure/storage/common/storage-account-overview): Provides blob storage for guestbook entries.
2. [Azure Container Registry](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-intro): Hosts the Docker container image.
3. [Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/overview): A managed environment and a container app with secrets, external HTTP ingress, and an HTTP scale rule.

The `Microsoft.App` resources pin api-version `2025-07-01`, the version the az CLI itself uses.

For more information on the sample application, see [Container Apps Blob Storage](../README.md).

## Configuration

Update the `main.bicepparam` file with your specific values:

```bicep
using 'main.bicep'

param prefix = 'local'
param suffix = 'test'
param imageName = 'guestbook'
param imageTag = 'v1'
```

## Deployment

```bash
cd samples/container-apps-blob-storage/python
bash bicep/deploy.sh
```

## Cleanup

```bash
bash scripts/cleanup.sh
```

## Related Documentation

- [Azure Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Bicep Language Reference](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/bicep-functions)
- [LocalStack for Azure Documentation](https://docs.localstack.cloud/azure/)
- [lstk CLI](https://docs.localstack.cloud/aws/developer-tools/running-localstack/lstk/)
- [lstk GitHub repository](https://github.com/localstack/lstk)
