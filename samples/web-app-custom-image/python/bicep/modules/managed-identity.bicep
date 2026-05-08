//********************************************
// Parameters
//********************************************

@description('Specifies the name of the user-defined managed identity.')
param name string

@description('Specifies the location.')
param location string = resourceGroup().location

@description('Specifies the name of the Azure Container Registry.')
param containerRegistryName string

@description('Specifies the resource tags.')
param tags object

//********************************************
// Resources
//********************************************


resource containerRegistry 'Microsoft.ContainerRegistry/registries@2025-06-01-preview' existing = {
  name: containerRegistryName
}

resource acrPullRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: '7f951dda-4ed3-4680-a7ca-43fe172d538d'
  scope: subscription()
}

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2025-01-31-preview' = {
  name: name
  location: location
  tags: tags
}

resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(containerRegistry.id, managedIdentity.id, acrPullRoleDefinition.id)
  scope: containerRegistry
  properties: {
    roleDefinitionId: acrPullRoleDefinition.id
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

//********************************************
// Outputs
//********************************************

output id string = managedIdentity.id
output name string = managedIdentity.name
output clientId string = managedIdentity.properties.clientId
output principalId string = managedIdentity.properties.principalId
