# Bicep Deployment

This directory contains the Bicep template for the sample. For details about the sample application, see [URL Shortener](../README.md).

## Prerequisites

- [LocalStack for Azure](https://docs.localstack.cloud/azure/)
- [Docker](https://docs.docker.com/get-docker/)
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) with [Bicep](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/install)
- [lstk CLI](https://docs.localstack.cloud/aws/developer-tools/running-localstack/lstk/)
- [jq](https://jqlang.org/), `zip` and `openssl`

## Deployment

```bash
bash deploy.sh
```

The script creates the resource group, validates and deploys `main.bicep` (generating the PostgreSQL password, the link-signing key and the internal API token per run), and then deploys the web app and the worker from zip packages with the Azure CLI.

## Cleanup

```bash
az group delete --name local-rg --yes
```
