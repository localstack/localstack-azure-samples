# Bicep Deployment

This directory contains the Bicep template and a deployment script for provisioning the sample's Azure resources. For details about the sample application, see [Azure Web App with Azure App Configuration and Azure Key Vault](../README.md).

## Prerequisites

- [LocalStack for Azure](https://docs.localstack.cloud/azure/)
- [Visual Studio Code](https://code.visualstudio.com/) + [Bicep extension](https://marketplace.visualstudio.com/items?itemName=ms-azuretools.vscode-bicep)
- [Docker](https://docs.docker.com/get-docker/)
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) + [lstk CLI](https://docs.localstack.cloud/aws/developer-tools/running-localstack/lstk/)
- [.NET SDK 10.0](https://dotnet.microsoft.com/en-us/download/dotnet/10.0)
- [PostgreSQL client (`psql`)](https://www.postgresql.org/download/)
- [`jq`](https://jqlang.org/)

```bash
brew install localstack/tap/lstk   # or: npm install -g @localstack/lstk
```

## Architecture Overview

The [`deploy.sh`](deploy.sh) script creates the resource group while the Bicep modules create:

1. [Azure Virtual Network](https://learn.microsoft.com/azure/virtual-network/virtual-networks-overview) (`virtual-network.bicep`) with two subnets:
   - *app-subnet*: delegated to `Microsoft.Web/serverFarms` for the Web App's regional VNet integration.
   - *pe-subnet*: hosts the three Private Endpoints.
2. [User-assigned managed identity](https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/overview) (`managed-identity.bicep`) `<prefix>-identity-<suffix>`.
3. [Azure Database for PostgreSQL flexible server](https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/overview) (`postgresql-flexible-server.bicep`): public-access mode, Burstable `Standard_B1ms`, version 16, 32 GiB, HA disabled, the permissive firewall rule for the post-deploy psql bootstrap and the `PlannerDB` [database](https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/concepts-servers) (UTF8 / `en_US.utf8`).
4. [Azure Key Vault](https://learn.microsoft.com/en-us/azure/key-vault/general/overview) (`key-vault.bicep`) `<prefix>-keyvault-<suffix>` with `enableRbacAuthorization: true`, soft delete (7 days) and no purge protection; the two `Microsoft.KeyVault/vaults/secrets` children `pg-user` and `pg-password` created from the `pgAppUser` and `@secure() pgAppPassword` parameters; the [Key Vault Secrets User](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/security#key-vault-secrets-user) role assignment for the identity; an optional Key Vault Secrets Officer assignment for the deploying principal (`deployerPrincipalId`); and its diagnostic settings. The module outputs the versionless secret identifiers, assembled from the vault URI plus `secrets/<name>` the way the Azure CLI variant does (the emulator does not return the `secretUri` property of the secret resource today, see the module comments).
5. [Azure App Configuration store](https://learn.microsoft.com/en-us/azure/azure-app-configuration/overview) (`app-configuration.bicep`) `<prefix>-appconfig-<suffix>`, Standard SKU, with `disableLocalAuth: false` and public network access enabled; the five `Microsoft.AppConfiguration/configurationStores/keyValues` children, created in a loop over the `keyValues` array `main.bicep` assembles from the PostgreSQL and Key Vault module outputs: `PG_HOST`, `PG_PORT` and `PG_DATABASE` as plain values and `PG_USER` and `PG_PASSWORD` with the content type `application/vnd.microsoft.appconfig.keyvaultref+json;charset=utf-8` and the value `{"uri":"<secret identifier>"}`; the [App Configuration Data Reader](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/integration#app-configuration-data-reader) role assignment for the identity; and its diagnostic settings.
6. Three [Azure Private DNS Zones](https://learn.microsoft.com/azure/dns/private-dns-privatednszone) (`private-dns-zone.bicep`), `privatelink.postgres.database.azure.com`, `privatelink.azconfig.io` and `privatelink.vaultcore.azure.net`, each linked to the VNet as `link-to-vnet`.
7. Three [Azure Private Endpoints](https://learn.microsoft.com/azure/private-link/private-endpoint-overview) (`private-endpoint.bicep`), groups `postgresqlServer`, `configurationStores` and `vault`, each with a `default` DNS zone group.
8. [Azure NAT Gateway](https://learn.microsoft.com/azure/nat-gateway/nat-overview) and one [Network Security Group](https://learn.microsoft.com/en-us/azure/virtual-network/network-security-groups-overview) per subnet (inside `virtual-network.bicep`).
9. [Azure Log Analytics Workspace](https://learn.microsoft.com/azure/azure-monitor/logs/log-analytics-overview) (`log-analytics.bicep`).
10. [Azure App Service Plan](https://learn.microsoft.com/en-us/azure/app-service/overview-hosting-plans) (`app-service-plan.bicep`).
11. [Azure Web App](https://learn.microsoft.com/en-us/azure/app-service/overview) (`web-app.bicep`) with regional VNet integration into *app-subnet*, the user-assigned identity, and the app settings `Endpoints__AppConfiguration` (the store endpoint) and `AZURE_CLIENT_ID` (the identity client id) next to `LOGIN_NAME`, `WEBSITES_PORT` and the Oryx build flags. The template sets **no** `PG_*` app setting: the app loads the five settings from the store.

Two remarks about the store's key-values:

- The `keyValues` children are written through Azure Resource Manager, which authorizes them with the store's [Azure Resource Manager authentication mode](https://learn.microsoft.com/en-us/azure/azure-app-configuration/quickstart-deployment-overview). The store keeps the default `Local` mode and access keys enabled, so the deploying principal only needs Contributor. If you disable access keys, switch the store to `Pass-through` and grant the deploying principal App Configuration Data Owner, otherwise the key-value writes fail on Azure.
- The Key Vault reference values are built with string interpolation (`'{"uri":"${uri}"}'`) rather than `string({ uri: uri })`: the result is the same JSON on Azure, while the LocalStack emulator's template engine renders `string()` of an object as a Python dictionary today.

## Configuration

Update [`main.bicepparam`](main.bicepparam) before deploying. The defaults are:

```bicep
using 'main.bicep'

param prefix = 'local'
param suffix = 'test'
param runtimeName = 'dotnetcore'
param runtimeVersion = '10.0'
param databaseName = 'PlannerDB'
param username = 'paolo'

param pgAdminLogin = 'pgadmin'
param pgAdminPassword = readEnvironmentVariable('PG_ADMIN_PASSWORD', '')
param pgVersion = '16'
param pgSkuTier = 'Burstable'
param pgSkuName = 'Standard_B1ms'
param pgStorageSizeGB = 32
param pgBackupRetentionDays = 7

param pgAppUser = 'testuser'
param pgAppPassword = readEnvironmentVariable('PG_APP_PASSWORD', '')

param appConfigurationSku = 'Standard'
param keyVaultSkuName = 'standard'
```

`pgAdminPassword` and `pgAppPassword` are the secure parameters that carry the two passwords; `deploy.sh` reads them from the `PG_ADMIN_PASSWORD` and `PG_APP_PASSWORD` env vars (with development defaults) and passes them on the command line together with `prefix`, `suffix`, `location`, `pgAdminLogin`, `pgAppUser`, `deployerPrincipalId` and `deployerPrincipalType`. Override for non-dev deployments. The store and vault names are globally unique on Azure, so export your own `SUFFIX`.

## Deployment

```bash
# default values
bash deploy.sh

# your own suffix and secrets
SUFFIX='<unique>' \
PG_ADMIN_PASSWORD='<your-admin-password>' \
PG_APP_PASSWORD='<your-app-password>' \
bash deploy.sh

# preview the changes of a re-deployment instead of validating the template
USE_WHAT_IF=1 bash deploy.sh
```

The script will:

1. Ensure the resource group exists.
2. Recover a soft-deleted App Configuration store or Key Vault of the same name, so a re-deployment after a cleanup does not fail on a reserved name.
3. Resolve the object id of the deploying principal (skipped with a warning when Microsoft Graph cannot resolve it).
4. Validate `main.bicep` (or run a what-if with `USE_WHAT_IF=1`).
5. Deploy the template, passing the parameters above.
6. Check that the store holds the five expected key-values.
7. Wait for the `PlannerDB` database to accept connections, then use `psql` (connected via the public endpoint and the firewall rule) to create the `testuser` role, the `activities` table and the demo rows. The role name and password are the values already stored in Key Vault; nothing is written to the Web App's app settings.
8. Print the key-values with their content types and the Web App's app settings.
9. Zip the application source under `../src` and deploy it.

`deploy.sh` accepts the same environment overrides as the Azure CLI variant: `PREFIX`, `SUFFIX`, `LOCATION`, `PG_ADMIN_USER`, `PG_ADMIN_PASSWORD`, `PG_APP_USER`, `PG_APP_PASSWORD`, `DEPLOY_APP`, plus `VALIDATE_TEMPLATE` and `USE_WHAT_IF`.

### Alternative: seeding the key-values from deploy.sh

The template creates the key-values itself, which keeps the whole topology in one deployment. If the `keyValues` children ever prove unreliable on one of the targets (for example because access keys are disabled and the store's Azure Resource Manager authentication mode is still `Local`), the same key-values can be seeded from `deploy.sh` after the deployment, the way the Azure CLI variant does:

1. Remove the `keyValues` resource and the `keyValues` parameter from `modules/app-configuration.bicep`, and the `appConfigurationKeyValues` variable from `main.bicep`. Never keep both: two owners of the same key-value drift on every deployment.
2. After the deployment, read the outputs `appConfigurationName`, `keyVaultUri`, `postgresFqdn` and `databaseName` and run, once per key, `az appconfig kv set --name <store> --key PG_HOST --value <host> --yes` (and `PG_PORT`, `PG_DATABASE`) and `az appconfig kv set-keyvault --name <store> --key PG_USER --secret-identifier <vault URI>/secrets/pg-user --yes` (and `PG_PASSWORD`), probing each key with `az appconfig kv show` first so the step stays idempotent.
3. The seeded key-values must match the template's exactly (keys, no label, content types, values), so `validate.sh` and the app behave the same. The commands use the data plane: they need access keys enabled (the default) or `--auth-mode login` with App Configuration Data Owner.

This alternative was not needed during the development of the sample: the template path works on the emulator and on Azure.

## Verification

```bash
PGPASSWORD='TestP@ssw0rd123' psql -h <fqdn> -p <port> -U testuser -d PlannerDB \
  -c "SELECT id, username, activity, created_at FROM activities;"

az appconfig kv list --name local-appconfig-test \
  --query "[].{Key:key,ContentType:contentType,Label:label}" --output table
az keyvault secret list --vault-name local-keyvault-test --query "[].name" --output tsv
az webapp config appsettings list --name local-webapp-test --resource-group local-rg \
  --query "[?starts_with(name, 'PG_')].name" --output tsv
bash ../scripts/validate.sh
```

`<port>` is `5432` in real Azure, or the port suffix of the server's FQDN in LocalStack:

```bash
az postgres flexible-server show \
  --resource-group local-rg --name local-pgflex-test \
  --query fullyQualifiedDomainName --output tsv
```

## Related Documentation

- [Microsoft.AppConfiguration configurationStores/keyValues (Bicep)](https://learn.microsoft.com/en-us/azure/templates/microsoft.appconfiguration/configurationstores/keyvalues)
- [Microsoft.KeyVault vaults/secrets (Bicep)](https://learn.microsoft.com/en-us/azure/templates/microsoft.keyvault/vaults/secrets)
- [Deployment overview: roles and Azure Resource Manager authentication mode](https://learn.microsoft.com/en-us/azure/azure-app-configuration/quickstart-deployment-overview)
- [LocalStack for Azure Documentation](https://docs.localstack.cloud/azure/)
- [lstk CLI](https://docs.localstack.cloud/aws/developer-tools/running-localstack/lstk/)
- [lstk GitHub repository](https://github.com/localstack/lstk)
