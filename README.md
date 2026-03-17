# LocalStack for Azure Samples

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![LocalStack](https://img.shields.io/badge/LocalStack-Pro-blue)](https://localstack.cloud/)
[![Azure](https://img.shields.io/badge/Azure-Compatible-0078d4)](https://azure.microsoft.com/)

This repository contains comprehensive sample projects demonstrating how to develop and test Azure cloud applications locally using [LocalStack for Azure](https://localstack.cloud/). Each sample provides complete infrastructure-as-code templates, application code, and deployment instructions for seamless local development.

## Prerequisites

### Required Tools
- [Docker](https://docs.docker.com/get-docker/): Container runtime for LocalStack
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli): Azure command-line interface
- [azlocal CLI](https://azure.localstack.cloud/user-guides/sdks/az/): LocalStack Azure CLI wrapper
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
| [ACI and Blob Storage](./samples/aci-blob-storage/python/README.md) | Azure Container Instances with ACR, Key Vault, and Blob Storage |
| [Web App and SQL Database ](./samples/web-app-sql-database/python/README.md) | Azure Web App using SQL Database | 
| [ServiceBus ](./samples/servicebus/README.md) | Azure ServiceBus used by a Spring Boot application | 
 
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

### Troubleshooting: Line Endings
If you encounter errors like `invalid option name` or `: command not found` when running on Linux/WSL, it's likely due to Windows-style line endings (CRLF). You can fix this by running:
```bash
find . -name "*.sh" -exec sed -i 's/\r$//' {} +
```
Or by installing and using `dos2unix`.

## Configuration

Follow the comprehensive setup guide in [LocalStack for Azure Quick Start](./docs/LOCALSTACK.md) to configure your LocalStack for Azure development environment.

## Documentation

- [LocalStack for Azure Documentation](https://azure.localstack.cloud/)
- [Azure CLI with LocalStack](https://azure.localstack.cloud/user-guides/sdks/az/)
- [Supported Azure Services](https://azure.localstack.cloud/references/coverage/)

## Contributing

Contributions are welcome! Please read our [Contributing Guidelines](CONTRIBUTING.md) before submitting pull requests.

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
