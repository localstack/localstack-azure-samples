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

The script creates the resource group, validates and deploys `main.bicep` (generating the PostgreSQL password, the link-signing key and the internal API token per run), and then deploys the web app and the worker from zip packages with the Azure CLI. It persists the generated PostgreSQL credentials to `../scripts/.last_deploy.<prefix>.env` (`.last_deploy.local.env` for the default prefix) so `scripts/validate.sh` works after a Bicep deployment.

`main.bicep` creates every resource through a module of the [modules](modules) folder: the Log Analytics workspace and the Application Insights resource, the managed identity, the storage account with its table, queue and container, the PostgreSQL server, the key vault with its two secrets, the Service Bus namespace with its queue, the App Service plan, the web app and the function app. The role assignments of the managed identity live in the modules of the storage account, of the key vault and of the namespace. Every resource that offers diagnostic settings gets one that sends to the workspace, and both apps receive the connection string of the Application Insights resource in their `APPLICATIONINSIGHTS_CONNECTION_STRING` app setting.

## Telemetry, logs and metrics

Once the apps are deployed, read the telemetry they sent to Application Insights and the logs and metrics the diagnostic settings sent to the workspace. The scripts take the same `PREFIX` and `SUFFIX` as the deployment:

```bash
bash ../scripts/query-telemetry.sh
bash ../scripts/query-logs-and-metrics.sh
```

See [Application Insights](../README.md#application-insights) and [Logs and metrics](../README.md#logs-and-metrics) for what they read.

## Cleanup

```bash
az group delete --name local-rg --yes
```
