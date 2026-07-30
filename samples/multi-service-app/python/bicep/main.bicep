//********************************************
// Parameters
//********************************************

@description('Prefix applied to every resource name in this sample.')
param prefix string = 'local'

@description('Suffix applied to every resource name in this sample.')
param suffix string = 'test'

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Runtime of the web app and the worker.')
param runtimeName string = 'python'

@description('Runtime version of the web app.')
param webRuntimeVersion string = '3.13'

@description('Runtime version of the worker function app.')
param functionRuntimeVersion string = '3.11'

@description('Administrator login of the PostgreSQL flexible server.')
param postgresAdminLogin string = 'linkletadmin'

@description('Administrator password of the PostgreSQL flexible server.')
@secure()
param postgresAdminPassword string

@description('HMAC key used by the web app to sign short codes; stored in Key Vault.')
@secure()
param signKey string

@description('Shared token protecting the web app internal API called by the worker.')
@secure()
param internalToken string

//********************************************
// Variables
//********************************************

var storageAccountName = '${prefix}msastorage${suffix}'
var keyVaultName = '${prefix}-msa-kv-${suffix}'
var postgresServerName = '${prefix}-msa-pgflex-${suffix}'
var servicebusNamespaceName = '${prefix}-msa-sb-ns-${suffix}'
var logAnalyticsName = '${prefix}-msa-log-analytics-${suffix}'
var appServicePlanName = '${prefix}-msa-app-service-plan-${suffix}'
var webAppName = '${prefix}-msa-webapp-${suffix}'
var functionAppName = '${prefix}-msa-functionapp-${suffix}'
var managedIdentityName = '${prefix}-msa-identity-${suffix}'
var linksTableName = 'links'
var qrJobsQueueName = 'qrjobs'
var qrContainerName = 'qrcodes'
var servicebusQueueName = 'link-events'
var postgresDatabaseName = 'clicks'

//********************************************
// Built-in role definitions
//********************************************

resource storageTableDataContributorRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3'
  scope: subscription()
}

resource storageQueueDataContributorRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: '974c5e8b-45b9-4653-ba55-5f855dd0fb88'
  scope: subscription()
}

resource storageBlobDataContributorRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
  scope: subscription()
}

resource keyVaultSecretsUserRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: '4633458b-17de-408a-b874-0445c86b69e6'
  scope: subscription()
}

resource serviceBusDataSenderRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: '69a216fc-b8fb-44d8-bc22-1f3c2cd27a39'
  scope: subscription()
}

resource serviceBusDataReceiverRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: '4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0'
  scope: subscription()
}

//********************************************
// Identity
//********************************************

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: managedIdentityName
  location: location
}

//********************************************
// Storage: table (links store), queue (QR render jobs), blob (QR images)
//********************************************

resource storageAccount 'Microsoft.Storage/storageAccounts@2025-01-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
}

resource tableService 'Microsoft.Storage/storageAccounts/tableServices@2025-01-01' = {
  parent: storageAccount
  name: 'default'
}

resource linksTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2025-01-01' = {
  parent: tableService
  name: linksTableName
}

resource queueService 'Microsoft.Storage/storageAccounts/queueServices@2025-01-01' = {
  parent: storageAccount
  name: 'default'
}

resource qrJobsQueue 'Microsoft.Storage/storageAccounts/queueServices/queues@2025-01-01' = {
  parent: queueService
  name: qrJobsQueueName
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2025-01-01' = {
  parent: storageAccount
  name: 'default'
}

resource qrContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2025-01-01' = {
  parent: blobService
  name: qrContainerName
  properties: {
    publicAccess: 'Blob'
  }
}

resource storageTableRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, managedIdentity.id, storageTableDataContributorRoleDefinition.id)
  scope: storageAccount
  properties: {
    roleDefinitionId: storageTableDataContributorRoleDefinition.id
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource storageQueueRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, managedIdentity.id, storageQueueDataContributorRoleDefinition.id)
  scope: storageAccount
  properties: {
    roleDefinitionId: storageQueueDataContributorRoleDefinition.id
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource storageBlobRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, managedIdentity.id, storageBlobDataContributorRoleDefinition.id)
  scope: storageAccount
  properties: {
    roleDefinitionId: storageBlobDataContributorRoleDefinition.id
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

//********************************************
// Key Vault: link-signing key + PostgreSQL connection string
//********************************************

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    accessPolicies: []
  }
}

resource keyVaultSecretsUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, managedIdentity.id, keyVaultSecretsUserRoleDefinition.id)
  scope: keyVault
  properties: {
    roleDefinitionId: keyVaultSecretsUserRoleDefinition.id
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource signKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'link-sign-key'
  properties: {
    value: signKey
  }
}

//********************************************
// PostgreSQL flexible server: click-event log
//********************************************

resource postgresServer 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' = {
  name: toLower(postgresServerName)
  location: location
  sku: {
    name: 'Standard_B1ms'
    tier: 'Burstable'
  }
  properties: {
    administratorLogin: postgresAdminLogin
    administratorLoginPassword: postgresAdminPassword
    version: '16'
    createMode: 'Default'
    storage: {
      storageSizeGB: 32
    }
  }
}

resource postgresDatabase 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2024-08-01' = {
  parent: postgresServer
  name: postgresDatabaseName
}

resource postgresFirewallRule 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2024-08-01' = {
  parent: postgresServer
  name: 'AllowAllIPs'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '255.255.255.255'
  }
}

// The PostgreSQL flexible-server emulator embeds the LS-side TCP-proxy port directly in
// fullyQualifiedDomainName; real Azure returns just the bare host on 5432.
var postgresFqdnParts = split(postgresServer.properties.fullyQualifiedDomainName, ':')
var postgresHost = postgresFqdnParts[0]
var postgresPort = length(postgresFqdnParts) > 1 ? postgresFqdnParts[1] : '5432'

