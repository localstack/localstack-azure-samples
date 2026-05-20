# Azure Service Bus with Spring Boot

This sample demonstrates a Java Spring Boot application that sends and receives messages via [Azure Service Bus](https://learn.microsoft.com/en-us/azure/service-bus-messaging/service-bus-messaging-overview). The application uses the [Spring Cloud Azure Service Bus Stream Binder](https://learn.microsoft.com/en-us/azure/developer/java/spring-framework/configure-spring-cloud-stream-binder-java-app-with-service-bus) to connect to a Service Bus queue, send a `Hello, World!` message, and receive it back, and then exits.

> [!NOTE]
> At this time, the Azure Web Apps and Azure Function Apps emulators in LocalStack for Azure do not support Java applications. The Spring Boot sample application must be executed directly on the host machine and cannot be deployed to the emulator.

## Architecture

The solution is composed of the following Azure resources:

1. [Azure Resource Group](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/manage-resource-groups-cli): A logical container scoping all resources in this sample.
2. [Azure Service Bus Namespace](https://learn.microsoft.com/en-us/azure/service-bus-messaging/service-bus-messaging-overview): The messaging namespace that hosts the queue used by the application.
3. [Azure Service Bus Queue](https://learn.microsoft.com/en-us/azure/service-bus-messaging/service-bus-queues-topics-subscriptions#queues): The `myqueue` queue used to send and receive messages.

> **Note**
> The Java application currently runs on the host machine. In a future iteration, it will be deployed to an emulator-hosted web app.

## Prerequisites

- [Azure Subscription](https://azure.microsoft.com/free/)
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)
- [Azlocal CLI](https://azure.localstack.cloud/user-guides/sdks/az/): LocalStack Azure CLI wrapper
- [Java 21+](https://learn.microsoft.com/en-us/java/openjdk/download)
- [Maven 3.8+](https://maven.apache.org/download.cgi)
- [Terraform](https://developer.hashicorp.com/terraform/downloads), if you plan to deploy the sample via Terraform.
- [Bicep extension](https://marketplace.visualstudio.com/items?itemName=ms-azuretools.vscode-bicep), if you plan to deploy the sample via Bicep.

## Deployment

Set up the Azure emulator using the LocalStack for Azure Docker image. Before starting, ensure you have a valid `LOCALSTACK_AUTH_TOKEN` to access the Azure emulator. Refer to the [Auth Token guide](https://docs.localstack.cloud/getting-started/auth-token/) to obtain your Auth Token and set it in the `LOCALSTACK_AUTH_TOKEN` environment variable. The Azure Docker image is available on the [LocalStack Docker Hub](https://hub.docker.com/r/localstack/localstack-azure-alpha). To pull the image, execute:

```bash
docker pull localstack/localstack-azure-alpha
```

Start the LocalStack Azure emulator by running:

```bash
# Set the authentication token
export LOCALSTACK_AUTH_TOKEN=<your_auth_token>

# Start the LocalStack Azure emulator
IMAGE_NAME=localstack/localstack-azure-alpha localstack start -d
localstack wait -t 60

# Route all Azure CLI calls to the LocalStack Azure emulator
azlocal start-interception
```

Deploy the application to LocalStack for Azure using one of these methods:

- [Azure CLI Deployment](./java/scripts/deploy.sh)
- [Bicep Deployment](./java/bicep/deploy.sh)
- [Terraform Deployment](./java/terraform/deploy.sh)

All deployment methods have been fully tested against Azure and the LocalStack for Azure local emulator.

> **Note**
> When you deploy the application to LocalStack for Azure for the first time, the initialization process involves downloading and building Docker images. This is a one-time operation—subsequent deployments will be significantly faster. Depending on your internet connection and system resources, this initial setup may take several minutes.

## How It Works

The deploy script performs the following steps:

1. Creates a resource group.
2. Creates a Service Bus namespace.
3. Creates a Service Bus queue (`myqueue`).
4. Retrieves the namespace connection string and exports it as `AZURE_SERVICEBUS_CONNECTION_STRING`.
5. Starts the Spring Boot application via `mvn clean spring-boot:run`.

The application then:

1. Connects to the configured Service Bus namespace using the connection string.
2. Sends a `Hello, World!` message to the `myqueue` queue.
3. Receives the message via a `@ServiceBusListener` consumer.
4. Shuts down after receiving the message.

## References

- [Azure Service Bus Documentation](https://learn.microsoft.com/en-us/azure/service-bus-messaging/service-bus-messaging-overview)
- [Spring Cloud Azure Service Bus](https://learn.microsoft.com/en-us/azure/developer/java/spring-framework/configure-spring-cloud-stream-binder-java-app-with-service-bus)
- [Azure Service Bus Queues](https://learn.microsoft.com/en-us/azure/service-bus-messaging/service-bus-queues-topics-subscriptions)
- [Spring Boot Starter for Azure Service Bus](https://learn.microsoft.com/en-us/azure/developer/java/spring-framework/spring-cloud-azure)
- [LocalStack for Azure](https://docs.localstack.cloud/azure/)
   
 
