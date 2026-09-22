# Bicep Deployment

This directory contains the Bicep template for the sample. For details about the sample application, see [API Management and Function App](../README.md).

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

The script creates the resource group, generates the shared secret (read by `main.bicepparam` from the environment), validates and deploys `main.bicep`, and then deploys the function from a zip package with the Azure CLI. The template imports the API from `../apim/openapi.json` and reads the policy from `../apim/inventory-api-policy.xml` through `loadTextContent`, so all three deployment variants publish the same API with the same policy.

## Cleanup

```bash
az group delete --name local-rg --yes
```
