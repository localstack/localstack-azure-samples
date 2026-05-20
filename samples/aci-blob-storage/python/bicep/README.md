# Bicep Deployment

This directory contains the Bicep template and a deployment script for provisioning Azure services in LocalStack for Azure. Refer to the [ACI Blob Storage](../README.md) guide for details about the sample application.

## Prerequisites

- [LocalStack for Azure](https://docs.localstack.cloud/azure/): Local Azure cloud emulator for development and testing
- [Docker](https://docs.docker.com/get-docker/): Container runtime required for LocalStack
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli): Azure command-line interface
- [Bicep extension](https://marketplace.visualstudio.com/items?itemName=ms-azuretools.vscode-bicep): VS Code extension for Bicep language support
- [azlocal CLI](https://azure.localstack.cloud/user-guides/sdks/az/): LocalStack Azure CLI wrapper
- [jq](https://jqlang.org/): JSON processor for scripting

### Installing azlocal CLI

```bash
pip install azlocal
```

## Architecture Overview

The [deploy.sh](deploy.sh) script first builds and pushes the Docker image to ACR, then the [main.bicep](main.bicep) template creates the following Azure resources:

1. [Azure Storage Account](https://learn.microsoft.com/en-us/azure/storage/common/storage-account-overview): Provides blob storage for vacation activity data.
2. [Azure Key Vault](https://learn.microsoft.com/en-us/azure/key-vault/general/overview): Stores the storage connection string as a secret.
3. [Azure Container Registry](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-intro): Hosts the Docker container image.
4. [Azure Container Instances](https://learn.microsoft.com/en-us/azure/container-instances/container-instances-overview): Runs the containerized Flask application.

For more information on the sample application, see [ACI Blob Storage](../README.md).

## Configuration

Update the `main.bicepparam` file with your specific values:

```bicep
using 'main.bicep'

param prefix = 'local'
param suffix = 'test'
param imageName = 'vacation-planner'
param imageTag = 'v1'
param loginName = 'paolo'
```

## Deployment

```bash
cd samples/aci-blob-storage/python
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
