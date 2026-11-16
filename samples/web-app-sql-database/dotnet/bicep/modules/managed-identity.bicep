//********************************************
// Parameters
//********************************************
@description('Specifies the name of the user-assigned managed identity.')
param name string

@description('Specifies the location.')
param location string = resourceGroup().location

@description('Specifies the resource tags.')
param tags object

//********************************************
// Resources
//********************************************

// The identity the SQL server reads its TDE protector key with: the Key Vault module gives it the get, wrapKey and
// unwrapKey key permissions in an access policy of the vault.
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: name
  location: location
  tags: tags
}

//********************************************
// Outputs
//********************************************
output id string = managedIdentity.id
output name string = managedIdentity.name
output clientId string = managedIdentity.properties.clientId
output principalId string = managedIdentity.properties.principalId
