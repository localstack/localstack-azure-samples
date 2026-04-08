# Azure CLI Deployment

This directory contains Azure CLI scripts and a deployment script for provisioning Azure services in LocalStack for Azure. For further details about the sample application, refer to the [Azure Service Bus with Spring Boot](../../README.md).

## Prerequisites

Before deploying this solution, ensure you have the following tools installed:

- [LocalStack for Azure](https://azure.localstack.cloud/): Local Azure cloud emulator for development and testing
- [Visual Studio Code](https://code.visualstudio.com/): Code editor installed on one of the [supported platforms](https://code.visualstudio.com/docs/supporting/requirements#_platforms)
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

The Azure CLI scripts create the following Azure resources:

1. [Azure Resource Group](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/manage-resource-groups-cli): A logical container scoping all resources in this sample.
2. [Azure Service Bus Namespace](https://learn.microsoft.com/en-us/azure/service-bus-messaging/service-bus-messaging-overview): The messaging namespace that hosts the queue used by the application.
3. [Azure Service Bus Queue](https://learn.microsoft.com/en-us/azure/service-bus-messaging/service-bus-queues-topics-subscriptions#queues): The `myqueue` queue used to send and receive messages.

The Spring Boot sample application connects to the Service Bus namespace, sends a test message to the sample queue, receives it back, and exits. For more information on the sample application, see [Azure Service Bus with Spring Boot](../../README.md).

## Provisioning Scripts

You can use the [deploy.sh](deploy.sh) script to automate the deployment of all Azure resources and the sample application in a single step, streamlining setup and reducing manual configuration. The script executes the following steps:

- Detects the environment (LocalStack vs Azure Cloud) and selects the appropriate CLI.
- Checks whether each resource (resource group, namespace, queue) already exists before creating it.
- Creates the Azure Resource Group in the specified location.
- Creates the Service Bus Namespace within the resource group.
- Creates the Service Bus Queue within the namespace.
- Retrieves the connection string for the Service Bus namespace.
- Compiles the Spring Boot project and runs the app on the host machine.

## Deployment

You can set up the Azure emulator by utilizing LocalStack for Azure Docker image. Before starting, ensure you have a valid `LOCALSTACK_AUTH_TOKEN` to access the Azure emulator. Refer to the [Auth Token guide](https://docs.localstack.cloud/getting-started/auth-token/) to obtain your Auth Token and specify it in the `LOCALSTACK_AUTH_TOKEN` environment variable. The Azure Docker image is available on the [LocalStack Docker Hub](https://hub.docker.com/r/localstack/localstack-azure-alpha). To pull the Azure Docker image, execute the following command:

```bash
docker pull localstack/localstack-azure-alpha
```

Start the LocalStack Azure emulator using the localstack CLI, execute the following command:

```bash
# Set the authentication token
export LOCALSTACK_AUTH_TOKEN=<your_auth_token>

# Start the LocalStack Azure emulator
IMAGE_NAME=localstack/localstack-azure-alpha localstack start -d
localstack wait -t 60

# Route all Azure CLI calls to the LocalStack Azure emulator
azlocal start-interception
```

Navigate to the `scripts` folder:

```bash
cd samples/servicebus/java/scripts
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

Once the deployment completes, run the [validate.sh](validate.sh) script to confirm that all resources were provisioned and configured as expected:

```bash
#!/bin/bash

# Variables
PREFIX='local'
SUFFIX='test'
RESOURCE_GROUP_NAME="${PREFIX}-rg"
SERVICEBUS_NAMESPACE_NAME="${PREFIX}-sb-ns-${SUFFIX}"
SERVICEBUS_QUEUE_NAME="myqueue"

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
az group show \
  --name "$RESOURCE_GROUP_NAME" \
  --output table \
  --only-show-errors

# Check Service Bus namespace
echo -e "\n[$SERVICEBUS_NAMESPACE_NAME] Service Bus namespace:\n"
az servicebus namespace show \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --name "$SERVICEBUS_NAMESPACE_NAME" \
	--query "{name:name, location:location, serviceBusEndpoint:serviceBusEndpoint, status:provisioningState}" \
  --output table \
  --only-show-errors

# Check Service Bus queue
echo -e "\n[$SERVICEBUS_QUEUE_NAME] Service Bus queue:\n"
az servicebus queue show \
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

- [Azure CLI Documentation](https://docs.microsoft.com/en-us/cli/azure/)
- [LocalStack for Azure Documentation](https://azure.localstack.cloud/)