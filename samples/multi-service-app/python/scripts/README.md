# Azure CLI Deployment

This directory contains Bash scripts for deploying and validating the sample using the `lstk` CLI. For details about the sample application, see [Multi-Service App](../README.md).

## Prerequisites

- [LocalStack for Azure](https://docs.localstack.cloud/azure/)
- [Docker](https://docs.docker.com/get-docker/)
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)
- [lstk CLI](https://docs.localstack.cloud/aws/developer-tools/running-localstack/lstk/)
- [jq](https://jqlang.org/), `zip`, `openssl` and [psql](https://www.postgresql.org/docs/current/app-psql.html)

## Scripts

| Script | Purpose |
|--------|---------|
| `deploy.sh` | Idempotently provisions all resources and deploys the web app and the worker from zip packages. Persists the generated PostgreSQL credentials to `.last_deploy.env`. |
| `validate.sh` | Walks the full causal chain end to end and exits non-zero on any failure. |
| `call-web-app.sh` | Quick user-level smoke test: home page, shorten a URL, follow the redirect. |
