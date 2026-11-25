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

// A user-assigned managed identity. The sample creates two: the one the SQL server wraps and unwraps its database
// encryption keys with, and the one the web app reads the connection string and the certificate with. The Key Vault
// module assigns their roles on the vault.
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
