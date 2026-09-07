# LocalStack for Azure Samples

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![LocalStack](https://img.shields.io/badge/LocalStack-Pro-blue)](https://localstack.cloud/)
[![Azure](https://img.shields.io/badge/Azure-Compatible-0078d4)](https://azure.microsoft.com/)

This repository contains comprehensive sample projects demonstrating how to develop and test Azure cloud applications locally using [LocalStack for Azure](https://localstack.cloud/). Each sample provides complete infrastructure-as-code templates, application code, and deployment instructions for seamless local development.

> [!NOTE]
> Azure Kubernetes Service (AKS) samples and tutorials live in a separate repository, [localstack-samples/aks-samples](https://github.com/localstack-samples/aks-samples). It covers cluster provisioning, application deployments backed by Azure data services, and standalone walkthroughs of individual AKS capabilities such as network policies, KEDA autoscaling, the Gateway API, and the Key Vault CSI driver. Everything there runs unchanged against both Azure and the emulator.

## Prerequisites

### Required Tools
- [Docker](https://docs.docker.com/get-docker/): Container runtime for LocalStack
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli): Azure command-line interface
- [lstk CLI](https://docs.localstack.cloud/aws/developer-tools/running-localstack/lstk/): LocalStack command-line interface (proxies the Azure CLI via `lstk az`)
- [jq](https://jqlang.org/): JSON processor for scripting

### Infrastructure as Code
- [Bicep](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/install): Azure ARM template language
- [Terraform](https://developer.hashicorp.com/terraform/downloads): Multi-cloud infrastructure provisioning

### Development Tools
- [Azure Storage Explorer](https://azure.microsoft.com/en-us/products/storage/storage-explorer): GUI for Azure Storage
- [Azure Functions Core Tools](https://docs.microsoft.com/en-us/azure/azure-functions/functions-run-local): Local function development

## Outline

Each sample is a self-contained project with its own README, Azure CLI scripts and, where applicable, Bicep and Terraform deployments that target both real Azure and the LocalStack for Azure emulator. The language of each implementation is shown in parentheses; the web-app samples share the same *Vacation Planner* application and come in a Python (Flask) and a .NET 10 (ASP.NET Core Razor Pages) version.

| Sample | Description |
|--------|-------------|
| [Function App and Storage (.NET)](./samples/function-app-storage-http/dotnet/README.md) | A gaming scoreboard built on Azure Functions (isolated worker): HTTP triggers record player scores in Table Storage, publish messages to Queue Storage and write game-session summaries to Blob Storage, all against the emulated storage account. |
| [Function App and Front Door (Python)](./samples/function-app-front-door/python/README.md) | A minimal Python Function App answering `/{name}`, published behind an Azure Front Door (Standard) profile so requests reach the function through the Front Door endpoint; deployable to real Azure or to the emulator. |
| [Function App and Managed Identities (Python)](./samples/function-app-managed-identity/python/README.md) | A serverless text processor: an Azure Functions app reads text blobs from an `input` container, converts them to uppercase and writes the result to an `output` container, authenticating to the storage account with a managed identity instead of keys. |
| [Function App and Service Bus (.NET)](./samples/function-app-service-bus/dotnet/README.md) | An Azure Functions app on an App Service plan that exchanges messages through Service Bus queues: an HTTP trigger sends greetings and a queue trigger consumes them, connecting with either a connection string or a managed identity. |
| Web App and CosmosDB for MongoDB API ([Python](./samples/web-app-cosmosdb-mongodb-api/python/README.md), [.NET](./samples/web-app-cosmosdb-mongodb-api/dotnet/README.md)) | The *Vacation Planner* single-page web app on an Azure Web App with regional VNet integration, storing activities in the `activities` collection of an Azure Cosmos DB for MongoDB account reached through a private endpoint. |
| Web App and CosmosDB for NoSQL API ([Python](./samples/web-app-cosmosdb-nosql-api/python/README.md), [.NET](./samples/web-app-cosmosdb-nosql-api/dotnet/README.md)) | The *Vacation Planner* single-page web app on an Azure Web App, storing activities as JSON items in the `activities` container of an Azure Cosmos DB for NoSQL database partitioned by user; deployed with Azure CLI scripts. |
| Web App and Managed Identities ([Python](./samples/web-app-managed-identity/python/README.md), [.NET](./samples/web-app-managed-identity/dotnet/README.md)) | The *Vacation Planner* single-page web app on an Azure Web App, storing each activity as a blob in an `activities` container and accessing Blob Storage through a user-assigned or system-assigned managed identity rather than connection strings. |
| Web App and SQL Database ([Python](./samples/web-app-sql-database/python/README.md), [.NET](./samples/web-app-sql-database/dotnet/README.md)) | The *Vacation Planner* single-page web app on an Azure Web App, storing activities in an Azure SQL Database. The connection string and the HTTPS certificate are read from Azure Key Vault, and an API endpoint verifies the Key Vault certificate. |
| Web App and PostgreSQL Database ([Python](./samples/web-app-postgresql-flexible-server/python/README.md), [.NET](./samples/web-app-postgresql-flexible-server/dotnet/README.md)) | The *Vacation Planner* single-page web app on an Azure Web App, storing activities in an Azure Database for PostgreSQL flexible server injected into a virtual network (delegated subnet and private DNS zone), with the database and application user created by the deploy scripts. |
| Web App and MySQL Database ([Python](./samples/web-app-mysql-flexible-server/python/README.md), [.NET](./samples/web-app-mysql-flexible-server/dotnet/README.md)) | The *Vacation Planner* single-page web app on an Azure Web App, storing activities in an Azure Database for MySQL flexible server injected into a virtual network, using TLS-only connections, with the database and application user created by the deploy scripts. |
| Web App with Custom Docker Image ([Python](./samples/web-app-custom-image/python/README.md), [.NET](./samples/web-app-custom-image/dotnet/README.md)) | A web app that runs a custom container image built locally and pushed to Azure Container Registry; the web app pulls it with a managed identity (AcrPull) through a VNet-integrated network and reports its image and host name on `/api/status`. |
| [ACI and Blob Storage (Python)](./samples/aci-blob-storage/python/README.md) | A containerized Flask web app on Azure Container Instances, with its image in Azure Container Registry, its secrets in Key Vault and its data in Blob Storage. |
| [Container Apps and Blob Storage (Python)](./samples/container-apps-blob-storage/python/README.md) | A guestbook web app on Azure Container Apps pulled from Azure Container Registry that persists entries in Blob Storage and exercises secrets, revisions, replicas and scale rules. |
| [Azure Service Bus with Spring Boot (Java)](./samples/servicebus/java/README.md) | A Java Spring Boot application that sends and receives Service Bus messages through the Spring Cloud Azure Service Bus Stream Binder. |
| [URL Shortener (Python)](./samples/url-shortener/python/README.md) | *Linklet*, a Flask URL shortener on an Azure Web App with an event-driven Azure Functions worker, composing Web App, Functions, Storage, Key Vault, Service Bus and PostgreSQL into a single causal chain. |
| [Event Hubs Fraud Detection Pipeline (Python)](./samples/eventhubs/python/README.md) | A streaming platform in miniature: payments ingested into Event Hubs over AMQP, Kafka and HTTPS, validated against Schema Registry, archived with Capture, scored by an Event Hubs-triggered Function App and shown on a Web App dashboard, with secrets in Key Vault. |
| [Event Hubs Cold-Path Automation (Python)](./samples/eventhubs-eventgrid/python/README.md) | A cold-chain monitoring pipeline in which Event Hubs Capture raises `Microsoft.EventHub.CaptureFileCreated` events to an Event Grid system topic; a subscription delivers them into a second event hub and an Event Hubs-triggered Function App decodes each Avro archive into per-device summaries. |

## Sample Structure

Each sample project is organized by Azure service and includes:

- Infrastructure templates (Bicep/Terraform) and/or Bash installation scripts.
- Application code with best practices
- Step-by-step deployment guides and tutorials.
- Optionally, testing and validation scripts.

## Local Testing

To validate all samples locally, you can run the same test suite used in the CI. This script will start LocalStack, configure the Azure CLI cloud profile, and execute the deployment and test scripts for each sample.

```bash
cd localstack-azure-samples

# Set your LOCALSTACK_AUTH_TOKEN
export LOCALSTACK_AUTH_TOKEN=<your-token>

# Or create a .env file:
# echo "LOCALSTACK_AUTH_TOKEN=<your-token>" > .env

./run-samples.sh
```

### Architecture support (amd64 / arm64)

Some samples run **natively** on `arm64` (Apple Silicon, arm64 CI runners); the rest depend on
container images Microsoft publishes for `amd64` alone, so there is no `arm64` image to pull.

| Sample | Native amd64 | Native arm64 | Backing image |
| --- | :---: | :---: | --- |
| `function-app-*` | ✅ | ✅ | built from a multi-arch `python` / `node` / `dotnet` base |
| `web-app-custom-image` | ✅ | ✅ | the image the sample builds itself |
| `aci-blob-storage` | ✅ | ✅ | the image the sample builds itself |
| `container-apps-blob-storage` | ✅ | ✅ | the image the sample builds itself |
| `web-app-*` (code deployment) | ✅ | emulated | `mcr.microsoft.com/oryx/<platform>` |
| `eventhubs` | ✅ | emulated | deploys a dashboard web app (Oryx, as above) |
| `servicebus/java` | ✅ | emulated | `mcr.microsoft.com/azure-app-service/java` |
| `web-app-sql-database` | ✅ | emulated | `mcr.microsoft.com/mssql/server` |

**"emulated" does not mean broken.** The emulator never pins `--platform`, so on an `arm64` host
Docker pulls the `amd64` image and runs it under whatever emulation the runtime provides. Docker
Desktop on Apple Silicon does this via Rosetta, so these samples do work on a Mac — just more
slowly. They fail only on an `arm64` host with no emulation registered, such as GitHub's
`ubuntu-*-arm` runners, which is why CI schedules only the natively-supported samples on `arm64`.

`run-samples.sh` warns when it runs one of these on an `arm64` host; set `SKIP_AMD64_ONLY=1` to skip
them instead. The authoritative list lives in `ARM64_SAMPLE_DIRS` in [run-samples.sh](./run-samples.sh);
the CI matrix is generated from it, so adding a sample there is all that is needed to have it
covered natively on both architectures.

> **Note:** Function Apps on `arm64` were fixed by
> [localstack-pro#8102](https://github.com/localstack/localstack-pro/pull/8102) and work on the
> current `localstack/localstack-azure:latest`. If you pin an older emulator image, expect every
> Function App deployment to fail with a misleading `500 ... No route to host`: those images
> unpack `amd64` Azure Functions Core Tools into an `arm64` image, so the host process cannot run.

### Troubleshooting: Line Endings
If you encounter errors like `invalid option name` or `: command not found` when running on Linux/WSL, it's likely due to Windows-style line endings (CRLF). You can fix this by running:
```bash
find . -name "*.sh" -exec sed -i 's/\r$//' {} +
```
Or by installing and using `dos2unix`.

## Configuration

Follow the comprehensive setup guide in [LocalStack for Azure Quick Start](./docs/LOCALSTACK.md) to configure your LocalStack for Azure development environment.

## Documentation

- [LocalStack for Azure Documentation](https://docs.localstack.cloud/azure/)
- [lstk CLI](https://docs.localstack.cloud/aws/developer-tools/running-localstack/lstk/)
- [lstk GitHub repository](https://github.com/localstack/lstk)
- [Supported Azure Services](https://azure.localstack.cloud/references/coverage/)

## Contributing

Contributions are welcome!

1. Fork the repository
2. Create a feature branch
3. Add your sample with complete documentation
4. Submit a pull request

## License

This project is licensed under the [MIT LICENSE](LICENSE).

## Support

- Issues: [GitHub Issues](https://github.com/localstack-samples/localstack-azure-samples/issues)
- LocalStack Support: [Support Portal](https://support.localstack.cloud/)
- Community: [LocalStack Discuss](https://discuss.localstack.cloud/)

## Show Your Support

Please give a ⭐ to this repository, if you find these samples helpful for your Azure local development workflow!
