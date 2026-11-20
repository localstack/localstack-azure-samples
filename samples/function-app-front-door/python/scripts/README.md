# Azure CLI Deployment

This directory contains Bash scripts for deploying and validating the sample using the `lstk` CLI. For details about the sample application, see [Front Door and Function Apps](../README.md).

## Prerequisites

- [LocalStack for Azure](https://docs.localstack.cloud/azure/)
- [Docker](https://docs.docker.com/get-docker/)
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)
- [lstk CLI](https://docs.localstack.cloud/aws/developer-tools/running-localstack/lstk/)
- [jq](https://jqlang.org/) and `zip`

## Scripts

| Script | Purpose |
|--------|---------|
| `deploy.sh` | Idempotently provisions a Log Analytics workspace, a workspace-based Application Insights resource, and two Function Apps and their storage on a shared App Service plan, deploys the same zip package to both, then creates the Front Door profile, endpoint, two origin groups, three origins, the rule set with its three rules, and the two routes. Every resource that offers diagnostic settings gets one that sends its resource logs and platform metrics to the workspace. Prints the endpoint URL and the commands to try it. |
| `validate.sh` | Walks the whole chain (origin health and the probe method, routing, route specificity, origin priority, the three rules, caching and purge, the headers the edge adds, an origin error, the endpoint's enabled state, the Application Insights resource and the telemetry app settings of both apps) and exits non-zero on any failure. |
| `call-front-door.sh` | Quick user-level smoke test: read a catalog item, read it again from the edge cache, follow the rewrite and the redirect, and print what the origin received. |
| `query-telemetry.sh` | Calls the endpoint, then reads back from the workspace the telemetry the two Function Apps sent to Application Insights: their requests, log records, custom events, custom metric and exceptions. |
| `query-logs-and-metrics.sh` | Lists the diagnostic settings of the resources, reads back from the workspace the invocation records of the Function Apps, the requests the endpoint served, the requests to the blobs, the exported platform metrics and the audit records of the queries, and ends with the executions of the Function Apps and the requests of the endpoint read from the metrics API. |
| `cleanup.sh` | Deletes the resource group and the local zip artifact. |

## Notes

- The scripts read `az account show --query environmentName` and adjust two things for the emulator: the routes forward to the origins over plain HTTP, and the endpoint is called through its `*.afd.azure.localhost.localstack.cloud:4566` alias rather than its `*.azurefd.net` host name.
- `deploy.sh` supports both spellings of `az afd rule create`: the flattened arguments of Azure CLI 2.83 and earlier, and the `--conditions`/`--actions` shorthand of the `cdn` extension used from 2.85 on.
