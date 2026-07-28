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
// of the template means they never appear in the deployment history.

output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
