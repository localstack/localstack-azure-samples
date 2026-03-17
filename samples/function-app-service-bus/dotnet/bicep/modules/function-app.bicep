//********************************************
// Parameters
//********************************************

@description('Specifies a globally unique name the Azure Functions App.')
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
param kind string = 'functionapp,linux'

@description('Specifies the language runtime used by the Azure Functions App.')
@allowed([
  'dotnet'
  'dotnet-isolated'
  'python'
  'java'
  'node'
  'powerShell'
  'custom'
])
param runtimeName string

@description('Specifies the target language version used by the Azure Functions App.')
param runtimeVersion string

@description('Specifies the minimum TLS version for the Azure Functions App.')
@allowed([
  '1.0'
  '1.1'
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

@description('Specifies whether Always On is enabled for the Azure Functions App.')
param alwaysOn bool = true

@description('Specifies whether HTTPS is enforced for the Azure Functions App.')
param httpsOnly bool = true

@description('Specifies the type of managed identity.')
@allowed([
  'SystemAssigned'
  'UserAssigned'
])
param managedIdentityType string = 'UserAssigned'

@description('Specifies the name of a user-assigned managed identity.')
param managedIdentityName string = ''

@description('Specifies the name of the hosting plan.')
param hostingPlanName string

@description('Specifies allowed origins for client-side CORS requests on the site.')
param allowedCorsOrigins string[] = []

@description('Specifies the name of the virtual network.')
param virtualNetworkName string

@description('Specifies the name of the subnet used by Azure Functions for the regional virtual network integration.')
param subnetName string

@description('Specifies the app settings of the Azure Functions App')
param settings array = []

@description('Specifies the resource id of the Log Analytics workspace.')
param workspaceId string

@description('Specifies the optional Git Repo URL.')
param repoUrl string = ' '

@description('Specifies the resource tags.')
param tags object

//********************************************
// Variables
//********************************************

// Generates a unique container name for deployments.
var diagnosticSettingsName = 'diagnosticSettings'
var logCategories = [
  'FunctionAppLogs'
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

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2025-01-31-preview' existing = {
  name: managedIdentityName
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2025-05-01' existing = {
  name: virtualNetworkName
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2025-05-01' existing = {
  parent: virtualNetwork
  name: subnetName
}

resource hostingPlan 'Microsoft.Web/serverfarms@2025-03-01' existing = {
  name: hostingPlanName
}

resource functionApp 'Microsoft.Web/sites@2025-03-01' = {
  name: name
  location: location
  kind: kind
  tags: tags
  identity: {
    type: managedIdentityType
    userAssignedIdentities  : managedIdentityType == 'SystemAssigned' ? null : {
          '${managedIdentity.id}': {}
        } 
  }
  properties: {
    httpsOnly: httpsOnly
    serverFarmId: hostingPlan.id
    virtualNetworkSubnetId: subnet.id
    outboundVnetRouting: {
      allTraffic: true
    }
    siteConfig: {
      minTlsVersion: minTlsVersion
      alwaysOn: alwaysOn
      linuxFxVersion: toUpper('${runtimeName}|${runtimeVersion}')
      cors: {
        allowedOrigins: union(['https://portal.azure.com', 'https://ms.portal.azure.com'], allowedCorsOrigins)
      }
      publicNetworkAccess: publicNetworkAccess
      appSettings: [
        for setting in settings: {
          name: setting.name
          value: setting.value
        }
      ]
      netFrameworkVersion: runtimeName == 'dotnet' || runtimeName == 'dotnet-isolated' ? runtimeVersion : null
      nodeVersion: runtimeName == 'node' ? runtimeVersion : null
      pythonVersion: runtimeName == 'python' ? runtimeVersion : null
      javaVersion: runtimeName == 'java' ? runtimeVersion : null
    }
  }
}

resource webAppSourceControl 'Microsoft.Web/sites/sourcecontrols@2024-11-01' = if (contains(repoUrl,'http')){
  name: 'web'
  parent: functionApp
  properties: {
    repoUrl: repoUrl
    branch: 'master'
    isManualIntegration: true
  }
}

resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if(!empty(workspaceId)) {
  name: diagnosticSettingsName
  scope: functionApp
  properties: {
    workspaceId: workspaceId
    logs: logs
    metrics: metrics
  }
}

//********************************************
// Outputs
//********************************************

output id string = functionApp.id
output name string = functionApp.name
output defaultHostName string = functionApp.properties.defaultHostName