resource postgresConnectionSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'pg-conn'
  properties: {
    value: 'host=${postgresHost} port=${postgresPort} dbname=${postgresDatabaseName} user=${postgresAdminLogin} password=${postgresAdminPassword}'
  }
  dependsOn: [
    postgresDatabase
  ]
}

//********************************************
// Service Bus: link-created events consumed by the abuse-scan worker
//********************************************

resource servicebusNamespace 'Microsoft.ServiceBus/namespaces@2024-01-01' = {
  name: servicebusNamespaceName
  location: location
  sku: {
    name: 'Standard'
  }
}

resource linkEventsQueue 'Microsoft.ServiceBus/namespaces/queues@2024-01-01' = {
  parent: servicebusNamespace
  name: servicebusQueueName
}

resource serviceBusSenderRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(servicebusNamespace.id, managedIdentity.id, serviceBusDataSenderRoleDefinition.id)
  scope: servicebusNamespace
  properties: {
    roleDefinitionId: serviceBusDataSenderRoleDefinition.id
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource serviceBusReceiverRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(servicebusNamespace.id, managedIdentity.id, serviceBusDataReceiverRoleDefinition.id)
  scope: servicebusNamespace
  properties: {
    roleDefinitionId: serviceBusDataReceiverRoleDefinition.id
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

//********************************************
// Observability: Log Analytics workspace
//********************************************

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

resource storageDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'default'
  scope: storageAccount
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    metrics: [
      {
        category: 'Transaction'
        enabled: true
      }
    ]
  }
}

//********************************************
// Compute: one Linux plan hosting both the web app and the worker
//********************************************

resource appServicePlan 'Microsoft.Web/serverfarms@2024-11-01' = {
  name: appServicePlanName
  location: location
  kind: 'linux'
  sku: {
    name: 'B1'
  }
  properties: {
    reserved: true
  }
}

var servicebusConnectionString = listKeys('${servicebusNamespace.id}/AuthorizationRules/RootManageSharedAccessKey', '2024-01-01').primaryConnectionString
var storageAccountKey = storageAccount.listKeys().keys[0].value
var storageEndpoints = storageAccount.properties.primaryEndpoints

resource webApp 'Microsoft.Web/sites@2024-11-01' = {
  name: webAppName
  location: location
  kind: 'app,linux'
  properties: {
    httpsOnly: false
    reserved: true
    serverFarmId: appServicePlan.id
    siteConfig: {
      linuxFxVersion: toUpper('${runtimeName}|${webRuntimeVersion}')
      appSettings: [
        { name: 'SCM_DO_BUILD_DURING_DEPLOYMENT', value: 'true' }
        { name: 'AZURE_CLIENT_ID', value: managedIdentity.properties.clientId }
        { name: 'AZURE_TABLES_ENDPOINT', value: storageEndpoints.table }
        { name: 'LINKS_TABLE', value: linksTableName }
        { name: 'KEYVAULT_URL', value: keyVault.properties.vaultUri }
        { name: 'QUEUE_ENDPOINT', value: storageEndpoints.queue }
        { name: 'QR_JOBS_QUEUE', value: qrJobsQueueName }
        { name: 'BLOB_ENDPOINT', value: storageEndpoints.blob }
        { name: 'QR_CONTAINER', value: qrContainerName }
        { name: 'SB_CONN', value: servicebusConnectionString }
        { name: 'SB_QUEUE', value: servicebusQueueName }
        { name: 'PG_SECRET_NAME', value: 'pg-conn' }
        { name: 'INTERNAL_TOKEN', value: internalToken }
      ]
    }
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
}

resource functionApp 'Microsoft.Web/sites@2024-11-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  properties: {
    httpsOnly: false
    reserved: true
    serverFarmId: appServicePlan.id
    siteConfig: {
      linuxFxVersion: toUpper('${runtimeName}|${functionRuntimeVersion}')
      appSettings: [
        { name: 'FUNCTIONS_EXTENSION_VERSION', value: '~4' }
        { name: 'FUNCTIONS_WORKER_RUNTIME', value: runtimeName }
        { name: 'SCM_DO_BUILD_DURING_DEPLOYMENT', value: 'true' }
        { name: 'ENABLE_ORYX_BUILD', value: 'true' }
        { name: 'AzureWebJobsStorage', value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};AccountKey=${storageAccountKey};BlobEndpoint=${storageEndpoints.blob};QueueEndpoint=${storageEndpoints.queue};TableEndpoint=${storageEndpoints.table}' }
        { name: 'AZURE_CLIENT_ID', value: managedIdentity.properties.clientId }
        { name: 'ServiceBusConnection__fullyQualifiedNamespace', value: '${servicebusNamespaceName}.servicebus.windows.net' }
        { name: 'ServiceBusConnection__clientId', value: managedIdentity.properties.clientId }
        { name: 'ServiceBusConnection__credential', value: 'managedidentity' }
        { name: 'QrStorage', value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};AccountKey=${storageAccountKey};BlobEndpoint=${storageEndpoints.blob};QueueEndpoint=${storageEndpoints.queue};TableEndpoint=${storageEndpoints.table}' }
        { name: 'WEB_BASE_URL', value: 'http://${webApp.properties.defaultHostName}' }
        { name: 'INTERNAL_TOKEN', value: internalToken }
      ]
    }
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
}

//********************************************
// Outputs
//********************************************

output resourceGroupName string = resourceGroup().name
output storageAccountName string = storageAccount.name
output keyVaultName string = keyVault.name
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name
output webAppName string = webApp.name
output functionAppName string = functionApp.name
output webAppHostName string = webApp.properties.defaultHostName
