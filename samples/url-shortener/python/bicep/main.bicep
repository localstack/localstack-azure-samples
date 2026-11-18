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

@description('Specifies the tags to be applied to the resources.')
param tags object = {
  environment: 'test'
  iac: 'bicep'
}

//
// Observability
//
@description('Specifies the name of the Azure Application Insights resource.')
param applicationInsightsName string = ''

@description('Specifies the service tier of the workspace.')
@allowed(['Free','Standalone','PerNode','PerGB2018'])
param logAnalyticsSku string = 'PerGB2018'

@description('Specifies the workspace data retention in days.')
param logAnalyticsRetentionInDays int = 30

//********************************************
// Variables
//********************************************

var storageAccountName = '${prefix}urlstorage${suffix}'
var keyVaultName = '${prefix}-urlshort-kv-${suffix}'
var postgresServerName = '${prefix}-urlshort-pgflex-${suffix}'
var servicebusNamespaceName = '${prefix}-urlshort-sb-ns-${suffix}'
var logAnalyticsName = '${prefix}-urlshort-log-analytics-${suffix}'
var appServicePlanName = '${prefix}-urlshort-app-service-plan-${suffix}'
var webAppName = '${prefix}-urlshort-webapp-${suffix}'
var functionAppName = '${prefix}-urlshort-functionapp-${suffix}'
var managedIdentityName = '${prefix}-urlshort-identity-${suffix}'
var linksTableName = 'links'
var qrJobsQueueName = 'qrjobs'
var qrContainerName = 'qrcodes'
var servicebusQueueName = 'link-events'
var postgresDatabaseName = 'clicks'

//********************************************
// Observability: the workspace and Application Insights
//********************************************

module workspace 'modules/log-analytics.bicep' = {
  name: 'workspace'
  params: {
    name: logAnalyticsName
    location: location
    tags: tags
    sku: logAnalyticsSku
    retentionInDays: logAnalyticsRetentionInDays
  }
}

module applicationInsights 'modules/application-insights.bicep' = {
  name: 'applicationInsights'
  params: {
    name: empty(applicationInsightsName) ? toLower('${prefix}-urlshort-insights-${suffix}') : applicationInsightsName
    location: location
    workspaceId: workspace.outputs.id
    tags: tags
  }
}

//********************************************
// Identity: shared by the web app and the worker
//********************************************

module managedIdentity 'modules/managed-identity.bicep' = {
  name: 'managedIdentity'
  params: {
    name: managedIdentityName
    location: location
    tags: tags
  }
}

//********************************************
// Storage: table (links store), queue (QR render jobs), blob (QR images)
//********************************************

module storageAccount 'modules/storage-account.bicep' = {
  name: 'storageAccount'
  params: {
    name: storageAccountName
    location: location
    linksTableName: linksTableName
    qrJobsQueueName: qrJobsQueueName
    qrContainerName: qrContainerName
    dataPrincipalId: managedIdentity.outputs.principalId
    workspaceId: workspace.outputs.id
    tags: tags
  }
}

//********************************************
// PostgreSQL flexible server: click-event log
//********************************************

module postgresServer 'modules/postgresql-flexible-server.bicep' = {
  name: 'postgresServer'
  params: {
    name: toLower(postgresServerName)
    location: location
    administratorLogin: postgresAdminLogin
    administratorLoginPassword: postgresAdminPassword
    version: '16'
    skuTier: 'Burstable'
    skuName: 'Standard_B1ms'
    storageSizeGB: 32
    databaseName: postgresDatabaseName
    firewallRuleName: 'AllowAllIPs'
    firewallStartIp: '0.0.0.0'
    firewallEndIp: '255.255.255.255'
    workspaceId: workspace.outputs.id
    tags: tags
  }
}

// The PostgreSQL flexible-server emulator embeds the LS-side TCP-proxy port directly in
// fullyQualifiedDomainName; real Azure returns just the bare host on 5432.
var postgresFqdnParts = split(postgresServer.outputs.fqdn, ':')
var postgresHost = postgresFqdnParts[0]
var postgresPort = length(postgresFqdnParts) > 1 ? postgresFqdnParts[1] : '5432'

//********************************************
// Key Vault: link-signing key + PostgreSQL connection string
//********************************************

module keyVault 'modules/key-vault.bicep' = {
  name: 'keyVault'
  params: {
    name: keyVaultName
    location: location
    signKey: signKey
    postgresConnectionString: 'host=${postgresHost} port=${postgresPort} dbname=${postgresServer.outputs.databaseName} user=${postgresAdminLogin} password=${postgresAdminPassword}'
    vaultReaderPrincipalId: managedIdentity.outputs.principalId
    workspaceId: workspace.outputs.id
    tags: tags
  }
}

//********************************************
// Service Bus: link-created events consumed by the abuse-scan worker
//********************************************

