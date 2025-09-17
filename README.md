# LocalStack for Azure Samples

This repository contains sample projects that can be deployed on your local machine using [LocalStack for Azure](https://localstack.cloud/).

Each example in the repository is prefixed with the name of the Azure service being used. For example, the `azure-functions` directory contains examples that demonstrate how to use the Azure Functions service with LocalStack. Please refer to the sub directories for more details and instructions on how to start the samples.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/)
- [az CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)
- [azlocal CLI](https://azure.localstack.cloud/user-guides/sdks/az/)
- [Bicep](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/install)
- [Terraform](https://developer.hashicorp.com/terraform/downloads)
- [Azure Storage Explorer](https://azure.microsoft.com/en-us/products/storage/storage-explorer)
- [jq](https://jqlang.org/)

## Configuration

Some of the samples require LocalStack Pro features. Please make sure to properly configure the `LOCALSTACK_AUTH_TOKEN` environment variable. You can find your Auth Token on the [LocalStack Web Application](https://app.localstack.cloud/workspace/auth-token) and you can refer to our [Auth Token documentation](https://docs.localstack.cloud/getting-started/auth-token/) for more details.
