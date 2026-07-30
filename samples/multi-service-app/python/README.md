# Multi-Service App: URL Shortener with Web App, Functions, Storage, Key Vault, Service Bus and PostgreSQL

This sample demonstrates *Linklet*, a Python Flask URL shortener hosted on an [Azure Web App](https://learn.microsoft.com/en-us/azure/app-service/overview) with an event-driven worker on [Azure Functions](https://learn.microsoft.com/en-us/azure/azure-functions/functions-overview). Unlike the sibling samples, which each exercise one or two services, this sample composes seven services into a single causal chain: every shortened link fans out through [Azure Service Bus](https://learn.microsoft.com/en-us/azure/service-bus-messaging/service-bus-messaging-overview) and [Azure Queue Storage](https://learn.microsoft.com/en-us/azure/storage/queues/storage-queues-introduction) to background workers, and every redirect is logged to an [Azure Database for PostgreSQL flexible server](https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/overview). It is intended as a realistic end-to-end workout for the LocalStack Azure emulator: a regression in any one service breaks an observable user outcome.

## Architecture

The solution is composed of the following Azure resources:

1. [Azure Resource Group](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/manage-resource-groups-cli): A logical container scoping all resources in this sample.
2. [Azure User-Assigned Managed Identity](https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/overview): Shared by the web app and the worker; all Storage and Key Vault data-plane calls are credential-free through it.
3. [Azure Storage Account](https://learn.microsoft.com/en-us/azure/storage/common/storage-account-overview) with three data planes:
   - *links* [Table](https://learn.microsoft.com/en-us/azure/storage/tables/table-storage-overview): The link store (code, target URL, hit counter, signature, scan verdict, QR status).
   - *qrjobs* [Queue](https://learn.microsoft.com/en-us/azure/storage/queues/storage-queues-introduction): QR-render jobs consumed by the worker's queue trigger.
   - *qrcodes* [Blob container](https://learn.microsoft.com/en-us/azure/storage/blobs/storage-blobs-introduction) (public read): The rendered QR SVGs.
4. [Azure Key Vault](https://learn.microsoft.com/en-us/azure/key-vault/general/overview) (RBAC mode): Holds the HMAC key that signs every short code and the PostgreSQL connection string; the app reads both at runtime through the managed identity.
5. [Azure Database for PostgreSQL flexible server](https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/overview): The `clicks` database receives one row per redirect (burstable `Standard_B1ms`, version 16).
6. [Azure Service Bus](https://learn.microsoft.com/en-us/azure/service-bus-messaging/service-bus-messaging-overview) (Standard): The *link-events* queue carries link-created events to the abuse-scan worker.
7. [Azure Log Analytics Workspace](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/log-analytics-overview): Receives the storage account's transaction metrics through diagnostic settings.
8. [Azure App Service Plan](https://learn.microsoft.com/en-us/azure/app-service/overview-hosting-plans) (Linux, B1): Hosts both compute components.
9. [Azure Web App](https://learn.microsoft.com/en-us/azure/app-service/overview): The Flask UI/API. `POST /shorten` writes the link, signs the code with the Key Vault key, sends a Service Bus event and enqueues a QR job; `GET /l/<code>` bumps the hit counter, logs the click to PostgreSQL and redirects.
10. [Azure Function App](https://learn.microsoft.com/en-us/azure/azure-functions/functions-overview) (Python v2 model): Two event-driven workers that call back into the web app's token-protected internal API:
    - *AbuseScan* ([Service Bus trigger](https://learn.microsoft.com/en-us/azure/azure-functions/functions-bindings-service-bus-trigger), identity-based connection): Applies a keyword heuristic and reports a `clean`/`flagged` verdict.
    - *QrGenerator* ([Queue Storage trigger](https://learn.microsoft.com/en-us/azure/azure-functions/functions-bindings-storage-queue-trigger)): Requests the QR SVG render for the short link.

The flow of a single link: `POST /shorten` → Table Storage + Key Vault + Service Bus + Queue Storage → workers → internal API → Table Storage + Blob Storage → `GET /l/<code>` → PostgreSQL + 302 redirect. The home page renders the link table with hit counts, signatures, scan verdicts and QR links.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/)
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)
- [lstk CLI](https://docs.localstack.cloud/aws/developer-tools/running-localstack/lstk/)
- [jq](https://jqlang.org/) and `zip`
- [psql](https://www.postgresql.org/docs/current/app-psql.html) (PostgreSQL client, used by the validation script)
- [Terraform](https://developer.hashicorp.com/terraform/downloads) (for the Terraform deployment)
- [Bicep](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/install) (for the Bicep deployment)
- A LocalStack account with a valid `LOCALSTACK_AUTH_TOKEN` (see the [Auth Token guide](https://docs.localstack.cloud/getting-started/auth-token/))

## Setup

Start the LocalStack Azure emulator and route the Azure CLI to it:

```bash
export LOCALSTACK_AUTH_TOKEN=<your_auth_token>
IMAGE_NAME=localstack/localstack-azure localstack start -d
localstack wait -t 60
lstk az start-interception
az login --service-principal -u any-app -p any-pass --tenant any-tenant
```

## Deployment

### Azure CLI scripts

```bash
bash scripts/deploy.sh
```

The script provisions all resources idempotently, deploys both applications from zip packages and persists the generated PostgreSQL credentials to `scripts/.last_deploy.env` for the validation script.

### Terraform

```bash
cd terraform
bash deploy.sh
```

The Terraform variant provisions the same resources declaratively and then performs the two zip deployments with the Azure CLI.

### Bicep

```bash
cd bicep
bash deploy.sh
```

The Bicep variant validates and deploys `main.bicep` into the resource group and then performs the two zip deployments with the Azure CLI.

## Testing

```bash
bash scripts/validate.sh
bash scripts/call-web-app.sh
```

`validate.sh` walks the full causal chain: web app health (Table Storage + Key Vault + PostgreSQL through the managed identity), shortening a benign and a suspicious URL, the AbuseScan verdicts arriving via the Service Bus trigger, the QR SVG rendered via the queue trigger and served from the public blob container, redirects logging click rows into PostgreSQL, hit counting in Table Storage, and the Log Analytics wiring. `call-web-app.sh` performs a quick user-level smoke test (home page, shorten, redirect).

You can also open the web app in a browser — the URL is printed at the end of the deploy script.

## Cleanup

```bash
az group delete --name local-rg --yes
```

## LocalStack notes

- The web app talks to Service Bus through the namespace connection string rather than a managed-identity connection: the Python Service Bus SDK enforces TLS verification and the emulator's certificate does not cover `*.servicebus.windows.net`. The connection string's endpoint is certificate-valid on both the emulator and real Azure.
- The worker's queue trigger uses a dedicated connection string with explicit `BlobEndpoint`/`QueueEndpoint`/`TableEndpoint` entries because strict .NET storage clients cannot parse an `EndpointSuffix` that carries the emulator's port.
- The PostgreSQL flexible-server emulator embeds its TCP-proxy port in the server's `fullyQualifiedDomainName`; both deployment variants split host and port so the same configuration works against real Azure (bare host, port 5432).
- On real Azure, additionally enable *Always On* for the function app (dedicated plans idle otherwise and non-HTTP triggers stop firing) and deploy the function app through a build-enabled path (Oryx remote build or a vendored `.python_packages` layout).
