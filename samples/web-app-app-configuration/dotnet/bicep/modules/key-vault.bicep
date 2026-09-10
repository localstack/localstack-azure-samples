//********************************************
// Parameters
//********************************************
@description('Specifies the name of the key vault. Globally unique, 3 to 24 alphanumerics and hyphens.')
@minLength(3)
@maxLength(24)
param name string

@description('Specifies the location.')
param location string = resourceGroup().location

@description('Specifies the SKU of the key vault.')
@allowed([
  'standard'
  'premium'
])
param skuName string = 'standard'

@description('Specifies for how many days a deleted key vault or secret stays recoverable.')
@minValue(7)
@maxValue(90)
param softDeleteRetentionInDays int = 7

@description('Specifies the name of the secret holding the PostgreSQL application role name.')
param pgUserSecretName string = 'pg-user'

@description('Specifies the PostgreSQL application role name stored as a secret.')
param pgAppUser string

@description('Specifies the name of the secret holding the PostgreSQL application role password.')
param pgPasswordSecretName string = 'pg-password'

@description('Specifies the PostgreSQL application role password stored as a secret.')
@secure()
param pgAppPassword string

@description('Specifies the principal id of the managed identity that reads the secrets (Key Vault Secrets User).')
param identityPrincipalId string

@description('Specifies the object id of the deploying principal, granted Key Vault Secrets Officer on the vault. Empty skips the assignment.')
param deployerPrincipalId string = ''

@description('Specifies the principal type of the deploying principal.')
@allowed([
  'User'
  'ServicePrincipal'
  'Group'
])
param deployerPrincipalType string = 'User'

@description('Specifies the resource id of the Log Analytics workspace.')
param workspaceId string

@description('Specifies the resource tags.')
param tags object

//********************************************
// Variables
//********************************************

// Key Vault Secrets User: read secret contents. Key Vault Secrets Officer: any action on secrets except
// managing permissions. Both work only on vaults that use the Azure RBAC permission model.
var keyVaultSecretsUserRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
var keyVaultSecretsOfficerRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7')
var diagnosticSettingsName = 'default'

//********************************************
// Resources
//********************************************

resource keyVault 'Microsoft.KeyVault/vaults@2024-11-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: skuName
    }
    // Azure RBAC permission model: the Key Vault Secrets User assignment below only works with it.
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: softDeleteRetentionInDays
    // Public network access stays enabled, like the PostgreSQL server of the original sample: the
    // deployment runs outside the virtual network. The web app reaches the vault through its private endpoint.
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// The two secrets the App Configuration Key Vault references point at. Written through Azure Resource
// Manager, which authorizes them with the control-plane action Microsoft.KeyVault/vaults/secrets/write
// included in the Contributor role.
resource pgUserSecret 'Microsoft.KeyVault/vaults/secrets@2024-11-01' = {
  parent: keyVault
  name: pgUserSecretName
  tags: tags
  properties: {
    value: pgAppUser
  }
}

resource pgPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2024-11-01' = {
  parent: keyVault
  name: pgPasswordSecretName
  tags: tags
  properties: {
    value: pgAppPassword
  }
}

resource keyVaultSecretsUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, identityPrincipalId, keyVaultSecretsUserRoleDefinitionId)
  scope: keyVault
  properties: {
    roleDefinitionId: keyVaultSecretsUserRoleDefinitionId
    principalId: identityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource keyVaultSecretsOfficerRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(deployerPrincipalId)) {
  name: guid(keyVault.id, deployerPrincipalId, keyVaultSecretsOfficerRoleDefinitionId)
  scope: keyVault
  properties: {
    roleDefinitionId: keyVaultSecretsOfficerRoleDefinitionId
    principalId: deployerPrincipalId
    principalType: deployerPrincipalType
  }
}

resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(workspaceId)) {
  name: diagnosticSettingsName
  scope: keyVault
  properties: {
    workspaceId: workspaceId
    logs: [
      {
        category: 'AuditEvent'
        enabled: true
      }
      {
        category: 'AzurePolicyEvaluationDetails'
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
output id string = keyVault.id
output name string = keyVault.name
output vaultUri string = keyVault.properties.vaultUri
//********************************************
// Variables (secret identifiers)
//********************************************

// Versionless secret identifiers (not secret values): the App Configuration Key Vault references built from
// them always follow the latest version of each secret. They are assembled from the vault URI the service
// returns plus the secret names, the same way the Azure CLI variant builds them, rather than read from the
// secret resources' secretUri property, which the LocalStack emulator does not return today. Azure returns
// the vault URI with a trailing slash, the emulator without one, so the separator is added only when needed.
var vaultUriWithSlash = endsWith(keyVault.properties.vaultUri, '/') ? keyVault.properties.vaultUri : '${keyVault.properties.vaultUri}/'

output secretUris object = {
  pgUser: '${vaultUriWithSlash}secrets/${pgUserSecret.name}'
  pgPassword: '${vaultUriWithSlash}secrets/${pgPasswordSecret.name}'
}
