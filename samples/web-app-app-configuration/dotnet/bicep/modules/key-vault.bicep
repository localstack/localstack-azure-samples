//********************************************
// Parameters
//********************************************
@description('Specifies the name of the key vault. Globally unique, 3 to 24 alphanumerics and hyphens.')
@minLength(3)
@maxLength(24)
param name string

@description('Specifies the location.')
param location string = resourceGroup().location

@description('Specifies the SKU family of the key vault.')
param skuFamily string = 'A'

@description('Specifies the SKU of the key vault.')
@allowed([
  'standard'
  'premium'
])
param skuName string = 'standard'

@description('Specifies whether the key vault uses the Azure RBAC permission model for data-plane authorization. The Key Vault Secrets User and Key Vault Secrets Officer roles only work with it.')
param enableRbacAuthorization bool = true

@description('Specifies whether soft delete is enabled for the key vault.')
param enableSoftDelete bool = true

@description('Specifies whether the key vault accepts requests from public networks. The deployment writes the secrets from outside the virtual network; the web app reaches the vault through its private endpoint.')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Enabled'

@description('Specifies the default action of the network ACLs of the key vault.')
@allowed([
  'Allow'
  'Deny'
])
param networkAclsDefaultAction string = 'Allow'

@description('Specifies which traffic bypasses the network ACLs of the key vault.')
@allowed([
  'AzureServices'
  'None'
])
param networkAclsBypass string = 'AzureServices'

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

@description('Specifies the principal type of the managed identity that reads the secrets.')
@allowed([
  'User'
  'ServicePrincipal'
  'Group'
])
param identityPrincipalType string = 'ServicePrincipal'

@description('Specifies the id of the built-in role assigned to the reading identity: Key Vault Secrets User by default.')
// A public role definition id, not a credential; the linter reacts to the role name in the parameter name.
#disable-next-line secure-secrets-in-params
param keyVaultSecretsUserRoleDefinitionId string = '4633458b-17de-408a-b874-0445c86b69e6'

@description('Specifies the id of the built-in role assigned to the deploying principal: Key Vault Secrets Officer by default.')
// A public role definition id, not a credential; the linter reacts to the role name in the parameter name.
#disable-next-line secure-secrets-in-params
param keyVaultSecretsOfficerRoleDefinitionId string = 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'

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

@description('Specifies whether the retention policy of the diagnostic settings is enabled.')
param retentionPolicyEnabled bool = true

@description('Specifies the retention of the diagnostic settings in days (0 keeps the data as long as the workspace does).')
param retentionPolicyDays int = 0

@description('Specifies the resource tags.')
param tags object

//********************************************
// Variables
//********************************************

// Key Vault Secrets User: read secret contents. Key Vault Secrets Officer: any action on secrets except
// managing permissions. Both work only on vaults that use the Azure RBAC permission model.
var keyVaultSecretsUserRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleDefinitionId)
var keyVaultSecretsOfficerRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsOfficerRoleDefinitionId)
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

resource keyVault 'Microsoft.KeyVault/vaults@2024-11-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: skuFamily
      name: skuName
    }
    enableRbacAuthorization: enableRbacAuthorization
    enableSoftDelete: enableSoftDelete
    softDeleteRetentionInDays: softDeleteRetentionInDays
    publicNetworkAccess: publicNetworkAccess
    networkAcls: {
      defaultAction: networkAclsDefaultAction
      bypass: networkAclsBypass
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
  name: guid(keyVault.id, identityPrincipalId, keyVaultSecretsUserRoleId)
  scope: keyVault
  properties: {
    roleDefinitionId: keyVaultSecretsUserRoleId
    principalId: identityPrincipalId
    principalType: identityPrincipalType
  }
}

resource keyVaultSecretsOfficerRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(deployerPrincipalId)) {
  name: guid(keyVault.id, deployerPrincipalId, keyVaultSecretsOfficerRoleId)
  scope: keyVault
  properties: {
    roleDefinitionId: keyVaultSecretsOfficerRoleId
    principalId: deployerPrincipalId
    principalType: deployerPrincipalType
  }
}

resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(workspaceId)) {
  name: diagnosticSettingsName
  scope: keyVault
  properties: {
    workspaceId: workspaceId
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
