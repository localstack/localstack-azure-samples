//********************************************
// Parameters
//********************************************

@description('Specifies the name of the Key Vault.')
param name string

@description('Specifies the location.')
param location string = resourceGroup().location

@description('Specifies the SKU name of the Key Vault.')
@allowed([
  'standard'
  'premium'
])
param skuName string = 'standard'

@description('Specifies the HMAC key the web app signs the short codes with, stored as the link-sign-key secret.')
@secure()
param signKey string

@description('Specifies the libpq connection string of the PostgreSQL database, stored as the pg-conn secret.')
@secure()
param postgresConnectionString string

@description('Specifies the principal id that gets the Key Vault Secrets User role on the vault; none when empty.')
param vaultReaderPrincipalId string = ''

@description('Specifies the resource id of the Log Analytics workspace.')
param workspaceId string

@description('Specifies the name of the diagnostic settings.')
param diagnosticSettingsName string = 'default'

@description('Specifies the log categories enabled by the diagnostic settings.')
param logCategories array = [
  'AuditEvent'
  'AzurePolicyEvaluationDetails'
]

@description('Specifies the metric categories enabled by the diagnostic settings.')
param metricCategories array = [
  'AllMetrics'
]

@description('Specifies where the diagnostic settings write the logs in the workspace: Dedicated writes each category to its resource-specific table (AZKVAuditLogs, AZKVPolicyEvaluationDetailsLogs), AzureDiagnostics to the shared AzureDiagnostics table.')
@allowed([
  'AzureDiagnostics'
  'Dedicated'
])
param logAnalyticsDestinationType string = 'Dedicated'

@description('Specifies the resource tags.')
param tags object

//********************************************
// Variables
//********************************************

var logs = [
  for category in logCategories: {
    category: category
    enabled: true
  }
]
var metrics = [
  for category in metricCategories: {
    category: category
    enabled: true
  }
]
var keyVaultSecretsUserRoleDefinitionId = '4633458b-17de-408a-b874-0445c86b69e6'

//********************************************
// Resources
//********************************************

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: skuName
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    accessPolicies: []
  }
}

resource vaultReaderRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(vaultReaderPrincipalId)) {
  name: guid(keyVault.id, vaultReaderPrincipalId, keyVaultSecretsUserRoleDefinitionId)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleDefinitionId)
    principalId: vaultReaderPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// The secrets are written through Azure Resource Manager, so the deployment needs no role on the vault's data plane
resource signKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'link-sign-key'
  properties: {
    value: signKey
  }
}

resource postgresConnectionSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'pg-conn'
  properties: {
    value: postgresConnectionString
  }
}

resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(workspaceId)) {
  name: diagnosticSettingsName
  scope: keyVault
  properties: {
    workspaceId: workspaceId
    logAnalyticsDestinationType: logAnalyticsDestinationType
    logs: logs
    metrics: metrics
  }
}

//********************************************
// Outputs
//********************************************

output id string = keyVault.id
output name string = keyVault.name
output vaultUri string = keyVault.properties.vaultUri
output postgresConnectionSecretName string = postgresConnectionSecret.name
