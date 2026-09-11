//********************************************
// Parameters
//********************************************
@description('Specifies the name of the App Configuration store. Globally unique, 5 to 50 alphanumerics and hyphens.')
@minLength(5)
@maxLength(50)
param name string

@description('Specifies the location.')
param location string = resourceGroup().location

@description('Specifies the SKU of the App Configuration store. Private endpoints need Developer, Standard or Premium.')
@allowed([
  'Developer'
  'Standard'
  'Premium'
])
param skuName string = 'Standard'

@description('Specifies for how many days a deleted App Configuration store stays recoverable.')
@minValue(1)
@maxValue(7)
param softDeleteRetentionInDays int = 7

@description('Specifies whether the access keys of the store are disabled. The keyValues children are written through Azure Resource Manager, which in the default Local authentication mode relies on the access keys, so they stay enabled.')
param disableLocalAuth bool = false

@description('Specifies whether purge protection is enabled for the store. Off so that a deleted store can be purged and its name reused.')
param enablePurgeProtection bool = false

@description('Specifies whether the store accepts requests from public networks. The deployment seeds the store from outside the virtual network; the web app reaches it through its private endpoint.')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Enabled'

@description('Specifies the key-values to seed: objects with key, value and contentType (empty for a plain value).')
param keyValues array

@description('Specifies the principal id of the managed identity that reads the store (App Configuration Data Reader).')
param dataReaderPrincipalId string

@description('Specifies the principal type of the managed identity that reads the store.')
@allowed([
  'User'
  'ServicePrincipal'
  'Group'
])
param dataReaderPrincipalType string = 'ServicePrincipal'

@description('Specifies the id of the built-in role assigned to the reading identity: App Configuration Data Reader by default.')
param dataReaderRoleDefinitionId string = '516239f1-63e1-4d78-a4de-a74fb236a071'

@description('Specifies the resource id of the Log Analytics workspace.')
param workspaceId string

@description('Specifies the name of the diagnostic settings.')
param diagnosticSettingsName string = 'default'

@description('Specifies the log categories enabled by the diagnostic settings.')
param logCategories array = [
  'HttpRequest'
  'Audit'
]

@description('Specifies the metric categories enabled by the diagnostic settings.')
param metricCategories array = [
  'AllMetrics'
]

@description('Specifies whether the retention policy of the diagnostic settings is enabled.')
param retentionPolicyEnabled bool = true

@description('Specifies the retention of the diagnostic settings in days (0 keeps the data as long as the workspace does).')
param retentionPolicyDays int = 0

@description('Specifies the resource tags.')
param tags object

//********************************************
// Variables
//********************************************

// App Configuration Data Reader: Microsoft.AppConfiguration/configurationStores/*/read data actions.
var dataReaderRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', dataReaderRoleDefinitionId)
var logs = [
  for category in logCategories: {
    category: category
    enabled: true
    retentionPolicy: {
      enabled: retentionPolicyEnabled
      days: retentionPolicyDays
    }
  }
]
var metrics = [
  for category in metricCategories: {
    category: category
    enabled: true
    retentionPolicy: {
      enabled: retentionPolicyEnabled
      days: retentionPolicyDays
    }
  }
]

//********************************************
// Resources
//********************************************

resource configurationStore 'Microsoft.AppConfiguration/configurationStores@2024-06-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: skuName
  }
  properties: {
    disableLocalAuth: disableLocalAuth
    enablePurgeProtection: enablePurgeProtection
    softDeleteRetentionInDays: softDeleteRetentionInDays
    publicNetworkAccess: publicNetworkAccess
  }
}

// The key-values, seeded through the ARM child resource. The child name is the key (no label is used, so
// no '$<label>' suffix). A Key Vault reference is a key-value whose content type is
// application/vnd.microsoft.appconfig.keyvaultref+json;charset=utf-8 and whose value is {"uri":"<secret uri>"}.
// The array arrives as a parameter, which is what lets the loop use values that main.bicep reads from
// other modules at deployment time.
resource storeKeyValues 'Microsoft.AppConfiguration/configurationStores/keyValues@2024-06-01' = [
  for keyValue in keyValues: {
    parent: configurationStore
    name: keyValue.key
    properties: {
      value: keyValue.value
      contentType: empty(keyValue.contentType) ? null : keyValue.contentType
    }
  }
]

resource appConfigurationDataReaderRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(configurationStore.id, dataReaderPrincipalId, dataReaderRoleId)
  scope: configurationStore
  properties: {
    roleDefinitionId: dataReaderRoleId
    principalId: dataReaderPrincipalId
    principalType: dataReaderPrincipalType
  }
}

resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(workspaceId)) {
  name: diagnosticSettingsName
  scope: configurationStore
  properties: {
    workspaceId: workspaceId
    logs: logs
    metrics: metrics
  }
}

//********************************************
// Outputs
//********************************************
output id string = configurationStore.id
output name string = configurationStore.name
// The endpoint the web app connects to, read back from the service: https://<store>.azconfig.io on Azure,
// https://<store>.azure.localhost.localstack.cloud:4566 on the emulator.
output endpoint string = configurationStore.properties.endpoint
