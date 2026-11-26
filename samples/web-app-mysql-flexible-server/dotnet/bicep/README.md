# Bicep Deployment

This directory contains the Bicep template and a deployment script for provisioning the sample's Azure resources. For details about the sample application, see [Azure Web App with Azure Database for MySQL flexible server](../README.md).

## Prerequisites

- [LocalStack for Azure](https://docs.localstack.cloud/azure/)
- [Visual Studio Code](https://code.visualstudio.com/) + [Bicep extension](https://marketplace.visualstudio.com/items?itemName=ms-azuretools.vscode-bicep)
- [Docker](https://docs.docker.com/get-docker/)
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) + [lstk CLI](https://docs.localstack.cloud/aws/developer-tools/running-localstack/lstk/)
- [.NET SDK 10.0](https://dotnet.microsoft.com/en-us/download/dotnet/10.0)
- [MySQL client (`mysql`)](https://dev.mysql.com/downloads/)
- [`jq`](https://jqlang.org/)

```bash
brew install localstack/tap/lstk   # or: npm install -g @localstack/lstk
```

## Architecture Overview

The [`deploy.sh`](deploy.sh) script creates the resource group while the Bicep modules create:

1. [Azure Virtual Network](https://learn.microsoft.com/azure/virtual-network/virtual-networks-overview) with two subnets:
   - *app-subnet*: delegated to `Microsoft.Web/serverFarms` for the Web App's regional VNet integration.
   - *pe-subnet*: hosts the Private Endpoint to the MySQL flexible server.
2. [Azure Private DNS Zone](https://learn.microsoft.com/azure/dns/private-dns-privatednszone) `privatelink.mysql.database.azure.com`, linked to the VNet.
3. [Azure Private Endpoint](https://learn.microsoft.com/azure/private-link/private-endpoint-overview) (group `mysqlServer`).
4. [Azure NAT Gateway](https://learn.microsoft.com/azure/nat-gateway/nat-overview).
5. [Network Security Groups](https://learn.microsoft.com/en-us/azure/virtual-network/network-security-groups-overview): one per subnet.
6. [Azure Log Analytics Workspace](https://learn.microsoft.com/azure/azure-monitor/logs/log-analytics-overview), with a diagnostic setting that sends the audit records of the queries run on the workspace to the workspace itself.
7. [Azure Application Insights](https://learn.microsoft.com/en-us/azure/azure-monitor/app/app-insights-overview): workspace-based, it stores the telemetry of the web app in the Log Analytics workspace.
8. [Azure Database for MySQL flexible server](https://learn.microsoft.com/en-us/azure/mysql/flexible-server/overview): public-access mode, Burstable `Standard_B1ms`, version 8.0.21, 32 GiB, HA disabled. A permissive firewall rule (`0.0.0.0–255.255.255.255`) lets the deploy machine reach the server for the post-create mysql bootstrap. Its audit log is on for the connection events (the `audit_log_enabled` and `audit_log_events` server parameters).
9. [MySQL database](https://learn.microsoft.com/en-us/azure/mysql/flexible-server/how-to-create-manage-databases) `plannerdb` (utf8mb4 / `utf8mb4_unicode_ci`).
10. [Azure App Service Plan](https://learn.microsoft.com/en-us/azure/app-service/overview-hosting-plans).
11. [Azure Web App](https://learn.microsoft.com/en-us/azure/app-service/overview) with regional VNet integration into *app-subnet*. The Bicep template sets `MYSQL_HOST`, `MYSQL_PORT`, `MYSQL_DATABASE`, and `MYSQL_USER` / `MYSQL_PASSWORD` on the Web App, from the `mysqlAppUser` and `mysqlAppPassword` parameters: the application user that `deploy.sh` then creates with the mysql client. A second deployment leaves them as they are. The app setting `APPLICATIONINSIGHTS_CONNECTION_STRING` holds the connection string of the Application Insights resource.

## Configuration

Update [`main.bicepparam`](main.bicepparam) before deploying. The defaults are:

```bicep
using 'main.bicep'

param prefix = 'local'
param suffix = 'test'
param runtimeName = 'dotnetcore'
param runtimeVersion = '10.0'
param databaseName = 'plannerdb'
param username = 'paolo'

param mysqlAdminLogin = 'myadmin'
param mysqlAdminPassword = readEnvironmentVariable('MYSQL_ADMIN_PASSWORD', '')
param mysqlVersion = '8.0.21'
param mysqlSkuTier = 'Burstable'
param mysqlSkuName = 'Standard_B1ms'
param mysqlStorageSizeGB = 32
param mysqlBackupRetentionDays = 7
```

`mysqlAdminPassword` is read from the `MYSQL_ADMIN_PASSWORD` env var. `deploy.sh` sets a default (`P@ssw0rd1234!`) if not provided; override for non-dev deployments.

## Deployment

```bash
# default values
bash deploy.sh

# override admin and app-user secrets
MYSQL_ADMIN_PASSWORD='<your-admin-password>' \
MYSQL_APP_PASSWORD='<your-app-password>' \
bash deploy.sh
```

The script will:

1. Ensure the resource group exists.
2. Validate `main.bicep`.
3. Deploy the template, passing `mysqlAdminPassword`, `mysqlAppUser` and `mysqlAppPassword`.
4. Use the `mysql` client (connected via the public endpoint + firewall rule) to create the `testuser` user, the `activities` table, and the demo rows.
5. Zip the application source under `../src` and deploy it.

## Verification

```bash
MYSQL_PWD='TestP@ssw0rd123' mysql -h <fqdn> -P <port> -u testuser plannerdb \
  -e "SELECT id, username, activity, created_at FROM activities;"
```

`<port>` is `3306` in real Azure, or the port suffix of the server's FQDN in LocalStack:

```bash
az mysql flexible-server show \
  --resource-group local-rg --name local-mysqlflex-test \
  --query fullyQualifiedDomainName --output tsv
```

## Telemetry, logs and metrics

Once the web app is deployed, read the telemetry it sent to Application Insights and the logs and metrics the diagnostic settings sent to the workspace. The scripts take the same `PREFIX` and `SUFFIX` as the deployment:

```bash
bash ../scripts/query-telemetry.sh
bash ../scripts/query-logs-and-metrics.sh
```

See [Application Insights](../README.md#application-insights) and [Logs and metrics](../README.md#logs-and-metrics) for what they read.

## Related Documentation

- [LocalStack for Azure Documentation](https://docs.localstack.cloud/azure/)
- [lstk CLI](https://docs.localstack.cloud/aws/developer-tools/running-localstack/lstk/)
- [lstk GitHub repository](https://github.com/localstack/lstk)
