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

When using LocalStack for Azure, configure the `metadata_host` and `subscription_id` settings in the [Azure Provider for Terraform](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs):

```hcl
provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
  metadata_host="localhost.localstack.cloud:4566"
  subscription_id = "00000000-0000-0000-0000-000000000000"
}
```

## Deployment

```bash
cd samples/container-apps-blob-storage/python
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
