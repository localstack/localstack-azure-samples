//********************************************
// Log Analytics workspace and Application Insights
// (telemetry for the Function App and the Web App)
//********************************************

@description('Specifies the name of the Log Analytics workspace.')
param workspaceName string

@description('Specifies the name of the Application Insights component.')
param applicationInsightsName string

@description('Specifies the location for all resources.')
param location string

@description('Specifies the retention of workspace data, in days.')
@minValue(30)
@maxValue(730)
param retentionInDays int = 30

@description('Specifies the tags for all resources.')
param tags object = {}

resource workspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
  }
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: workspace.id
  }
}

output workspaceId string = workspace.id
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString
output instrumentationKey string = applicationInsights.properties.InstrumentationKey
