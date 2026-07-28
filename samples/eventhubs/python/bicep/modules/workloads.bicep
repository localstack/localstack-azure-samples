//********************************************
// Function App (Event Hubs trigger) and Web App (dashboard),
// plus the App Service plans that host them
//********************************************

@description('Specifies the name of the Function App running fraud detection.')
param functionAppName string

@description('Specifies the name of the Web App running the operations dashboard.')
param webAppName string

@description('Specifies the name of the App Service plan for the Function App.')
param functionPlanName string

@description('Specifies the name of the App Service plan for the Web App.')
param webPlanName string

@description('Specifies the location for all resources.')
param location string

@description('Specifies the Python version for both workloads.')
param pythonVersion string = '3.12'

@description('Name of the storage account used for function content and checkpoints.')
param storageAccountName string

// NOTE: the connection-string app settings (AzureWebJobsStorage, EVENTHUB_*) are set by
// deploy.sh after this template completes. They are built from keys that only exist once
// the resources do, and keeping them out of the template also keeps them out of the
// deployment history.

@description('Application Insights connection string.')
param applicationInsightsConnectionString string = ''

@description('Name of the event hub carrying payments.')
param eventHubName string = 'payments'

@description('Name of the event hub carrying fraud alerts.')
param alertHubName string = 'fraud-alerts'

@description('Consumer group the fraud detector reads from.')
param fraudConsumerGroup string = 'fraud-detector'

@description('Blob container holding Capture archives.')
param captureContainerName string = 'payments-archive'

@description('Schema Registry group name.')
param schemaGroupName string = 'payments-schemas'

@description('A single payment at or above this amount is flagged.')
param fraudAmountThreshold int = 5000

@description('More than this many payments for one account inside the window is flagged.')
param fraudVelocityCount int = 5

@description('Velocity window, in seconds.')
param fraudVelocityWindowSeconds int = 60

@description('Specifies the tags for all resources.')
param tags object = {}

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
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsightsConnectionString
        }
        // The trigger and output bindings resolve these by name (see function_app.py).
        {
          name: 'EVENT_HUB_NAME'
          value: eventHubName
        }
        {
          name: 'ALERT_HUB_NAME'
          value: alertHubName
        }
        {
          name: 'FRAUD_CONSUMER_GROUP'
          value: fraudConsumerGroup
        }
        {
          name: 'FRAUD_AMOUNT_THRESHOLD'
          value: string(fraudAmountThreshold)
        }
        {
          name: 'FRAUD_VELOCITY_COUNT'
          value: string(fraudVelocityCount)
        }
        {
          name: 'FRAUD_VELOCITY_WINDOW_SECONDS'
          value: string(fraudVelocityWindowSeconds)
        }
      ]
    }
  }
}

resource webPlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: webPlanName
  location: location
  tags: tags
  sku: {
    name: 'S1'
    tier: 'Standard'
  }
  properties: {
    reserved: true
  }
}

resource webApp 'Microsoft.Web/sites@2023-12-01' = {
  name: webAppName
  location: location
  tags: tags
  kind: 'app,linux'
  properties: {
    serverFarmId: webPlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'PYTHON|${pythonVersion}'
      appCommandLine: 'gunicorn --config gunicorn.conf.py app:app'
      appSettings: [
        {
          name: 'SCM_DO_BUILD_DURING_DEPLOYMENT'
          value: 'true'
        }
        {
          name: 'EVENT_HUB_NAME'
          value: eventHubName
        }
        {
          name: 'ALERT_HUB_NAME'
          value: alertHubName
        }
        {
          name: 'FRAUD_CONSUMER_GROUP'
          value: fraudConsumerGroup
        }
        {
          name: 'CAPTURE_CONTAINER_NAME'
          value: captureContainerName
        }
        {
          name: 'SCHEMA_GROUP_NAME'
          value: schemaGroupName
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsightsConnectionString
        }
      ]
    }
  }
}

output functionAppName string = functionApp.name
output webAppName string = webApp.name
output webAppUrl string = 'https://${webApp.properties.defaultHostName}'
output storageAccountUsed string = storageAccountName
