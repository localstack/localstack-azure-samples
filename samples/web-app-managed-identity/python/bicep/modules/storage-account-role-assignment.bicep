//********************************************
// Parameters
//********************************************
@description('Specifies the name of the Azure Storage account the role is assigned on.')
param storageAccountName string

@description('Specifies the id of the built-in role definition to assign, for example ba92f5b4-2d11-453d-a403-e96b0029c9fe for Storage Blob Data Contributor.')
param roleDefinitionId string

@description('Specifies the principal (object) id the role is assigned to. For a managed identity, this is its principal id, never its client id.')
param principalId string

@description('Specifies the type of the principal the role is assigned to.')
@allowed([
  'User'
  'Group'
  'ServicePrincipal'
])
param principalType string = 'ServicePrincipal'

//********************************************
// Resources
//********************************************
resource storageAccount 'Microsoft.Storage/storageAccounts@2025-01-01' existing = {
  name: storageAccountName
}

resource roleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: roleDefinitionId
  scope: subscription()
}

// The name is derived from the scope, the principal and the role, so a second deployment updates the same
// assignment instead of creating a duplicate.
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, principalId, roleDefinition.id)
  scope: storageAccount
  properties: {
    roleDefinitionId: roleDefinition.id
    principalId: principalId
    principalType: principalType
  }
}

//********************************************
// Outputs
//********************************************
output id string = roleAssignment.id
output name string = roleAssignment.name
