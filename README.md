# LocalStack for Azure Samples

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![LocalStack](https://img.shields.io/badge/LocalStack-Pro-blue)](https://localstack.cloud/)
[![Azure](https://img.shields.io/badge/Azure-Compatible-0078d4)](https://azure.microsoft.com/)

This repository contains comprehensive sample projects demonstrating how to develop and test Azure cloud applications locally using [LocalStack for Azure](https://localstack.cloud/). Each sample provides complete infrastructure-as-code templates, application code, and deployment instructions for seamless local development.

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

| Sample Name | Description |
|-------------|-------------|
| [Function App and Storage](./samples/function-app-storage-http/dotnet/README.md) | Azure Functions App using Blob, Queue, and Table Storage |
| [Function App and Front Door](./samples/function-app-front-door/python/README.md) | Azure Functions App exposed via Front Door |
| [Function App and Managed Identities](./samples/function-app-managed-identity/python/README.md) | Azure Function App using Managed Identities |
| [Function App and Service Bus](./samples/function-app-service-bus/dotnet/README.md) | Azure Function App using Service Bus |
| [Web App and CosmosDB for MongoDB API ](./samples/web-app-cosmosdb-mongodb-api/python/README.md) | Azure Web App using CosmosDB for MongoDB API |
| [Web App and CosmosDB for NoSQL API ](./samples/web-app-cosmosdb-nosql-api/python/README.md) | Azure Web App using CosmosDB for NoSQL API |
| [Web App and Managed Identities](./samples/web-app-managed-identity/python/README.md) | Azure Web App using Managed Identities |
| [Web App and SQL Database ](./samples/web-app-sql-database/python/README.md) | Azure Web App using SQL Database |
| [Web App and PostgreSQL Database ](./samples/web-app-postgresql-flexible-server/python/README.md) | Azure Web App using PostgreSQL Database |
| [Web App and MySQL Database ](./samples/web-app-mysql-flexible-server/python/README.md) | Azure Web App using MySQL Database |
| [Web App with Custom Docker Image](./samples/web-app-custom-image/python/README.md) | Azure Web App running a custom Docker image |
| [ACI and Blob Storage](./samples/aci-blob-storage/python/README.md) | Azure Container Instances with ACR, Key Vault, and Blob Storage |
| [Azure Service Bus with Spring Boot](./samples/servicebus/java/README.md) | Azure Service Bus used by a Spring Boot application |
| [URL Shortener](./samples/url-shortener/python/README.md) | URL shortener composing Web App, Functions, Storage, Key Vault, Service Bus and PostgreSQL |
| [Event Hubs Fraud Detection Pipeline](./samples/eventhubs/python/README.md) | Real-time payment stream processing with Event Hubs (AMQP, Kafka and HTTPS ingestion, Capture, Schema Registry), an Event Hubs-triggered Function App, Key Vault, Storage and a Web App dashboard |
| [Event Hubs Cold-Path Automation](./samples/eventhubs-eventgrid/python/README.md) | Event Hubs Capture raises `Microsoft.EventHub.CaptureFileCreated` to an Event Grid system topic, a subscription delivers it into a second event hub, and an Event Hubs-triggered Function App decodes each Avro archive and writes per-device summaries |
 
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
