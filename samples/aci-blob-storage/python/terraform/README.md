# Terraform Deployment

This directory contains Terraform modules and a deployment script for provisioning Azure services in LocalStack for Azure. Refer to the [ACI Blob Storage](../README.md) guide for details about the sample application.

## Prerequisites

- [LocalStack for Azure](https://azure.localstack.cloud/): Local Azure cloud emulator for development and testing
- [Terraform](https://developer.hashicorp.com/terraform/downloads): Infrastructure as Code tool
- [Docker](https://docs.docker.com/get-docker/): Container runtime required for LocalStack
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli): Azure command-line interface
- [azlocal CLI](https://azure.localstack.cloud/user-guides/sdks/az/): LocalStack Azure CLI wrapper

### Installing azlocal CLI

```bash
pip install azlocal
```

## Architecture Overview

The [deploy.sh](deploy.sh) script first builds and pushes the Docker image to a pre-created ACR, then the [main.tf](main.tf) Terraform module creates the following Azure resources:

1. [Azure Storage Account](https://learn.microsoft.com/en-us/azure/storage/common/storage-account-overview): Provides blob storage for vacation activity data.
2. [Azure Container Instances](https://learn.microsoft.com/en-us/azure/container-instances/container-instances-overview): Runs the containerized Flask application with public IP and DNS label.

> **Note:** Key Vault is not included in the Terraform deployment as the Azure Terraform provider does not yet support LocalStack's Key Vault URI format. The storage connection string is passed directly to ACI as a secure environment variable.

For more information on the sample application, see [ACI Blob Storage](../README.md).

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
- [LocalStack for Azure Documentation](https://azure.localstack.cloud/)
