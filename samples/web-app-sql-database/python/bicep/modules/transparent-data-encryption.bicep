@description('Specifies the name of the SQL logical server.')
param sqlServerName string

@description('Specifies the name of the Key Vault that holds the TDE protector key.')
param keyVaultName string

@description('Specifies the name of the Key Vault key used as the TDE protector.')
param keyName string

@description('Specifies the versioned URI of the Key Vault key used as the TDE protector.')
param keyUri string

resource sqlServer 'Microsoft.Sql/servers@2024-05-01-preview' existing = {
  name: sqlServerName
}

// A server key must be named after the vault, key and key version it points to.
resource serverKey 'Microsoft.Sql/servers/keys@2023-08-01' = {
  parent: sqlServer
  name: '${keyVaultName}_${keyName}_${last(split(keyUri, '/'))}'
  properties: {
    serverKeyType: 'AzureKeyVault'
    uri: keyUri
  }
}

resource encryptionProtector 'Microsoft.Sql/servers/encryptionProtector@2023-08-01' = {
  parent: sqlServer
  name: 'current'
  properties: {
    serverKeyType: 'AzureKeyVault'
    serverKeyName: serverKey.name
    autoRotationEnabled: true
  }
}
