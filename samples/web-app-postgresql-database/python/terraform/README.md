# Terraform Deployment

This directory contains Terraform modules and a deployment script for provisioning Azure Database for PostgreSQL Flexible Server resources in LocalStack for Azure. Refer to the [Azure Database for PostgreSQL Flexible Server](../README.md) guide for details about the sample application.

## Prerequisites

Before deploying this solution, ensure you have the following tools installed:

- [LocalStack for Azure](https://azure.localstack.cloud/): Local Azure cloud emulator for development and testing
- [Visual Studio Code](https://code.visualstudio.com/): Code editor installed on one of the [supported platforms](https://code.visualstudio.com/docs/supporting/requirements#_platforms)
- [Terraform](https://developer.hashicorp.com/terraform/downloads): Infrastructure as Code tool for provisioning Azure resources
- [Python 3.12+](https://www.python.org/downloads/): Required for running the Flask web application
- [Docker](https://docs.docker.com/get-docker/): Container runtime required for LocalStack
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli): Azure command-line interface
- [azlocal CLI](https://azure.localstack.cloud/user-guides/sdks/az/): LocalStack Azure CLI wrapper
- [jq](https://jqlang.org/): JSON processor for scripting and parsing command outputs

### Installing azlocal CLI

The [deploy.sh](deploy.sh) Bash script uses the `azlocal` CLI instead of the standard Azure CLI to work with LocalStack. Install it using:

```bash
pip install azlocal
```

For more information, see [Get started with the az tool on LocalStack](https://azure.localstack.cloud/user-guides/sdks/az/).

## Architecture Overview

The [main.tf](main.tf) Terraform module creates the following Azure resources:

1. [Azure Resource Group](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/manage-resource-groups-cli): Logical container for all resources.
2. [Azure Database for PostgreSQL Flexible Server](https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/overview): Managed PostgreSQL database server with version 16.
3. [PostgreSQL Databases](https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/concepts-servers): Two databases (`sampledb` and `analyticsdb`).
4. [Firewall Rules](https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/concepts-firewall-rules): Three firewall rules (`allow-all`, `corporate-network`, `vpn-access`).

## Configuration

When using LocalStack for Azure, configure the `metadata_host` and `subscription_id` settings in the [Azure Provider for Terraform](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs) to ensure proper connectivity:


```hcl
provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }

  # Set the hostname of the Azure Metadata Service (for example management.azure.com)
  # used to obtain the Cloud Environment when using LocalStack's Azure emulator.
  # This allows the provider to correctly identify the environment and avoid making calls to the real Azure endpoints.
  metadata_host="localhost.localstack.cloud:4566"

  # Set the subscription ID to a dummy value when using LocalStack's Azure emulator.
  subscription_id = "00000000-0000-0000-0000-000000000000"
}
```

## Deployment

You can set up the Azure emulator by utilizing LocalStack for Azure Docker image. Before starting, ensure you have a valid `LOCALSTACK_AUTH_TOKEN` to access the Azure emulator. Refer to the [Auth Token guide](https://docs.localstack.cloud/getting-started/auth-token/) to obtain your Auth Token and specify it in the `LOCALSTACK_AUTH_TOKEN` environment variable. The Azure Docker image is available on the [LocalStack Docker Hub](https://hub.docker.com/r/localstack/localstack-azure-alpha). To pull the Azure Docker image, execute the following command:

```bash
docker pull localstack/localstack-azure-alpha
```

Start the LocalStack Azure emulator using the localstack CLI, execute the following command:

```bash
export LOCALSTACK_AUTH_TOKEN=<your_auth_token>
IMAGE_NAME=localstack/localstack-azure-alpha localstack start
```

Navigate to the `terraform` folder:

```bash
cd samples/postgresql-flexible-server/python/terraform
```

Make the script executable:

```bash
chmod +x deploy.sh
```

Run the deployment script:

```bash
./deploy.sh
```

## Validation

After deployment, you can use the `validate.sh` script to verify that all resources were created and configured correctly:

```bash
#!/bin/bash

# Variables
ENVIRONMENT=$(az account show --query environmentName --output tsv)

# Choose the appropriate CLI based on the environment
if [[ $ENVIRONMENT == "LocalStack" ]]; then
	echo "Using azlocal for LocalStack emulator environment."
	AZ="azlocal"
else
	echo "Using standard az for AzureCloud environment."
	AZ="az"
fi

# Get resource group name from Terraform output
RESOURCE_GROUP=$(terraform output -raw resource_group_name)

# Check resource group
$AZ group show \
--name "$RESOURCE_GROUP" \
--output table

# List resources
$AZ resource list \
--resource-group "$RESOURCE_GROUP" \
--output table

# Check PostgreSQL Flexible Server
SERVER_NAME=$(terraform output -raw server_name)
$AZ postgres flexible-server show \
--name "$SERVER_NAME" \
--resource-group "$RESOURCE_GROUP" \
--output table
```

## Cleanup

To destroy all created resources:

```bash
# Destroy Terraform-managed resources
terraform destroy -auto-approve

# Verify deletion
azlocal group list --output table
```

This will remove all Azure resources created by the Terraform deployment script.

## Related Documentation

- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest)
- [Terraform — azurerm_postgresql_flexible_server](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/postgresql_flexible_server)
- [LocalStack for Azure Documentation](https://azure.localstack.cloud/)
