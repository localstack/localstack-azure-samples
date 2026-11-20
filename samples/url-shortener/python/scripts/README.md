# Azure CLI Deployment

This directory contains Bash scripts for deploying and validating the sample using the `lstk` CLI. For details about the sample application, see [URL Shortener](../README.md).

## Prerequisites

- [LocalStack for Azure](https://docs.localstack.cloud/azure/)
- [Docker](https://docs.docker.com/get-docker/)
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)
- [lstk CLI](https://docs.localstack.cloud/aws/developer-tools/running-localstack/lstk/)
- [jq](https://jqlang.org/), `zip`, `openssl` and [psql](https://www.postgresql.org/docs/current/app-psql.html)

## Scripts

| Script | Purpose |
|--------|---------|
| `deploy.sh` | Idempotently provisions all resources, among them a Log Analytics workspace and a workspace-based Application Insights resource, gives every resource that offers diagnostic settings one that sends to the workspace, and deploys the web app and the worker from zip packages. The key vault writes its secrets through the data plane, so the identity running `deploy.sh` gets Key Vault Secrets Officer on it. Persists the generated PostgreSQL credentials to `.last_deploy.<prefix>.env` (`.last_deploy.local.env` for the default prefix). |
| `validate.sh` | Walks the full causal chain end to end, checks the Application Insights resource and the telemetry app settings of both apps, and exits non-zero on any failure. |
| `call-web-app.sh` | Quick user-level smoke test: home page, shorten a URL, follow the redirect. |
| `query-telemetry.sh` | Shortens and follows a link, waits for the workers, then reads back from the workspace the telemetry the two apps sent to Application Insights: requests, dependencies, log records, custom events, custom metrics and exceptions. |
| `query-logs-and-metrics.sh` | Lists the diagnostic settings of the resources and reads back from the workspace the logs and metrics they sent, then reads platform metrics from the metrics API. |
