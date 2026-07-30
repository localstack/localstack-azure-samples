# Bicep deployment

Provisions the payment fraud detection pipeline with a Bicep template, then publishes the
application code with the Azure CLI.

## Prerequisites

- The LocalStack Azure emulator is running and `lstk az start-interception` has been run.
- The Bicep CLI (`az bicep install`) and `jq` are available.

## Usage

```bash
cd samples/eventhubs/python/bicep
bash deploy.sh
```

`deploy.sh` creates the resource group, validates and deploys `main.bicep`, reads the
outputs, wires the connection strings, zip-deploys the Function App and the Web App, and
verifies the payments hub.

### Why the connection strings are set by the script, not the template

Anything a template emits as an output is retained in the deployment history, so this sample
keeps keys out of the template entirely: `deploy.sh` reads them with
`az ... authorization-rule keys list` once the resources exist and writes them straight into
Key Vault and the app settings. The storage connection string is assembled from the
account's own endpoints, because the Azure Functions host cannot parse the `EndpointSuffix`
form when the suffix carries a port.

## Template layout

| File | Contents |
|------|----------|
| `main.bicep` | Parameters, names, and the module graph |
| `main.bicepparam` | Parameter values for the sample |
| `modules/storage.bicep` | Storage account and the Capture container |
| `modules/event-hubs.bicep` | Namespace, both hubs, Capture, consumer groups, authorization rules, schema group |
| `modules/key-vault.bicep` | Key vault (the secrets themselves are written by `deploy.sh`) |
| `modules/monitoring.bicep` | Log Analytics workspace and Application Insights |
| `modules/workloads.bicep` | App Service plans, the Function App and the Web App |

## Parameters

| Parameter | Default | Notes |
|-----------|---------|-------|
| `prefix` / `suffix` | `local` / `payments` | Compose every resource name |
| `eventHubSkuName` | `Standard` | Capture and Kafka need Standard or higher |
| `partitionCount` | `4` | Partitions are the unit of parallelism and of ordering |
| `retentionTimeInHours` | `24` | Standard tier allows up to 7 days |
| `captureIntervalInSeconds` | `60` | Minimum allowed by Azure |
| `fraudAmountThreshold` | `5000` | A single payment at or above this is flagged |
| `fraudVelocityCount` | `5` | Payments per account per window before flagging |

## Outputs

`main.bicep` returns the resource names and the dashboard URL:

```bash
az deployment group show \
  --name eventhubs-fraud-detection \
  --resource-group local-eventhubs-rg \
  --query properties.outputs
```
