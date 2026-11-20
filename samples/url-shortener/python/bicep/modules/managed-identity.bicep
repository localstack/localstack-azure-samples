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

// The identity the web app and the worker share: it reads and writes the links table, the QR jobs queue and the QR
// images, reads the Key Vault secrets, and sends and receives the link events. The role assignments live in the modules
// that own the target resources.
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
