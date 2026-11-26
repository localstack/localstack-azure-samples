# Terraform Deployment

This directory contains Terraform modules and a deployment script for provisioning Azure services in LocalStack for Azure. Refer to the [ACI Blob Storage](../README.md) guide for details about the sample application.

## Prerequisites

- [LocalStack for Azure](https://docs.localstack.cloud/azure/): Local Azure cloud emulator for development and testing
- [Terraform](https://developer.hashicorp.com/terraform/downloads): Infrastructure as Code tool
- [Docker](https://docs.docker.com/get-docker/): Container runtime required for LocalStack
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli): Azure command-line interface
- [lstk CLI](https://docs.localstack.cloud/aws/developer-tools/running-localstack/lstk/): LocalStack command-line interface (proxies the Azure CLI via `lstk az`)

### Installing lstk CLI

```bash
brew install localstack/tap/lstk   # or: npm install -g @localstack/lstk
```

## Architecture Overview

The [deploy.sh](deploy.sh) script first builds and pushes the Docker image to a pre-created ACR, then the [main.tf](main.tf) Terraform module creates the following Azure resources:

1. [Azure Storage Account](https://learn.microsoft.com/en-us/azure/storage/common/storage-account-overview): Provides blob storage for vacation activity data.
2. [Azure Container Instances](https://learn.microsoft.com/en-us/azure/container-instances/container-instances-overview): Runs the containerized Flask application with public IP and DNS label.

> [!NOTE]
> Key Vault is not included in the Terraform deployment as the Azure Terraform provider does not yet support LocalStack's Key Vault URI format. The storage connection string is passed directly to ACI as a secure environment variable.

For more information on the sample application, see [ACI Blob Storage](../README.md).

## Configuration

`providers.tf` hardcodes no endpoint and no subscription. `deploy.sh` exports the variables the [Azure Provider for Terraform](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs) reads natively, so the same files run unmodified against the LocalStack emulator and against Azure:

| Variable                               | Exported when                         | Value                                                     |
| -------------------------------------- | ------------------------------------- | --------------------------------------------------------- |
| `ARM_SUBSCRIPTION_ID`, `ARM_TENANT_ID` | always                                | `az account show`                                         |
| `ARM_METADATA_HOSTNAME`                | the active `az cloud` is `LocalStack` | host of `az cloud show --query endpoints.resourceManager` |

The provider discovers every endpoint of the emulator from `ARM_METADATA_HOSTNAME`, and authenticates with the Azure CLI session on both targets. Against Azure, `deploy.sh` unsets `ARM_METADATA_HOSTNAME`, so the provider uses the endpoints of the public cloud. Running `terraform` directly, rather than through `deploy.sh`, needs these variables exported.

The key vault uses the Azure RBAC permission model, and Terraform writes the storage connection string secret through its data plane: the configuration grants the principal that runs it the Key Vault Secrets Officer role on the vault, and waits `rbac_propagation_delay` (60 seconds by default) for the role to apply on Azure; `deploy.sh` passes `0s` on the emulator.

`deploy.sh` creates the resource group and the container registry before Terraform runs, so that it can push the image, and imports the resource group into the Terraform state on the first run. It creates each of them only when it does not exist yet, so the script can run again.

## Deployment

```bash
cd samples/aci-blob-storage/python
bash terraform/deploy.sh
```

## Cleanup

```bash
bash scripts/cleanup.sh
```

To also clean up Terraform state:

```bash
cd terraform
rm -rf .terraform terraform.tfstate terraform.tfstate.backup .terraform.lock.hcl tfplan
```

## Related Documentation

- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest)
- [LocalStack for Azure Documentation](https://docs.localstack.cloud/azure/)
- [lstk CLI](https://docs.localstack.cloud/aws/developer-tools/running-localstack/lstk/)
- [lstk GitHub repository](https://github.com/localstack/lstk)
