//********************************************
// Parameters
//********************************************

@description('Specifies the name of the Azure Web App.')
param webAppName string

@description('Specifies whether App Service builds the deployed zip with Oryx (SCM_DO_BUILD_DURING_DEPLOYMENT).')
@allowed([
  'true'
  'false'
])
param scmDoBuildDuringDeployment string = 'true'

@description('Specifies whether the Oryx build runs for the deployed zip (ENABLE_ORYX_BUILD).')
@allowed([
  'true'
  'false'
])
param enableOryxBuild string = 'true'

@description('Specifies the name of the Key Vault that holds the SQL connection string secret and the certificate.')
param keyVaultName string

@description('Specifies the URI of the Key Vault.')
param keyVaultUri string

@description('Specifies the name of the Key Vault secret that holds the SQL connection string.')
param secretName string

@description('Specifies the name of the Key Vault certificate the app serves HTTPS with on port 8443.')
param certificateName string

@description('Specifies the username for the application.')
param username string

@description('Specifies the client id of the web app\'s user-assigned managed identity, handed to the app as AZURE_CLIENT_ID.')
param managedIdentityClientId string

@description('Specifies the connection string of the Application Insights resource the app sends its telemetry to.')
param applicationInsightsConnectionString string

//********************************************
// Resources
//********************************************

resource webApp 'Microsoft.Web/sites@2024-11-01' existing = {
  name: webAppName
}

// The app settings are a module of their own, applied once the Key Vault module has created the vault, its secret and
// the role assignments of the web app's identity: the app reads the vault as soon as these settings restart it.
resource configAppSettings 'Microsoft.Web/sites/config@2024-11-01' = {
  parent: webApp
  name: 'appsettings'
  properties: {
    SCM_DO_BUILD_DURING_DEPLOYMENT: scmDoBuildDuringDeployment
    ENABLE_ORYX_BUILD: enableOryxBuild
    // The Key Vault name and the secret name: the app reads the connection string from the vault itself
    KEY_VAULT_NAME: keyVaultName
    SECRET_NAME: secretName
    LOGIN_NAME: username
    KEYVAULT_URI: keyVaultUri
    CERT_NAME: certificateName
    // The user-assigned managed identity DefaultAzureCredential reads the vault with
    AZURE_CLIENT_ID: managedIdentityClientId
    APPLICATIONINSIGHTS_CONNECTION_STRING: applicationInsightsConnectionString
  }
}