module servicebusNamespace 'modules/service-bus.bicep' = {
  name: 'servicebusNamespace'
  params: {
    name: servicebusNamespaceName
    location: location
    skuName: 'Standard'
    capacity: 1
    zoneRedundant: false
    queueNames: [
      servicebusQueueName
    ]
    dataPrincipalId: managedIdentity.outputs.principalId
    workspaceId: workspace.outputs.id
    tags: tags
  }
}

// The keys are read by the modules that use them, when they deploy: Azure refused key reads in this template before the
// Service Bus namespace and the storage account existed. The web app module gets the namespace name and the function
// app module the storage account name and endpoints, outputs of the modules that create them.

//********************************************
// Compute: one Linux plan hosting both the web app and the worker
//********************************************

module appServicePlan 'modules/app-service-plan.bicep' = {
  name: 'appServicePlan'
  params: {
    name: appServicePlanName
    location: location
    skuTier: 'Basic'
    skuName: 'B1'
    kind: 'linux'
    reserved: true
    workspaceId: workspace.outputs.id
    tags: tags
  }
}

module webApp 'modules/web-app.bicep' = {
  name: 'webApp'
  params: {
    name: webAppName
    location: location
    runtimeName: runtimeName
    runtimeVersion: webRuntimeVersion
    hostingPlanName: appServicePlan.outputs.name
    managedIdentityId: managedIdentity.outputs.id
    appSettings: {
      SCM_DO_BUILD_DURING_DEPLOYMENT: 'true'
      AZURE_CLIENT_ID: managedIdentity.outputs.clientId
      AZURE_TABLES_ENDPOINT: storageAccount.outputs.tableEndpoint
      LINKS_TABLE: linksTableName
      KEYVAULT_URL: keyVault.outputs.vaultUri
      QUEUE_ENDPOINT: storageAccount.outputs.queueEndpoint
      QR_JOBS_QUEUE: qrJobsQueueName
      BLOB_ENDPOINT: storageAccount.outputs.blobEndpoint
      QR_CONTAINER: qrContainerName
      SB_QUEUE: servicebusQueueName
      PG_SECRET_NAME: keyVault.outputs.postgresConnectionSecretName
      INTERNAL_TOKEN: internalToken
      APPLICATIONINSIGHTS_CONNECTION_STRING: applicationInsights.outputs.connectionString
    }
    serviceBusNamespaceName: servicebusNamespace.outputs.name
    workspaceId: workspace.outputs.id
    tags: tags
  }
}

module functionApp 'modules/function-app.bicep' = {
  name: 'functionApp'
  params: {
    name: functionAppName
    location: location
    kind: 'functionapp,linux'
    runtimeName: runtimeName
    runtimeVersion: functionRuntimeVersion
    httpsOnly: false
    identityType: 'UserAssigned'
    managedIdentityId: managedIdentity.outputs.id
    hostingPlanName: appServicePlan.outputs.name
    storageAccountName: storageAccount.outputs.name
    // Explicit endpoints rather than an EndpointSuffix: the Functions host's storage clients cannot parse a suffix that
    // carries the emulator's port. The module also writes the connection string to QrStorage.
    storageEndpoints: {
      blob: storageAccount.outputs.blobEndpoint
      queue: storageAccount.outputs.queueEndpoint
      table: storageAccount.outputs.tableEndpoint
    }
    storageConnectionStringSettingName: 'QrStorage'
    appSettings: {
      SCM_DO_BUILD_DURING_DEPLOYMENT: 'true'
      ENABLE_ORYX_BUILD: 'true'
      AZURE_CLIENT_ID: managedIdentity.outputs.clientId
      ServiceBusConnection__fullyQualifiedNamespace: '${servicebusNamespaceName}.servicebus.windows.net'
      ServiceBusConnection__clientId: managedIdentity.outputs.clientId
      ServiceBusConnection__credential: 'managedidentity'
      WEB_BASE_URL: 'http://${webApp.outputs.defaultHostName}'
      INTERNAL_TOKEN: internalToken
      APPLICATIONINSIGHTS_CONNECTION_STRING: applicationInsights.outputs.connectionString
      // The Python worker sends its own telemetry through OpenTelemetry, which host.json turns on, instead of the host
      // forwarding its log records, and only the records of the functions' logger
      PYTHON_APPLICATIONINSIGHTS_ENABLE_TELEMETRY: 'true'
      PYTHON_APPLICATIONINSIGHTS_LOGGER_NAME: 'function_app'
    }
    workspaceId: workspace.outputs.id
    tags: tags
  }
}

//********************************************
// Outputs
//********************************************

output resourceGroupName string = resourceGroup().name
output storageAccountName string = storageAccount.outputs.name
output keyVaultName string = keyVault.outputs.name
output logAnalyticsWorkspaceName string = workspace.outputs.name
output applicationInsightsName string = applicationInsights.outputs.name
output webAppName string = webApp.outputs.name
output functionAppName string = functionApp.outputs.name
output webAppHostName string = webApp.outputs.defaultHostName
output postgresHost string = postgresHost
output postgresPort string = postgresPort
