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

@description('Specifies the key-values to seed: objects with key, value and contentType (empty for a plain value).')
param keyValues array

@description('Specifies the principal id of the managed identity that reads the store (App Configuration Data Reader).')
param dataReaderPrincipalId string

@description('Specifies the resource id of the Log Analytics workspace.')
param workspaceId string

@description('Specifies the resource tags.')
param tags object

//********************************************
// Variables
//********************************************

// App Configuration Data Reader: Microsoft.AppConfiguration/configurationStores/*/read data actions.
var appConfigurationDataReaderRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '516239f1-63e1-4d78-a4de-a74fb236a071')
var diagnosticSettingsName = 'default'

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
    // Access keys stay enabled and the Azure Resource Manager authentication mode stays Local (the
    // default): the keyValues children below are written through Azure Resource Manager, which in Local
    // mode relies on the access keys, and the Azure CLI variant seeds the store with them too.
    disableLocalAuth: false
    enablePurgeProtection: false
    softDeleteRetentionInDays: softDeleteRetentionInDays
    // Public network access stays enabled: the deployment runs outside the virtual network. The web app
    // reaches the store through its private endpoint.
    publicNetworkAccess: 'Enabled'
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
  name: guid(configurationStore.id, dataReaderPrincipalId, appConfigurationDataReaderRoleDefinitionId)
  scope: configurationStore
  properties: {
    roleDefinitionId: appConfigurationDataReaderRoleDefinitionId
    principalId: dataReaderPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(workspaceId)) {
  name: diagnosticSettingsName
  scope: configurationStore
  properties: {
    workspaceId: workspaceId
    logs: [
      {
        category: 'HttpRequest'
        enabled: true
      }
      {
        category: 'Audit'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
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
