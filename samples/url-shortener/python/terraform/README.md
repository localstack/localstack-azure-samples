# Terraform Deployment

This directory contains the Terraform configuration for the sample. For details about the sample application, see [URL Shortener](../README.md).

## Prerequisites

- [LocalStack for Azure](https://docs.localstack.cloud/azure/)
- [Docker](https://docs.docker.com/get-docker/)
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)
- [lstk CLI](https://docs.localstack.cloud/aws/developer-tools/running-localstack/lstk/)
- [Terraform](https://developer.hashicorp.com/terraform/downloads)

## Deployment

```bash
bash deploy.sh
```

The script runs `terraform init`, `plan` and `apply`, and deploys the web app and the worker from zip packages with the Azure CLI. It persists the generated PostgreSQL credentials to `../scripts/.last_deploy.<prefix>.env` (`.last_deploy.local.env` for the default prefix) so `scripts/validate.sh` works after a Terraform deployment. Terraform state stays local, matching the sibling samples.

`main.tf` creates every resource except the resource group through a module of the [modules](modules) folder: the Log Analytics workspace and the Application Insights resource, the managed identity, the storage account with its table, queue and container, the PostgreSQL server, the key vault with its two secrets, the Service Bus namespace with its queue, the role assignments, the App Service plan, the web app and the function app. Every resource that offers diagnostic settings gets one that sends to the workspace, and both apps receive the connection string of the Application Insights resource in their `APPLICATIONINSIGHTS_CONNECTION_STRING` app setting. The key vault writes its secrets through the data plane, so the identity running `terraform apply` gets Key Vault Secrets Officer on it: `deploy.sh` resolves its object id and passes it as `deployer_object_id`.

## Telemetry, logs and metrics

Once the apps are deployed, read the telemetry they sent to Application Insights and the logs and metrics the diagnostic settings sent to the workspace. The scripts take the same `PREFIX` and `SUFFIX` as the deployment:

```bash
bash ../scripts/query-telemetry.sh
bash ../scripts/query-logs-and-metrics.sh
```

See [Application Insights](../README.md#application-insights) and [Logs and metrics](../README.md#logs-and-metrics) for what they read.

## Cleanup

```bash
terraform destroy \
	-var "prefix=local" \
	-var "suffix=test" \
	-var "location=westeurope"
```
