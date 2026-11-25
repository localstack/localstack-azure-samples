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

@description('Specifies whether the Key Vault uses the Azure RBAC permission model, which the role assignments of this module need.')
param enableRbacAuthorization bool = true

@description('Specifies the principal id of the web app\'s user-assigned managed identity, which reads the connection string secret and the certificate.')
param webAppIdentityPrincipalId string

@description('Specifies the principal id of the user-assigned managed identity the SQL server reads its TDE protector key with.')
param sqlServerIdentityPrincipalId string

@description('Specifies the principal type of the two managed identities in their role assignments.')
@allowed([
  'User'
  'ServicePrincipal'
  'Group'
])
param identityPrincipalType string = 'ServicePrincipal'

@description('Specifies the id of the built-in role the web app\'s identity reads the connection string and the private key of the certificate with: Key Vault Secrets User by default.')
// A public role definition id, not a credential; the linter reacts to the role name in the parameter name.
#disable-next-line secure-secrets-in-params
param keyVaultSecretsUserRoleDefinitionId string = '4633458b-17de-408a-b874-0445c86b69e6'

@description('Specifies the id of the built-in role the web app\'s identity reads the certificate with: Key Vault Certificate User by default.')
param keyVaultCertificateUserRoleDefinitionId string = 'db79e9a7-68ee-4b58-9aeb-b90e7c24fcba'

@description('Specifies the id of the built-in role the SQL server\'s identity wraps and unwraps its database encryption keys with: Key Vault Crypto Service Encryption User by default.')
param keyVaultCryptoServiceEncryptionUserRoleDefinitionId string = 'e147488a-f6f5-4113-8e2d-b22465e65bf6'

@description('Specifies the id of the built-in role the deploying principal reads the connection string secret with: Key Vault Secrets Officer by default.')
// A public role definition id, not a credential; the linter reacts to the role name in the parameter name.
#disable-next-line secure-secrets-in-params
param keyVaultSecretsOfficerRoleDefinitionId string = 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'

@description('Specifies the id of the built-in role the deploying principal creates the certificate with: Key Vault Certificates Officer by default.')
param keyVaultCertificatesOfficerRoleDefinitionId string = 'a4417e6f-fecd-4de8-b567-7b0420556985'

@description('Specifies the object id of the principal that runs the deployment: deploy.sh creates the certificate of the web app after it, and validate.sh reads the connection string secret. Empty skips its role assignments.')
param deployerPrincipalId string = ''

@description('Specifies the principal type of the deploying principal.')
@allowed([
  'User'
  'ServicePrincipal'
  'Group'
])
param deployerPrincipalType string = 'User'

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

// Key Vault Secrets User: read secret contents. Key Vault Certificate User: read certificate contents. Key Vault
// Crypto Service Encryption User: read the metadata of keys and wrap and unwrap with them. Key Vault Secrets Officer
// and Key Vault Certificates Officer: any action on secrets and on certificates, except managing permissions. All of
// them work only on vaults that use the Azure RBAC permission model.
var keyVaultSecretsUserRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleDefinitionId)
var keyVaultCertificateUserRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultCertificateUserRoleDefinitionId)
var keyVaultCryptoServiceEncryptionUserRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultCryptoServiceEncryptionUserRoleDefinitionId)
var keyVaultSecretsOfficerRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsOfficerRoleDefinitionId)
var keyVaultCertificatesOfficerRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultCertificatesOfficerRoleDefinitionId)
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
    enableRbacAuthorization: enableRbacAuthorization
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

// The web app reads the connection string and the private key of its certificate as secrets, and the certificate
// itself, with its user-assigned managed identity
resource webAppSecretsUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, webAppIdentityPrincipalId, keyVaultSecretsUserRoleId)
  scope: keyVault
  properties: {
    roleDefinitionId: keyVaultSecretsUserRoleId
    principalId: webAppIdentityPrincipalId
    principalType: identityPrincipalType
  }
}

resource webAppCertificateUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, webAppIdentityPrincipalId, keyVaultCertificateUserRoleId)
  scope: keyVault
  properties: {
    roleDefinitionId: keyVaultCertificateUserRoleId
    principalId: webAppIdentityPrincipalId
    principalType: identityPrincipalType
  }
}

// The SQL server wraps and unwraps its database encryption keys with the TDE protector key through its user-assigned
// managed identity. The TDE module uses the outputs of this module, so it starts only after this assignment exists.
resource sqlServerCryptoServiceEncryptionUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, sqlServerIdentityPrincipalId, keyVaultCryptoServiceEncryptionUserRoleId)
  scope: keyVault
  properties: {
    roleDefinitionId: keyVaultCryptoServiceEncryptionUserRoleId
    principalId: sqlServerIdentityPrincipalId
    principalType: identityPrincipalType
  }
}

// The deploying principal creates the certificate after the deployment (Bicep cannot create a Key Vault certificate)
// and reads the connection string secret when it validates the deployment, both through the data plane
resource deployerSecretsOfficerRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(deployerPrincipalId)) {
  name: guid(keyVault.id, deployerPrincipalId, keyVaultSecretsOfficerRoleId)
  scope: keyVault
  properties: {
    roleDefinitionId: keyVaultSecretsOfficerRoleId
    principalId: deployerPrincipalId
    principalType: deployerPrincipalType
  }
}

resource deployerCertificatesOfficerRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(deployerPrincipalId)) {
  name: guid(keyVault.id, deployerPrincipalId, keyVaultCertificatesOfficerRoleId)
  scope: keyVault
  properties: {
    roleDefinitionId: keyVaultCertificatesOfficerRoleId
    principalId: deployerPrincipalId
    principalType: deployerPrincipalType
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
