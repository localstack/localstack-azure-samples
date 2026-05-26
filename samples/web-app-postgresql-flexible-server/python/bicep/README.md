# Bicep Deployment

This directory contains the Bicep template and a deployment script for provisioning the sample's Azure resources. For details about the sample application, see [Azure Web App with Azure Database for PostgreSQL flexible server](../README.md).

## Prerequisites

- [LocalStack for Azure](https://docs.localstack.cloud/azure/)
- [Visual Studio Code](https://code.visualstudio.com/) + [Bicep extension](https://marketplace.visualstudio.com/items?itemName=ms-azuretools.vscode-bicep)
- [Docker](https://docs.docker.com/get-docker/)
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) + [Azlocal CLI](https://azure.localstack.cloud/user-guides/sdks/az/)
- [Python 3.12+](https://www.python.org/downloads/)
- [PostgreSQL client (`psql`)](https://www.postgresql.org/download/)
- [`jq`](https://jqlang.org/)

```bash
pip install azlocal
```

## Architecture Overview

The [`deploy.sh`](deploy.sh) script creates the resource group while the Bicep modules create:

1. [Azure Virtual Network](https://learn.microsoft.com/azure/virtual-network/virtual-networks-overview) with two subnets:
   - *app-subnet*: delegated to `Microsoft.Web/serverFarms` for the Web App's regional VNet integration.
   - *pe-subnet*: hosts the Private Endpoint to the PostgreSQL flexible server.
2. [Azure Private DNS Zone](https://learn.microsoft.com/azure/dns/private-dns-privatednszone) `privatelink.postgres.database.azure.com`, linked to the VNet.
3. [Azure Private Endpoint](https://learn.microsoft.com/azure/private-link/private-endpoint-overview) (group `postgresqlServer`).
4. [Azure NAT Gateway](https://learn.microsoft.com/azure/nat-gateway/nat-overview).
5. [Network Security Groups](https://learn.microsoft.com/en-us/azure/virtual-network/network-security-groups-overview): one per subnet.
6. [Azure Log Analytics Workspace](https://learn.microsoft.com/azure/azure-monitor/logs/log-analytics-overview).
7. [Azure Database for PostgreSQL flexible server](https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/overview): public-access mode, Burstable `Standard_B1ms`, version 16, 32 GiB, HA disabled. A permissive firewall rule (`0.0.0.0–255.255.255.255`) lets the deploy machine reach the server for the post-create psql bootstrap.
8. [PostgreSQL database](https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/concepts-server-and-database) `sampledb` (UTF8 / `en_US.utf8`).
9. [Azure App Service Plan](https://learn.microsoft.com/en-us/azure/app-service/overview-hosting-plans).
10. [Azure Web App](https://learn.microsoft.com/en-us/azure/app-service/overview) with regional VNet integration into *app-subnet*. The Bicep template sets `PG_HOST`, `PG_PORT`, and `PG_DATABASE` on the Web App but **does not** set `PG_USER` or `PG_PASSWORD` — those are written by `deploy.sh` after psql creates the application role.

## Configuration

Update [`main.bicepparam`](main.bicepparam) before deploying. The defaults are:

```bicep
using 'main.bicep'

param prefix = 'local'
param suffix = 'test'
param runtimeName = 'python'
param runtimeVersion = '3.13'
param databaseName = 'sampledb'
param username = 'paolo'

param pgAdminLogin = 'pgadmin'
param pgAdminPassword = readEnvironmentVariable('PG_ADMIN_PASSWORD', '')
param pgVersion = '16'
param pgSkuTier = 'Burstable'
param pgSkuName = 'Standard_B1ms'
param pgStorageSizeGB = 32
param pgBackupRetentionDays = 7
```

`pgAdminPassword` is read from the `PG_ADMIN_PASSWORD` env var. `deploy.sh` sets a default (`P@ssw0rd1234!`) if not provided; override for non-dev deployments.

## Deployment

```bash
# default values
bash deploy.sh

# override admin and app-user secrets
PG_ADMIN_PASSWORD='<your-admin-password>' \
PG_APP_PASSWORD='<your-app-password>' \
bash deploy.sh
```

The script will:

1. Ensure the resource group exists.
2. Validate `main.bicep`.
3. Deploy the template, passing `pgAdminPassword`.
4. Use `psql` (connected via the public endpoint + firewall rule) to create the `testuser` role, the `activities` table, and the three demo rows.
5. Set the Web App's `PG_USER`/`PG_PASSWORD` to `testuser` / `<app-password>` — the server admin login is never written to the Web App.
6. Zip the application source under `../src` and deploy it.

## Verification

```bash
PGPASSWORD='TestP@ssw0rd123' psql -h <fqdn> -p <port> -U testuser -d PlannerDB \
  -c "SELECT id, username, activity, created_at FROM activities;"
```

`<port>` is `5432` in real Azure, or the port suffix of the server's FQDN in LocalStack:

```bash
az postgres flexible-server show \
  --resource-group local-rg --name local-pgflex-test \
  --query fullyQualifiedDomainName --output tsv
```
