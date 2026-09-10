# Azure CLI Deployment

This directory contains Bash scripts for deploying and validating the sample using the `lstk` CLI. For details about the sample application, see [Azure Web App with Azure App Configuration and Azure Key Vault](../README.md).

## Prerequisites

- [LocalStack for Azure](https://docs.localstack.cloud/azure/)
- [Docker](https://docs.docker.com/get-docker/)
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) + [lstk CLI](https://docs.localstack.cloud/aws/developer-tools/running-localstack/lstk/)
- [Python 3.12+](https://www.python.org/downloads/)
- [PostgreSQL client (`psql`)](https://www.postgresql.org/download/)
- [`jq`](https://jqlang.org/)

```bash
brew install localstack/tap/lstk   # or: npm install -g @localstack/lstk
```

## Architecture Overview

[`deploy.sh`](deploy.sh) provisions the same resources as the Bicep and Terraform variants but with raw `az` commands. Every step is a get-or-create probe followed by the create, so the script can be re-run. It creates, in this order:

1. [Azure Resource Group](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/manage-resource-groups-cli).
2. [User-assigned managed identity](https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/overview) `<prefix>-identity-<suffix>` (`az identity create`), reading back its `clientId`, `principalId` and resource id.
3. [Azure App Configuration store](https://learn.microsoft.com/en-us/azure/azure-app-configuration/overview) `<prefix>-appconfig-<suffix>` (`az appconfig create --sku Standard --enable-public-network true`), after recovering a soft-deleted store of the same name (`az appconfig list-deleted`, `az appconfig recover`). Public network access is enabled explicitly because Azure disables it on a store that gets a private endpoint when the property was never set, and the `az appconfig kv` calls of this script run outside the virtual network. Its endpoint is read back with `az appconfig show --query endpoint`.
4. [Azure Key Vault](https://learn.microsoft.com/en-us/azure/key-vault/general/overview) `<prefix>-keyvault-<suffix>` with the RBAC permission model (`az keyvault create --enable-rbac-authorization true`), after recovering a soft-deleted vault of the same name (`az keyvault list-deleted`, `az keyvault recover`). Its URI is read back with `az keyvault show --query properties.vaultUri`.
5. The [Key Vault Secrets Officer](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/security#key-vault-secrets-officer) role assignment for the deploying principal on the vault, so the next step can write secrets on an RBAC vault. The principal's object id comes from `az ad signed-in-user show` (users) or `az ad sp show --id <appId>` (service principals); when it cannot be resolved the script warns and continues, and the role becomes a prerequisite.
6. The secrets `pg-user` and `pg-password` (`az keyvault secret set`, retried while the role assignment propagates), holding the credentials of the PostgreSQL application role. The values are never printed.
7. The identity's role assignments: [App Configuration Data Reader](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/integration#app-configuration-data-reader) on the store and [Key Vault Secrets User](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/security#key-vault-secrets-user) on the vault (`az role assignment create --assignee-object-id <principalId> --assignee-principal-type ServicePrincipal`, checked first with `az role assignment list`).
8. [Azure Database for PostgreSQL flexible server](https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/overview): public-access mode, `Burstable / Standard_B1ms`, version 16, 32 GiB, HA disabled, with the permissive `AllowAllIPs` firewall rule and the `PlannerDB` [database](https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/concepts-servers). The server FQDN is split into host and port: the emulator embeds its TCP-proxy port in the FQDN, Azure returns the bare host and the port defaults to `5432`.
9. The five key-values of the store: `PG_HOST`, `PG_PORT` and `PG_DATABASE` as plain values (`az appconfig kv set`), `PG_USER` and `PG_PASSWORD` as Key Vault references to the two secrets (`az appconfig kv set-keyvault --secret-identifier <vault URI>/secrets/<name>`, versionless so the reference follows the latest version). Each write is skipped when the store already holds the same value.
10. [Network Security Groups](https://learn.microsoft.com/en-us/azure/virtual-network/network-security-groups-overview) for both subnets.
11. [Azure NAT Gateway](https://learn.microsoft.com/azure/nat-gateway/nat-overview) with its public IP prefix.
12. [Azure Virtual Network](https://learn.microsoft.com/azure/virtual-network/virtual-networks-overview) with:
    - *app-subnet*: delegated to `Microsoft.Web/serverFarms` (with NAT gateway).
    - *pe-subnet*: hosts the three Private Endpoints (no delegation; private endpoint network policies disabled).
13. Three [Azure Private DNS Zones](https://learn.microsoft.com/azure/dns/private-dns-privatednszone), `privatelink.postgres.database.azure.com`, `privatelink.azconfig.io` and `privatelink.vaultcore.azure.net`, each linked to the VNet as `link-to-vnet`, and three [Azure Private Endpoints](https://learn.microsoft.com/azure/private-link/private-endpoint-overview), `<prefix>-postgres-pe-<suffix>` (group `postgresqlServer`), `<prefix>-appconfig-pe-<suffix>` (group `configurationStores`) and `<prefix>-keyvault-pe-<suffix>` (group `vault`), each with a `default` DNS zone group that registers its A record.
14. A separate application role (`testuser`) created via `psql`, with the minimum schema privileges on `PlannerDB`, the `activities` table and the seeded rows.
15. [Azure App Service Plan](https://learn.microsoft.com/en-us/azure/app-service/overview-hosting-plans).
16. [Azure Web App](https://learn.microsoft.com/en-us/azure/app-service/overview) with regional VNet integration into *app-subnet*, forced tunneling, the user-assigned managed identity (`az webapp create --assign-identity <identity id>`), and the app settings `Endpoints__AppConfiguration` (the store endpoint), `AZURE_CLIENT_ID` (the identity client id), `LOGIN_NAME`, `WEBSITES_PORT`, `SCM_DO_BUILD_DURING_DEPLOYMENT` and `ENABLE_ORYX_BUILD`. No `PG_*` setting: the app loads them from the store.
17. [Azure Log Analytics Workspace](https://learn.microsoft.com/azure/azure-monitor/logs/log-analytics-overview) and the diagnostic settings of the web app, the plan, the PostgreSQL server, the App Configuration store, the Key Vault, the VNet and the two NSGs.
18. The zip deployment of the application code (`az webapp deploy --type zip`).

The Web App uses `testuser`; neither the server-admin login nor the application credentials are written into the Web App's app settings. Use [`validate.sh`](validate.sh) after `deploy.sh` to inspect each Azure resource: it lists the store, its key-values with their content types, the vault and its secret names, the identity, the two role assignments, the three Private DNS Zones, links, Private Endpoints and zone groups, and it exits with a non-zero code if the Web App has any `PG_*` app setting or lacks `Endpoints__AppConfiguration` or `AZURE_CLIENT_ID`.

## Usage

```bash
# default names and secrets
bash deploy.sh

# your own suffix (the store and vault names are globally unique on Azure) and secrets
SUFFIX='<unique>' \
PG_ADMIN_PASSWORD='<admin-password>' \
PG_APP_PASSWORD='<app-password>' \
bash deploy.sh

# inspect what was deployed
bash validate.sh
```

`deploy.sh` and `validate.sh` accept the following environment overrides:

| Env var              | Default            | Description                                                                 |
| -------------------- | ------------------ | --------------------------------------------------------------------------- |
| `PREFIX`             | `local`            | Prefix of every resource name (the resource group is `<prefix>-rg`)         |
| `SUFFIX`             | `test`             | Suffix of every resource name; pick your own on Azure                       |
| `LOCATION`           | `westeurope`       | Azure region                                                                |
| `APP_CONFIG_SKU`     | `Standard`         | App Configuration tier (private endpoints need Developer, Standard or Premium) |
| `PG_ADMIN_USER`      | `pgadmin`          | Server administrator login                                                  |
| `PG_ADMIN_PASSWORD`  | `P@ssw0rd1234!`    | Server administrator password (sensitive)                                   |
| `PG_DATABASE_NAME`   | `PlannerDB`        | Application database                                                        |
| `PG_APP_USER`        | `testuser`         | Application role used by the Web App, stored as the `pg-user` secret        |
| `PG_APP_PASSWORD`    | `TestP@ssw0rd123`  | Password for the application role, stored as the `pg-password` secret       |
| `LOGIN_NAME`         | `paolo`            | User whose activities the app shows                                         |
| `DEPLOY_APP`         | `1`                | Set to `0` to skip the zip deployment step                                  |

The script uses [`call-web-app.sh`](call-web-app.sh) (unchanged from the source sample) to demonstrate four ways of hitting the Web App from outside the emulator.

## Related Documentation

- [Azure CLI reference: az appconfig kv](https://learn.microsoft.com/en-us/cli/azure/appconfig/kv)
- [Azure CLI reference: az keyvault secret](https://learn.microsoft.com/en-us/cli/azure/keyvault/secret)
- [Azure CLI reference: az role assignment](https://learn.microsoft.com/en-us/cli/azure/role/assignment)
- [LocalStack for Azure Documentation](https://docs.localstack.cloud/azure/)
- [lstk CLI](https://docs.localstack.cloud/aws/developer-tools/running-localstack/lstk/)
- [lstk GitHub repository](https://github.com/localstack/lstk)
