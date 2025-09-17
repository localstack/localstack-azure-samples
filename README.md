# LocalStack for Azure Samples

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![LocalStack](https://img.shields.io/badge/LocalStack-Pro-blue)](https://localstack.cloud/)
[![Azure](https://img.shields.io/badge/Azure-Compatible-0078d4)](https://azure.microsoft.com/)

This repository contains comprehensive sample projects demonstrating how to develop and test Azure cloud applications locally using [LocalStack for Azure](https://localstack.cloud/). Each sample provides complete infrastructure-as-code templates, application code, and deployment instructions for seamless local development.

## 🏗️ Sample Structure

Each sample project is organized by Azure service and includes:

- Infrastructure templates** (Bicep/Terraform) and/or Bash installation scripts.
- Application code with best practices
- Step-by-step deployment guides and tutorials.
- Optionalky, testing and validation scripts.

Browse the service-specific directories:

- `azure-functions/` - Serverless function examples
- `azure-storage/` - Storage account and blob examples
- `azure-app-service/` - Web application examples
- `azure-cosmos-db/` - NoSQL database examples
- *[Additional services to be added]*

## 🚀 Quick Start

1. **Clone the repository**
   ```bash
   git clone https://github.com/paolosalvatori/localstack-azure-samples.git
   cd localstack-azure-samples
   ```

2. **Set up LocalStack Pro**
   ```bash
   export LOCALSTACK_AUTH_TOKEN="your-auth-token-here"
   docker-compose up -d
   ```

3. **Choose a sample and follow its README**
   ```bash
   cd azure-functions/basic-http-trigger
   # Follow the instructions in the sample's README.md
   ```

## 📋 Prerequisites

### Required Tools
- **[Docker](https://docs.docker.com/get-docker/)** - Container runtime for LocalStack
- **[Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)** - Azure command-line interface
- **[azlocal CLI](https://azure.localstack.cloud/user-guides/sdks/az/)** - LocalStack Azure CLI wrapper
- **[jq](https://jqlang.org/)** - JSON processor for scripting

### Infrastructure as Code
- **[Bicep](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/install)** - Azure ARM template language
- **[Terraform](https://developer.hashicorp.com/terraform/downloads)** - Multi-cloud infrastructure provisioning

### Development Tools
- **[Azure Storage Explorer](https://azure.microsoft.com/en-us/products/storage/storage-explorer)** - GUI for Azure Storage
- **[Azure Functions Core Tools](https://docs.microsoft.com/en-us/azure/azure-functions/functions-run-local)** - Local function development

## ⚙️ Configuration

### LocalStack Pro Setup

Most samples require LocalStack Pro features. Configure your authentication:

1. **Get your Auth Token** from the [LocalStack Web Application](https://app.localstack.cloud/workspace/auth-token)

2. **Set the environment variable**:
   ```bash
   export LOCALSTACK_AUTH_TOKEN="your-auth-token-here"
   ```

3. **Verify configuration**:
   ```bash
   curl -s http://localhost:4566/_localstack/health | jq
   ```

For detailed authentication setup, see the [Auth Token documentation](https://docs.localstack.cloud/getting-started/auth-token/).

## 📚 Documentation

- [LocalStack for Azure Documentation](https://azure.localstack.cloud/)
- [Azure CLI with LocalStack](https://azure.localstack.cloud/user-guides/sdks/az/)
- [Supported Azure Services](https://azure.localstack.cloud/references/coverage/)

## 🤝 Contributing

Contributions are welcome! Please read our [Contributing Guidelines](CONTRIBUTING.md) before submitting pull requests.

1. Fork the repository
2. Create a feature branch
3. Add your sample with complete documentation
4. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

- **Issues**: [GitHub Issues](https://github.com/paolosalvatori/localstack-azure-samples/issues)
- **LocalStack Support**: [Support Portal](https://support.localstack.cloud/)
- **Community**: [LocalStack Discuss](https://discuss.localstack.cloud/)

---

⭐ **Star this repository** if you find these samples helpful for your Azure local development workflow!
