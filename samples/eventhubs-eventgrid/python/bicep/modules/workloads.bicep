//********************************************
// The Function App that processes each Capture archive, and its App Service plan.
//
// The connection-string app settings (AzureWebJobsStorage, STORAGE_CONNECTION_STRING,
// EVENTHUB_*) are set by deploy.sh after this template completes: they are built from keys that
// only exist once the resources do, and keeping them out of the template keeps them out of the
// deployment history.
//********************************************

@description('Name of the Function App running the capture processor.')
param functionAppName string

@description('Name of the App Service plan hosting it.')
param functionPlanName string

@description('Specifies the location for all resources.')
param location string

@description('Python version for the worker.')
param pythonVersion string = '3.12'

@description('Hub the trigger reads.')
param notificationHubName string

@description('Hub the output binding writes to.')
param curatedHubName string

@description('Consumer group the trigger uses.')
param captureConsumerGroup string

@description('A reading at or above this is reported as an excursion.')
param temperatureLimit int

@description('Specifies the tags for all resources.')
param tags object = {}

@description('Specifies the resource id of the Log Analytics workspace the diagnostic settings send to.')
param workspaceId string

@description('Specifies the name of the diagnostic settings.')
param diagnosticSettingsName string = 'default'

@description('Specifies the connection string of the Application Insights resource the function app sends its telemetry to.')
param applicationInsightsConnectionString string

resource functionPlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: functionPlanName
  location: location
  tags: tags
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {
    reserved: true
  }
}

resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp,linux'
  properties: {
    serverFarmId: functionPlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'Python|${pythonVersion}'
      appSettings: [
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'python'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(functionAppName)
        }
        // The trigger and output bindings resolve these by name (see function_app.py).
        {
          name: 'NOTIFICATION_HUB_NAME'
          value: notificationHubName
        }
        {
          name: 'CURATED_HUB_NAME'
          value: curatedHubName
        }
        {
          name: 'CAPTURE_CONSUMER_GROUP'
          value: captureConsumerGroup
        }
        {
          name: 'TEMPERATURE_LIMIT'
          value: string(temperatureLimit)
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsightsConnectionString
        }
        // The Python worker sends its own telemetry through OpenTelemetry, which host.json turns on, instead of the
        // host forwarding its log records, and only the records of the function's logger
        {
          name: 'PYTHON_APPLICATIONINSIGHTS_ENABLE_TELEMETRY'
          value: 'true'
        }
        {
          name: 'PYTHON_APPLICATIONINSIGHTS_LOGGER_NAME'
          value: 'function_app'
        }
      ]
    }
  }
}

resource planDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: diagnosticSettingsName
  scope: functionPlan
  properties: {
    workspaceId: workspaceId
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

resource functionAppDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: diagnosticSettingsName
  scope: functionApp
  properties: {
    workspaceId: workspaceId
    logs: [
      {
        category: 'FunctionAppLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

output functionAppName string = functionApp.name
output functionAppId string = functionApp.id
