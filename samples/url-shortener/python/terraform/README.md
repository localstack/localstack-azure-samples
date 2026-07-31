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

The script runs `terraform init`, `plan` and `apply`, attaches the storage diagnostic settings to the Log Analytics workspace, and deploys the web app and the worker from zip packages with the Azure CLI. Terraform state stays local, matching the sibling samples.

## Cleanup

```bash
terraform destroy \
	-var "prefix=local" \
	-var "suffix=test" \
	-var "location=westeurope"
```
