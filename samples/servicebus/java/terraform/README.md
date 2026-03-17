# Terraform Deployment

This directory contains Terraform modules and a deployment script for provisioning Azure services in LocalStack for Azure. For further details about the sample application, refer to the [Azure Service Bus with Spring Boot](../README.md).

## Prerequisites

Before deploying this solution, ensure you have the following tools installed:

- [LocalStack for Azure](https://azure.localstack.cloud/): Local Azure cloud emulator for development and testing
- [Visual Studio Code](https://code.visualstudio.com/): Code editor installed on one of the [supported platforms](https://code.visualstudio.com/docs/supporting/requirements#_platforms)
- [Terraform](https://developer.hashicorp.com/terraform/downloads): Infrastructure as Code tool for provisioning Azure resources
- [Docker](https://docs.docker.com/get-docker/): Container runtime required for LocalStack
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli): Azure command-line interface
- [Azlocal CLI](https://azure.localstack.cloud/user-guides/sdks/az/): LocalStack Azure CLI wrapper
- [Java 21+](https://learn.microsoft.com/en-us/java/openjdk/download): Java runtime for compiling and running the sample application
- [Maven 3.8+](https://maven.apache.org/download.cgi): Build tool for managing Java project dependencies and compilation
- [jq](https://jqlang.org/): JSON processor for scripting and parsing command outputs

### Installing azlocal CLI

The [deploy.sh](deploy.sh) Bash script uses the `azlocal` CLI instead of the standard Azure CLI to work with LocalStack. Install it using:

```bash
pip install azlocal
```

For more information, see [Get started with the az tool on LocalStack](https://azure.localstack.cloud/user-guides/sdks/az/).

## Architecture Overview

The Terraform modules create the following Azure resources:

1. [Azure Resource Group](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/manage-resource-groups-cli): A logical container scoping all resources in this sample.
2. [Azure Service Bus Namespace](https://learn.microsoft.com/en-us/azure/service-bus-messaging/service-bus-messaging-overview): The messaging namespace that hosts the queue used by the application.
3. [Azure Service Bus Queue](https://learn.microsoft.com/en-us/azure/service-bus-messaging/service-bus-queues-topics-subscriptions#queues): The `myqueue` queue used to send and receive messages.

The Spring Boot sample application connects to the Service Bus namespace, sends a test message to the sample queue, receives it back, and exits. For more information on the sample application, see [Azure Service Bus with Spring Boot](../README.md).

## Provisioning Scripts

You can use the [deploy.sh](deploy.sh) script to automate the deployment of all Azure resources and the sample application in a single step, streamlining setup and reducing manual configuration. The script executes the following steps:

- Cleans up any previous Terraform state and plan files to ensure a fresh deployment.
- Initializes the Terraform working directory and downloads required plugins.
- Creates and validates a Terraform execution plan for the Azure infrastructure.
- Applies the Terraform plan to provision all necessary Azure resources.
- Extracts resource names and outputs from the Terraform deployment.
- Compiles the Spring Boot project and runs the app on the host machine.

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

You can set up the Azure emulator by utilizing LocalStack for Azure Docker image. Before starting, ensure you have a valid `LOCALSTACK_AUTH_TOKEN` to access the Azure emulator. Refer to the [Auth Token guide](https://docs.localstack.cloud/getting-started/auth-token/?__hstc=108988063.8aad2b1a7229945859f4d9b9bb71e05d.1743148429561.1758793541854.1758810151462.32&__hssc=108988063.3.1758810151462&__hsfp=3945774529) to obtain your Auth Token and specify it in the `LOCALSTACK_AUTH_TOKEN` environment variable. The Azure Docker image is available on the [LocalStack Docker Hub](https://hub.docker.com/r/localstack/localstack-azure-alpha). To pull the Azure Docker image, execute the following command:

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
cd samples/servicebus/java/terraform
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

Once the deployment completes, run the [validate.sh](../scripts/validate.sh) script to confirm that all resources were provisioned and configured as expected:

```bash
#!/bin/bash

# Variables
PREFIX='local'
SUFFIX='test'
RESOURCE_GROUP_NAME="${PREFIX}-rg"
SERVICEBUS_NAMESPACE_NAME="${PREFIX}-sb-ns-${SUFFIX}"
SERVICEBUS_QUEUE_NAME="myqueue"
ENVIRONMENT=$(az account show --query environmentName --output tsv)

# Choose the appropriate CLI based on the environment
if [[ $ENVIRONMENT == "LocalStack" ]]; then
  echo "Using azlocal for LocalStack emulator environment."
  AZ="azlocal"
else
  echo "Using standard az for AzureCloud environment."
  AZ="az"
fi

# Check resource group
echo -e "[$RESOURCE_GROUP_NAME] resource group:\n"
$AZ group show \
  --name "$RESOURCE_GROUP_NAME" \
  --output table \
  --only-show-errors

# Check Service Bus namespace
echo -e "\n[$SERVICEBUS_NAMESPACE_NAME] Service Bus namespace:\n"
$AZ servicebus namespace show \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --name "$SERVICEBUS_NAMESPACE_NAME" \
	--query "{name:name, location:location, serviceBusEndpoint:serviceBusEndpoint, status:provisioningState}" \
  --output table \
  --only-show-errors

# Check Service Bus queue
echo -e "\n[$SERVICEBUS_QUEUE_NAME] Service Bus queue:\n"
$AZ servicebus queue show \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --namespace-name "$SERVICEBUS_NAMESPACE_NAME" \
  --name "$SERVICEBUS_QUEUE_NAME" \
	--query "{name:name, messageCount:messageCount, sizeInBytes:sizeInBytes}" \
  --output table \
  --only-show-errors
```

## Cleanup

To destroy all created resources:

```bash
#!/bin/bash

# Variables
PREFIX='local'
SUFFIX='test'
RESOURCE_GROUP_NAME="${PREFIX}-rg"

# Delete resource group and all contained resources
az group delete --name $RESOURCE_GROUP_NAME --yes --no-wait

# Verify deletion
az group list --output table
```

This will remove all Azure resources created by the CLI deployment script.

## Related Documentation

- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest)
- [LocalStack for Azure Documentation](https://azure.localstack.cloud/)