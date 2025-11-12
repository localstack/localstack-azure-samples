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
| [Web App and CosmosDB ](./samples/web-app-cosmosdb-mongodb-api/python/README.md) | Azure Web App using CosmosDB for MongoDB API | 
| [Web App and SQL Database ](./samples/web-app-sql-database/python/README.md) | Azure Web App using SQL Database | 
 
## Sample Structure

Each sample project is organized by Azure service and includes:

- Infrastructure templates (Bicep/Terraform) and/or Bash installation scripts.
- Application code with best practices
- Step-by-step deployment guides and tutorials.
- Optionally, testing and validation scripts.

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
