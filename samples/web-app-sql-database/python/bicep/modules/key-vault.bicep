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

@description('Specifies the principal id of the web app\'s system-assigned managed identity, which reads the connection string secret and the certificate.')
param webAppPrincipalId string

@description('Specifies the principal id of the user-assigned managed identity the SQL server reads its TDE protector key with.')
param sqlServerIdentityPrincipalId string

@description('Specifies the object id of the principal that runs the deployment, which creates the certificate of the web app after it. Empty gives it no access policy.')
param deployerPrincipalId string = ''

@description('Specifies whether soft delete is enabled for the Key Vault.')
param enableSoftDelete bool = true

@description('Specifies the number of days a deleted vault is retained.')
param softDeleteRetentionInDays int = 7

@description('Specifies whether purge protection is enabled for the Key Vault. Azure SQL requires it on the vault of a TDE protector key.')
param enablePurgeProtection bool = true

@description('Specifies the name of the key used as the TDE protector of the SQL server.')
param tdeKeyName string

@description('Specifies the name of the secret that holds the SQL connection string.')
param sqlConnectionStringSecretName string

@description('Specifies the fully qualified domain name of the SQL server.')
param sqlServerFqdn string

@description('Specifies the name of the SQL database.')
param sqlDatabaseName string

@description('Specifies the username of the SQL database user the app connects as.')
param sqlDatabaseUsername string

@description('Specifies the password of the SQL database user the app connects as.')
@secure()
param sqlDatabasePassword string

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

//********************************************
// Resources
//********************************************
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: skuName
    }
    accessPolicies: concat([
      {
        tenantId: subscription().tenantId
        objectId: webAppPrincipalId
        permissions: {
          secrets: [
            'get'
            'list'
          ]
          certificates: [
            'get'
          ]
        }
      }
      {
        tenantId: subscription().tenantId
        objectId: sqlServerIdentityPrincipalId
        permissions: {
          keys: [
            'get'
            'wrapKey'
            'unwrapKey'
          ]
        }
      }
    ], empty(deployerPrincipalId) ? [] : [
      {
        tenantId: subscription().tenantId
        objectId: deployerPrincipalId
        permissions: {
          certificates: [
            'get'
            'list'
            'create'
          ]
        }
      }
    ])
    enableRbacAuthorization: false
    enableSoftDelete: enableSoftDelete
    softDeleteRetentionInDays: softDeleteRetentionInDays
    enablePurgeProtection: enablePurgeProtection
  }
}

resource tdeKey 'Microsoft.KeyVault/vaults/keys@2024-11-01' = {
  parent: keyVault
  name: tdeKeyName
  properties: {
    kty: 'RSA'
    keySize: 2048
    keyOps: [
      'wrapKey'
      'unwrapKey'
    ]
  }
}

resource sqlConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2024-11-01' = {
  parent: keyVault
  name: sqlConnectionStringSecretName
  properties: {
    value: 'Server=tcp:${sqlServerFqdn},1433;Database=${sqlDatabaseName};User ID=${sqlDatabaseUsername};Password=${sqlDatabasePassword};Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;'
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
output tdeKeyName string = tdeKey.name
output tdeKeyUriWithVersion string = tdeKey.properties.keyUriWithVersion
output sqlConnectionStringSecretName string = sqlConnectionStringSecret.name
output sqlConnectionStringSecretUri string = sqlConnectionStringSecret.properties.secretUri
