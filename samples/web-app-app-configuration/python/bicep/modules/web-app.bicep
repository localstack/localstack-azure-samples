//********************************************
// Parameters
//********************************************

@description('Specifies a globally unique name the Azure Web App.')
param name string

@description('Specifies the location.')
param location string = resourceGroup().location

@description('Specifies the kind of the hosting plan.')
@allowed([
  'app'                                    // Windows Web app
  'app,linux'                              // Linux Web app
  'app,linux,container'                    // Linux Container Web app
  'hyperV'                                 // Windows Container Web App
  'app,container,windows'                  // Windows Container Web App
  'app,linux,kubernetes'                   // Linux Web App on ARC
  'app,linux,container,kubernetes'         // Linux Container Web App on ARC
  'functionapp'                            // Function Code App
  'functionapp,linux'                      // Linux Consumption Function app
  'functionapp,linux,container,kubernetes' // Function Container App on ARC
  'functionapp,linux,kubernetes'           // Function Code App on ARC
])
param kind string = 'app,linux'

@description('Specifies the language runtime used by the Azure Web App.')
@allowed([
  'dotnet'
  'dotnetcore'
  'dotnet-isolated'
  'python'
  'java'
  'node'
  'powerShell'
  'custom'
])
param runtimeName string

@description('Specifies the target language version used by the Azure Web App.')
param runtimeVersion string

@description('Specifies the minimum TLS version for the Azure Web App.')
@allowed([
  '1.2'
  '1.3'
])
param minTlsVersion string = '1.2'

@description('Specifies whether the public network access is enabled or disabled')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Enabled'

@description('Specifies whether HTTPS is enforced for the Azure Web App.')
param httpsOnly bool = true

@description('Specifies the name of the hosting plan.')
param hostingPlanName string

@description('Specifies the resource id of the user-assigned managed identity the web app authenticates with.')
param managedIdentityId string

@description('Specifies the client id of the user-assigned managed identity, handed to the app as AZURE_CLIENT_ID.')
param managedIdentityClientId string

@description('Specifies the endpoint of the App Configuration store the app loads its settings from.')
param appConfigurationEndpoint string

@description('Specifies the name of the virtual network.')
param virtualNetworkName string

@description('Specifies the name of the subnet used by the Web App for the regional virtual network integration.')
param subnetName string

@description('Specifies the resource id of the Log Analytics workspace.')
param workspaceId string

@description('Specifies the username for the application.')
param username string = 'paolo'

@description('Specifies the optional Git Repo URL.')
param repoUrl string = ' '

@description('Specifies the resource tags.')
param tags object

//********************************************
// Variables
//********************************************

var diagnosticSettingsName = 'default'
var logCategories = [
  'AppServiceHTTPLogs'
  'AppServiceConsoleLogs'
  'AppServiceAppLogs'
  'AppServiceAuditLogs'
  'AppServiceIPSecAuditLogs'
  'AppServicePlatformLogs'
  'AppServiceAuthenticationLogs'
]
var metricCategories = [
  'AllMetrics'
]
var logs = [
  for category in logCategories: {
    category: category
    enabled: true
    retentionPolicy: {
      enabled: true
      days: 0
    }
  }
]
var metrics = [
  for category in metricCategories: {
    category: category
    enabled: true
    retentionPolicy: {
      enabled: true
      days: 0
    }
  }
]

//********************************************
// Resources
//********************************************

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: virtualNetworkName
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  parent: virtualNetwork
  name: subnetName
}

resource hostingPlan 'Microsoft.Web/serverfarms@2024-04-01' existing = {
  name: hostingPlanName
}

resource webApp 'Microsoft.Web/sites@2025-03-01' = {
  name: name
  location: location
  tags: tags
  kind: kind
  properties: {
    httpsOnly: httpsOnly
    serverFarmId: hostingPlan.id
    virtualNetworkSubnetId: subnet.id
    outboundVnetRouting: {
      allTraffic: true
    }
    siteConfig: {
      linuxFxVersion: toUpper('${runtimeName}|${runtimeVersion}')
      minTlsVersion: minTlsVersion
      publicNetworkAccess: publicNetworkAccess
    }
  }
  // The user-assigned managed identity that App Configuration Data Reader and Key Vault Secrets User are
  // assigned to. AZURE_CLIENT_ID below tells DefaultAzureCredential in the app to use it.
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityId}': {}
    }
  }
}

resource configAppSettings 'Microsoft.Web/sites/config@2024-11-01' = {
  parent: webApp
  name: 'appsettings'
  properties: {
    SCM_DO_BUILD_DURING_DEPLOYMENT: 'true'
    ENABLE_ORYX_BUILD: 'true'
    // No PG_* setting: the app loads PG_HOST, PG_PORT, PG_DATABASE, PG_USER and PG_PASSWORD from the App
    // Configuration store with the in-process provider, which also resolves the two Key Vault references.
    // Endpoints__AppConfiguration is the setting the provider reads the store endpoint from (the .NET
    // variant sees it as Endpoints:AppConfiguration).
    Endpoints__AppConfiguration: appConfigurationEndpoint
    AZURE_CLIENT_ID: managedIdentityClientId
    WEBSITES_PORT: '8000'
    LOGIN_NAME: username
  }
}

resource webAppSourceControl 'Microsoft.Web/sites/sourcecontrols@2024-11-01' = if (contains(repoUrl,'http')){
  name: 'web'
  parent: webApp
  properties: {
    repoUrl: repoUrl
    branch: 'master'
    isManualIntegration: true
  }
}

resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if(!empty(workspaceId)) {
  name: diagnosticSettingsName
  scope: webApp
  properties: {
    workspaceId: workspaceId
    logs: logs
    metrics: metrics
  }
}

//********************************************
// Outputs
//********************************************
output id string = webApp.id
output name string = webApp.name
output defaultHostName string = webApp.properties.defaultHostName
