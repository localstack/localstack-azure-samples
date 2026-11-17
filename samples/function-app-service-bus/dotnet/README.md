# Azure Functions App with Service Bus Messaging

This sample demonstrates how to deploy an [Azure Functions App](https://learn.microsoft.com/en-us/azure/azure-functions/functions-overview) on an [Azure App Service Plan](https://learn.microsoft.com/en-us/azure/app-service/overview-hosting-plans) that exchanges messages through queues in a [Service Bus](https://learn.microsoft.com/en-us/azure/service-bus-messaging/service-bus-messaging-overview) namespace. The function app authenticates to Azure resources using a [user-assigned managed identity](https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/overview) and connects to the Service Bus namespace via an [Azure Private Endpoint](https://learn.microsoft.com/azure/private-link/private-endpoint-overview) for secure, private network communication.

## Architecture

The following diagram illustrates the architecture of the solution:

![Architecture Diagram](./images/architecture.png)

The function app is composed of the following functions:

- **GreetingRequester**: Timer-triggered function that periodically sends a request message containing a randomly generated name to the `input` queue.
- **GreetingHandler**: Uses the [Azure Service Bus trigger](https://learn.microsoft.com/en-us/azure/azure-functions/functions-bindings-service-bus-trigger) to listen for incoming messages on the `input` queue. When a message arrives, it extracts the name, composes a greeting, and sends the result to the `output` queue using the [Azure Service Bus output binding](https://learn.microsoft.com/en-us/azure/azure-functions/functions-bindings-service-bus-output).
- **GreetingConsumer**: Timer-triggered function that periodically polls the `output` queue, retrieves greeting response messages, and logs them for monitoring.
- **GetGreetings**: HTTP-triggered function that returns the most recent greetings stored in an in-memory circular buffer. Greetings are returned in reverse chronological order (newest first), providing a quick way to verify the message pipeline is working.

The solution is composed of the following Azure resources:

1. [Azure Resource Group](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/manage-resource-groups-cli): A logical container scoping all resources in this sample.
2. [Azure Virtual Network](https://learn.microsoft.com/azure/virtual-network/virtual-networks-overview): Hosts two subnets:
	- *app-subnet*: Dedicated to [regional VNet integration](https://learn.microsoft.com/azure/azure-functions/functions-networking-options?tabs=azure-portal#outbound-networking-features) with the Function App.
	- *pe-subnet*: Used for hosting Azure Private Endpoints.
3. [Azure Private DNS Zones](https://learn.microsoft.com/azure/dns/private-dns-privatednszone): Provide internal DNS resolution so that resources within the virtual network can reach Private Endpoints by hostname rather than public addresses. There is a separate Azure Private DNS Zone for the following resource types:
  - Azure Service Bus namespace
	- Azure Blob Storage
	- Azure Queue Storage
	- Azure Table Storage
4. [Azure Private Endpoints](https://learn.microsoft.com/azure/private-link/private-endpoint-overview): Provide secure, private network connectivity to Azure resources by exposing them through private IP addresses within the virtual network, eliminating the need for traffic to traverse the public internet. There is a separate Azure Private Endpoint for the following resources:
  - Azure Service Bus namespace
	- Azure Blob Storage
	- Azure Queue Storage
	- Azure Table Storage
5. [Azure NAT Gateway](https://learn.microsoft.com/azure/nat-gateway/nat-overview): Provides deterministic outbound connectivity and a stable public IP address for the Function App's outbound traffic. Included for architectural completeness; the sample app itself does not call any external services.
6. [Azure Network Security Group](https://learn.microsoft.com/en-us/azure/virtual-network/network-security-groups-overview): Enforces inbound and outbound traffic rules across the virtual network's subnets.
7. [Azure Log Analytics Workspace](https://learn.microsoft.com/azure/azure-monitor/logs/log-analytics-overview): Centralizes the diagnostic logs and metrics of every resource, the telemetry of Application Insights, and the audit records of the queries run on it.
8. [Azure App Service Plan](https://learn.microsoft.com/en-us/azure/app-service/overview-hosting-plans): Defines the underlying compute tier and scaling behavior for the function app.
9. [Azure Functions App](https://learn.microsoft.com/en-us/azure/azure-functions/functions-overview): Hosts the sample function app.
10. [Azure Application Insights](https://learn.microsoft.com/en-us/azure/azure-monitor/app/app-insights-overview): A workspace-based resource that collects the invocations of the functions, their log records and the exceptions they log, and the custom events and the custom metric of the greetings, which the Functions host and the .NET worker send through OpenTelemetry. See [Application Insights](#application-insights).
11. [Azure Service Bus](https://learn.microsoft.com/en-us/azure/service-bus-messaging/service-bus-messaging-overview): A fully managed enterprise message broker. This namespace hosts the `input` and `output` queues used by the function app to exchange messages asynchronously.
12. [Azure Storage Account](https://learn.microsoft.com/en-us/azure/storage/common/storage-account-overview): Provides durable storage used internally by the Azure Functions runtime for state management, including distributed locks, checkpoints, and timer trigger coordination.
13. [User-Assigned Managed Identity](https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/overview): This identity is assigned the necessary RBAC roles and is used by the function app to authenticate securely—without storing credentials—to the following Azure resources: 
  - Azure Service Bus namespace
	- Azure Storage
	- Azure Application Insights

## Prerequisites

- [lstk CLI](https://docs.localstack.cloud/aws/developer-tools/running-localstack/lstk/)
- [Azure Subscription](https://azure.microsoft.com/free/)
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)
- [Azure Functions Core Tools](https://learn.microsoft.com/en-us/azure/azure-functions/functions-run-local) is required to build, run, and deploy the Azure Functions app locally
- [.NET SDK](https://dotnet.microsoft.com/en-us/download) is required to compile and run the C# Azure Functions project
- [Bicep extension](https://marketplace.visualstudio.com/items?itemName=ms-azuretools.vscode-bicep), if you plan to install the sample via Bicep.
- [Terraform](https://developer.hashicorp.com/terraform/downloads), if you plan to install the sample via Terraform.

> [!IMPORTANT]
> **Macs with Apple silicon**: the function app runs natively on arm64, but the emulator builds each deployment with Microsoft's Oryx build image, which Microsoft publishes for amd64 only ([microsoft/Oryx#2133](https://github.com/microsoft/Oryx/issues/2133) asks for arm64).
> Docker Desktop runs that build under amd64 emulation: in Docker Desktop's settings, under **General**, select the **Apple Virtualization framework** as the Virtual Machine Manager and turn on **Use Rosetta for x86_64/amd64 emulation on Apple Silicon**.
> Under QEMU, which Docker Desktop uses otherwise (Rosetta off, or Docker VMM, which has no Rosetta), the build can crash, because Oryx is a .NET app and [.NET does not support QEMU](https://github.com/dotnet/core/blob/main/release-notes/8.0/supported-os.md).

## Deployment

Set up the Azure emulator using the LocalStack for Azure Docker image. Before starting, ensure you have a valid `LOCALSTACK_AUTH_TOKEN` to access the Azure emulator. Refer to the [Auth Token guide](https://docs.localstack.cloud/getting-started/auth-token/) to obtain your Auth Token and set it in the `LOCALSTACK_AUTH_TOKEN` environment variable. The Azure Docker image is available on the [LocalStack Docker Hub](https://hub.docker.com/r/localstack/localstack-azure). To pull the image, execute:

```bash
docker pull localstack/localstack-azure
```

Start the LocalStack Azure emulator by running:

```bash
# Set the authentication token
export LOCALSTACK_AUTH_TOKEN=<your_auth_token>

# Start the LocalStack Azure emulator
lstk start --type azure

# Route all Azure CLI calls to the LocalStack Azure emulator
lstk az start-interception
```

Deploy the application to LocalStack for Azure using one of these methods:

- [Azure CLI Deployment](./scripts/README.md)
- [Bicep Deployment](./bicep/README.md)
- [Terraform Deployment](./terraform/README.md)

All deployment methods have been fully tested against Azure and the LocalStack for Azure local emulator.

> [!NOTE]
> When you deploy the application to LocalStack for Azure for the first time, the initialization process involves downloading and building Docker images. This is a one-time operation—subsequent deployments will be significantly faster. Depending on your internet connection and system resources, this initial setup may take several minutes.

## Test

Once the resources and function app have been deployed, you can use the [call-http-trigger.sh](./scripts/call-http-trigger.sh) Bash script to invoke the **GetGreetings** HTTP-triggered function. This function returns the most recent greetings stored in the in-memory circular buffer, allowing you to verify that the entire message pipeline is working end to end. The output should look like this:

```bash
Getting function app name...
Function app [local-func-test] successfully retrieved.
Getting resource group name for function app [local-func-test]...
Resource group [local-rg] successfully retrieved.
Getting the default host name of the function app [local-func-test]...
Function app default host name [local-func-test.azurewebsites.azure.localhost.localstack.cloud:4566] successfully retrieved.
Finding container name with prefix [ls-local-func-test]...
Looking for containers with names starting with [ls-local-func-test]...
Found matching container [ls-local-func-test-tdkqjh]
Container [ls-local-func-test-tdkqjh] found successfully
Getting IP address for container [ls-local-func-test-tdkqjh]...
IP address [172.17.0.7] retrieved successfully for container [ls-local-func-test-tdkqjh]
Getting the port the function app listens on in container [ls-local-func-test-tdkqjh]...
Function app listens on port [80] in container [ls-local-func-test-tdkqjh]
Getting the host port mapped to port [80] in container [ls-local-func-test-tdkqjh]...
Mapped host port [42330] retrieved successfully for container [ls-local-func-test-tdkqjh]
Calling HTTP trigger function to retrieve the last [100] greetings via hostname [babo-func-test.azurewebsites.azure.localhost.localstack.cloud:4566]...
{
  "requester": {
    "sent": [
      "Paolo",
      "Max"
    ]
  },
  "handler": {
    "received": [
      "Paolo",
      "Max"
    ],
    "sent": [
      "Welcome Paolo, glad you're here!",
      "Salutations Max, how's everything going?"
    ]
  },
  "consumer": {
    "received": [
      "Welcome Paolo, glad you're here!",
      "Salutations Max, how's everything going?"
    ]
  }
}
Calling HTTP trigger function to retrieve the last [10] greetings via container IP address [172.17.0.7]...
{
  "requester": {
    "sent": [
      "Paolo",
      "Max"
    ]
  },
  "handler": {
    "received": [
      "Paolo",
      "Max"
    ],
    "sent": [
      "Welcome Paolo, glad you're here!",
      "Salutations Max, how's everything going?"
    ]
  },
  "consumer": {
    "received": [
      "Welcome Paolo, glad you're here!",
      "Salutations Max, how's everything going?"
    ]
  }
}
Calling HTTP trigger function to retrieve the last [10] greetings via host port [42330]...
{
  "requester": {
    "sent": [
      "Paolo",
      "Max"
    ]
  },
  "handler": {
    "received": [
      "Paolo",
      "Max"
    ],
    "sent": [
      "Welcome Paolo, glad you're here!",
      "Salutations Max, how's everything going?"
    ]
  },
  "consumer": {
    "received": [
      "Welcome Paolo, glad you're here!",
      "Salutations Max, how's everything going?"
    ]
  }
}
```

You can also inspect the function app's runtime behavior by viewing the logs of its Docker container. Run `docker logs ls-local-func-test-xxxxxx` (replacing `xxxxxx` with the actual container suffix) to see output similar to the following:

```bash
[2026-03-17T13:11:30.000Z] Executing 'Functions.GreetingRequester' (Reason='Timer fired at 2026-03-17T13:11:30.0002087+00:00', Id=1677eef3-d54a-434a-b21c-0bb1606ebedc)
[2026-03-17T13:11:30.001Z] [GreetingRequester] Timer trigger function started.
[2026-03-17T13:11:30.001Z] [GreetingRequester] Creating Service Bus client for sending messages...
[2026-03-17T13:11:30.001Z] [GreetingRequester] Creating sender for input queue 'input'
[2026-03-17T13:11:30.001Z] [GreetingRequester] Sending message to input queue 'input'...
[2026-03-17T13:11:30.219Z] [GreetingRequester] Successfully sent message to input queue 'input' with name: Jane
[2026-03-17T13:11:30.219Z] [GreetingRequester] Function Ran. Next timer schedule = (null)
[2026-03-17T13:11:30.219Z] Executed 'Functions.GreetingRequester' (Succeeded, Id=1677eef3-d54a-434a-b21c-0bb1606ebedc, Duration=218ms)
[2026-03-17T13:11:30.298Z] Executing 'Functions.GreetingHandler' (Reason='(null)', Id=5ec3e867-0073-44d4-8dc8-869e0ce95401)
[2026-03-17T13:11:30.298Z] Trigger Details: MessageId: c5a1b026-b435-4f62-b273-de9f6e2224a1, SequenceNumber: 1, DeliveryCount: 1, EnqueuedTimeUtc: 2026-03-17T13:11:30.2170000+00:00, LockedUntilUtc: 2026-03-17T13:12:30.2170000+00:00, SessionId: (null)
[2026-03-17T13:11:30.299Z] [GreetingHandler] Message ID: c5a1b026-b435-4f62-b273-de9f6e2224a1
[2026-03-17T13:11:30.299Z] [GreetingHandler] Message Body: {"name":"Jane"}
[2026-03-17T13:11:30.299Z] [GreetingHandler] Message Content-Type: application/json
[2026-03-17T13:11:30.299Z] [GreetingHandler] Processing request for name: Jane
[2026-03-17T13:11:30.299Z] Start processing HTTP request POST http://127.0.0.1:43127/Settlement/Complete
[2026-03-17T13:11:30.299Z] Sending HTTP request POST http://127.0.0.1:43127/Settlement/Complete
[2026-03-17T13:11:30.302Z] Received HTTP response headers after 2.609ms - 200
[2026-03-17T13:11:30.302Z] End processing HTTP request after 2.6465ms - 200
[2026-03-17T13:11:30.302Z] [GreetingHandler] Processed message [c5a1b026-b435-4f62-b273-de9f6e2224a1] successfully: Hi Jane, great to see you!
[2026-03-17T13:11:30.303Z] Executed 'Functions.GreetingHandler' (Succeeded, Id=5ec3e867-0073-44d4-8dc8-869e0ce95401, Duration=4ms)
[2026-03-17T13:11:34.375Z] [GreetingConsumer] Function Ran. Next timer schedule = (null)
[2026-03-17T13:11:34.375Z] Executed 'Functions.GreetingConsumer' (Succeeded, Id=32dbc94a-4ff7-4315-9de4-ea36593589fc, Duration=10427ms)
[2026-03-17T13:11:34.380Z] Executing 'Functions.GreetingConsumer' (Reason='Timer fired at 2026-03-17T13:11:34.3806261+00:00', Id=af37440c-360b-4114-97ea-bf88f1843bcf)
[2026-03-17T13:11:34.381Z] [GreetingConsumer] Timer trigger function started.
[2026-03-17T13:11:34.381Z] [GreetingConsumer] Creating Service Bus client for receiving messages...
[2026-03-17T13:11:34.381Z] [GreetingConsumer] Starting to receive messages from output queue 'output'
[2026-03-17T13:11:34.799Z] [GreetingConsumer] Successfully received and deserialized message from output queue. Date: 2026-03-17T13:06:30, Text: Hi Jane, great to see you!
[2026-03-17T13:11:39.802Z] [GreetingConsumer] No more messages available in output queue 'output'
```

## Application Insights

The function app sends its telemetry to a workspace-based [Application Insights](https://learn.microsoft.com/en-us/azure/azure-monitor/app/app-insights-overview) resource that stores it in the `<prefix>-log-analytics-<suffix>` workspace. The three deployment methods set the `APPLICATIONINSIGHTS_CONNECTION_STRING` app setting to the connection string of the resource. `host.json` sets `telemetryMode` to `OpenTelemetry`, so the Functions host and the .NET isolated worker both send their telemetry through [OpenTelemetry](https://learn.microsoft.com/en-us/azure/azure-functions/opentelemetry-howto): the worker with `Microsoft.Azure.Functions.Worker.OpenTelemetry` and the Azure Monitor exporter. The functions also send a [custom event](https://learn.microsoft.com/en-us/azure/azure-monitor/app/opentelemetry-add-modify#send-custom-events) for each greeting they request, process or receive, and count these operations in the `greetings` [custom metric](https://learn.microsoft.com/en-us/azure/azure-monitor/app/opentelemetry-add-modify#add-custom-metrics):

```csharp
var host = new HostBuilder()
    .ConfigureFunctionsWorkerDefaults()
    .ConfigureServices(services =>
    {
        if (!string.IsNullOrEmpty(Environment.GetEnvironmentVariable("APPLICATIONINSIGHTS_CONNECTION_STRING")))
        {
            services.AddOpenTelemetry()
                .UseFunctionsWorkerDefaults()
                .WithMetrics(metrics => metrics.AddMeter(GreetingTelemetry.MeterName))
                .UseAzureMonitorExporter();
        }
    })
    .Build();

// GreetingTelemetry.cs
public static void Track(ILogger logger, string eventName, string operation, string name)
{
    logger.LogInformation("{microsoft.custom_event.name} {greeting.name}", eventName, name);
    Greetings.Add(1, new KeyValuePair<string, object?>("operation", operation));
}
```

`Microsoft.Azure.Functions.Worker.OpenTelemetry` 1.2.0 needs the 2.52.0 version of the worker, which the project references: with an older `Microsoft.Azure.Functions.Worker`, every invocation fails.

The workspace keeps the telemetry in these tables:

| Table           | What the function app sends                                                                                                         |
| --------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| `AppRequests`   | The invocations of the functions, such as the runs of the `GreetingRequester` timer function                                        |
| `AppTraces`     | The log records of the functions and of the Functions host                                                                          |
| `AppEvents`     | The `GreetingRequested`, `GreetingProcessed` and `GreetingReceived` custom events, with the name of the greeting in `greeting.name` |
| `AppMetrics`    | The `greetings` custom metric, with the operation (`request`, `process` or `receive`) in `operation`                                |
| `AppExceptions` | The exceptions the functions log, with their stack trace                                                                            |

[`scripts/query-telemetry.sh`](./scripts/query-telemetry.sh) reads the tables back, retrying until their records arrive. The timers keep the function app busy by themselves, so the script calls nothing.

## Logs and metrics

The function app, its App Service plan, the storage account and its blob, queue, table and file services, the Service Bus namespace, the VNet, the two NSGs, the NAT Gateway and its public IP each have a diagnostic setting that sends their resource logs, their platform metrics or both to the `<prefix>-log-analytics-<suffix>` Log Analytics workspace, and the workspace has one that sends the audit records of the queries run on it (`Audit`, table `LAQueryLogs`) to itself. The Application Insights resource has none: its telemetry is already in the workspace it's based on, and a diagnostic setting of a workspace-based Application Insights resource [can't send to that workspace](https://learn.microsoft.com/en-us/azure/azure-monitor/app/export-telemetry#diagnostic-settings-based-export). The private endpoints, the private DNS zones and the managed identity offer no diagnostic settings.

| Resource                 | Tables in the workspace                                   | What the sample leaves there                                                                                        |
| ------------------------ | --------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| Function app             | `FunctionAppLogs`                                         | The records the Functions host writes for each invocation                                                           |
| Storage account services | `StorageBlobLogs`, `StorageQueueLogs`, `StorageTableLogs` | The requests of the Functions host to the blobs it keeps its locks and keys in; the sample uses no queues or tables |
| Service Bus namespace    | `AZMSRunTimeAuditLogs`, `AZMSOperationalLogs`             | The sends and receives of the functions, and the operations that change the namespace                               |

Their platform metrics land in the `AzureMetrics` table. The setting of the Service Bus namespace writes to the resource-specific tables, which Microsoft recommends over the shared `AzureDiagnostics` table: the Azure CLI script passes `--export-to-resource-specific true`, the Bicep module sets `logAnalyticsDestinationType: 'Dedicated'` and the Terraform module `log_analytics_destination_type = "Dedicated"`. The VNet and the two NSGs send their network logs; on the emulator these categories stay empty, because no traffic crosses an emulated network security group.

[`scripts/query-logs-and-metrics.sh`](./scripts/query-logs-and-metrics.sh) shows the diagnostic settings and reads these tables back, retrying until their records arrive (the queue and table logs only once, since nothing writes them), then reads the executions of the function app, the transactions of the storage account and the messages of the namespace from the Azure Monitor metrics API. On Azure the first records of a new diagnostic setting can take up to 90 minutes: raise `RETRY_COUNT` there. On Azure the script reads the exported platform metrics (`AzureMetrics`) only once: Azure exports them late and irregularly, so the script shows those that arrived and notes how many are still missing, without failing.

## References

- [Azure Functions Apps Documentation](https://learn.microsoft.com/en-us/azure/app-service/)
- [Azure Service Bus](https://learn.microsoft.com/en-us/azure/service-bus-messaging/service-bus-messaging-overview)
- [LocalStack for Azure](https://docs.localstack.cloud/azure/)
- [lstk CLI](https://docs.localstack.cloud/aws/developer-tools/running-localstack/lstk/)
- [lstk GitHub repository](https://github.com/localstack/lstk)
