//********************************************
// Key Vault holding the pipeline connection strings
//********************************************

@description('Specifies the name of the key vault.')
@minLength(3)
@maxLength(24)
param keyVaultName string

@description('Specifies the location for all resources.')
param location string


@description('Specifies the tags for all resources.')
param tags object = {}

@description('Specifies the resource id of the Log Analytics workspace the diagnostic settings send to.')
param workspaceId string

@description('Specifies the name of the diagnostic settings.')
param diagnosticSettingsName string = 'default'

@description('Specifies the log categories that the diagnostic settings of the key vault send to the workspace (AZKVAuditLogs, AZKVPolicyEvaluationDetailsLogs).')
param logCategories array = [
  'AuditEvent'
  'AzurePolicyEvaluationDetails'
]

@description('Specifies the object id of the deploying principal, granted Key Vault Secrets Officer on the vault so that deploy.sh can write the secrets. Empty skips the assignment.')
param deployerPrincipalId string = ''

@description('Specifies the type of the deploying principal.')
@allowed([
  'User'
  'ServicePrincipal'
  'Group'
])
param deployerPrincipalType string = 'User'

// The built-in Key Vault Secrets Officer role: any action on the secrets of a vault
var keyVaultSecretsOfficerRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7')

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    // Soft delete is on by default in Azure and cannot be turned off once enabled, so the
    // template states it explicitly rather than asking for something Azure would refuse.
    // It also matches the Terraform path, which sets a 7-day retention.
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    publicNetworkAccess: 'Enabled'
  }
}

// The secrets themselves are written by deploy.sh after the deployment: keeping them out
// of the template means they never appear in the deployment history. The vault uses the RBAC permission model, so
// the deploying principal needs a data-plane role to write them.
resource keyVaultSecretsOfficerRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(deployerPrincipalId)) {
  name: guid(keyVault.id, deployerPrincipalId, keyVaultSecretsOfficerRoleId)
  scope: keyVault
  properties: {
    roleDefinitionId: keyVaultSecretsOfficerRoleId
    principalId: deployerPrincipalId
    principalType: deployerPrincipalType
  }
}

// The operations on the vault and its secrets, among them the writes of deploy.sh and the reads of validate.sh, in the
// resource-specific tables (Dedicated)
resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: diagnosticSettingsName
  scope: keyVault
  properties: {
    workspaceId: workspaceId
    logAnalyticsDestinationType: 'Dedicated'
    logs: [for category in logCategories: {
      category: category
      enabled: true
    }]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

output keyVaultId string = keyVault.id
output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
