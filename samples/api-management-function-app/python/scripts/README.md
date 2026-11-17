# Azure CLI Deployment

This directory contains Bash scripts for deploying and validating the sample using the `lstk` CLI. For details about the sample application, see [API Management and Function App](../README.md).

## Prerequisites

- [LocalStack for Azure](https://docs.localstack.cloud/azure/)
- [Docker](https://docs.docker.com/get-docker/)
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)
- [lstk CLI](https://docs.localstack.cloud/aws/developer-tools/running-localstack/lstk/)
- [jq](https://jqlang.org/), `zip` and `openssl`

## Scripts

| Script | Purpose |
|--------|---------|
| `deploy.sh` | Idempotently provisions a Log Analytics workspace, a workspace-based Application Insights resource, the Function App and the API Management instance, deploys the function from a zip package, imports the API, applies the policy, and creates the named value, product and subscription. Every resource that offers diagnostic settings gets one that sends to the workspace. Prints the gateway URL and the command that reads the subscription key. |
| `validate.sh` | Walks the whole chain (direct backend refusal, import, key checks, forwarding, policy effects, CORS preflight, 404, rate limit, the Application Insights resource and the telemetry app settings) and exits non-zero on any failure. |
| `call-api.sh` | Quick user-level smoke test: reads the key, lists the items and reads one of them, honouring a `Retry-After` if the rate limit is still in force. |
| `query-telemetry.sh` | Calls the API through the gateway, then reads back from the workspace the telemetry the Function App sent to Application Insights: its requests, log records, custom events, custom metric and exceptions. |
| `query-logs-and-metrics.sh` | Lists the diagnostic settings of the resources, reads back from the workspace the invocation records of the Function App, the requests to the blobs, the exported platform metrics and the audit records of the queries, and ends with the executions of the Function App, the transactions of the storage account and the requests of the gateway read from the metrics API. |
