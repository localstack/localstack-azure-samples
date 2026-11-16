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

// The identity the web app uses to access the storage account. The role assignment lives in the
// storage-account-role-assignment module.
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
