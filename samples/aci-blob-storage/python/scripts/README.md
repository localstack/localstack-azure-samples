# Azure CLI Deployment

This directory includes Bash scripts for deploying and testing the ACI Vacation Planner sample using the `azlocal` CLI. Refer to the [ACI Blob Storage](../README.md) guide for details about the sample application.

## Prerequisites

- [LocalStack for Azure](https://docs.localstack.cloud/azure/): Local Azure cloud emulator for development and testing
- [Docker](https://docs.docker.com/get-docker/): Container runtime required for LocalStack
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli): Azure command-line interface
- [azlocal CLI](https://azure.localstack.cloud/user-guides/sdks/az/): LocalStack Azure CLI wrapper

### Installing azlocal CLI

```bash
pip install azlocal
```

## Architecture Overview

The [deploy.sh](deploy.sh) script creates the following Azure resources using Azure CLI commands:

1. [Azure Storage Account](https://learn.microsoft.com/en-us/azure/storage/common/storage-account-overview): Provides blob storage for vacation activity data.
2. [Azure Key Vault](https://learn.microsoft.com/en-us/azure/key-vault/general/overview): Stores the storage connection string as a secret.
3. [Azure Container Registry](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-intro): Hosts the Docker container image for the Flask web app.
4. [Azure Container Instances](https://learn.microsoft.com/en-us/azure/container-instances/container-instances-overview): Runs the containerized Flask application with public IP and DNS label.

For more information on the sample application, see [ACI Blob Storage](../README.md).

## Deployment

```bash
cd samples/aci-blob-storage/python
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
