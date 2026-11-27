# Terraform Deployment

This directory contains Terraform modules and a deployment script for provisioning Azure services in LocalStack for Azure. Refer to the [Container Apps Blob Storage](../README.md) guide for details about the sample application.

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

1. [Azure Storage Account](https://learn.microsoft.com/en-us/azure/storage/common/storage-account-overview): Provides blob storage for guestbook entries.
2. [Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/overview): A managed environment ([azurerm_container_app_environment](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/container_app_environment)) and a container app ([azurerm_container_app](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/container_app)) with secrets, external HTTP ingress, and an HTTP scale rule.

For more information on the sample application, see [Container Apps Blob Storage](../README.md).

## Configuration

`providers.tf` hardcodes no endpoint and no subscription. `deploy.sh` exports the variables the [Azure Provider for Terraform](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs) reads natively, so the same files run unmodified against the LocalStack emulator and against Azure:

| Variable                               | Exported when                         | Value                                                     |
| -------------------------------------- | ------------------------------------- | --------------------------------------------------------- |
| `ARM_SUBSCRIPTION_ID`, `ARM_TENANT_ID` | always                                | `az account show`                                         |
| `ARM_METADATA_HOSTNAME`                | the active `az cloud` is `LocalStack` | host of `az cloud show --query endpoints.resourceManager` |

The provider discovers every endpoint of the emulator from `ARM_METADATA_HOSTNAME`, and authenticates with the Azure CLI session on both targets. Against Azure, `deploy.sh` unsets `ARM_METADATA_HOSTNAME`, so the provider uses the endpoints of the public cloud. Running `terraform` directly, rather than through `deploy.sh`, needs these variables exported.

`deploy.sh` creates the resource group and the container registry before Terraform runs, so that it can push the image, and imports the resource group into the Terraform state on the first run. It creates each of them only when it does not exist yet, so the script can run again.

## Deployment

```bash
cd samples/container-apps-blob-storage/python
bash terraform/deploy.sh
```

To have the app reach Blob Storage with a managed identity instead of the connection string secret, set `MANAGED_IDENTITY_TYPE` (`SystemAssigned` or `UserAssigned`). The module then creates the identity (user-assigned only), grants it the `Storage Blob Data Contributor` role on the storage account, and passes the app the blob endpoint, plus `AZURE_CLIENT_ID` for a user-assigned identity:

```bash
MANAGED_IDENTITY_TYPE=UserAssigned bash terraform/deploy.sh
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
