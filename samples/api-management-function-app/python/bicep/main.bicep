//********************************************
// Parameters
//********************************************

@description('Prefix applied to every resource name in this sample.')
param prefix string = 'local'

@description('Suffix applied to every resource name in this sample.')
param suffix string = 'test'

@description('Location for all resources.')
param location string = resourceGroup().location

@description('Language runtime of the Function App.')
param runtimeName string = 'python'

@description('Runtime version of the Function App.')
param runtimeVersion string = '3.11'

@description('SKU of the Linux App Service plan hosting the Function App.')
param appServicePlanSku string = 'B1'

@description('SKU of the API Management service. Consumption provisions in minutes; the classic tiers take much longer.')
param apimSkuName string = 'Consumption'

@description('Name of the organisation publishing the APIs.')
param publisherName string = 'LocalStack'

@description('E-mail address API Management sends its notifications to.')
param publisherEmail string = 'noreply@localstack.cloud'

@description('Scheme API Management uses to call the Function App. The emulator serves it over plain HTTP; use https on real Azure.')
@allowed([
  'http'
  'https'
])
param backendScheme string = 'http'

@description('Shared secret the gateway adds to every backend call; generated per run by deploy.sh.')
@secure()
param backendSecret string

//********************************************
// Variables
//********************************************

var storageAccountName = '${prefix}invstorage${suffix}'
var appServicePlanName = '${prefix}-inventory-app-service-plan-${suffix}'
var functionAppName = '${prefix}-inventory-functionapp-${suffix}'
var apimName = '${prefix}-inventory-apim-${suffix}'
var apiId = 'inventory-api'
var apiPath = 'inventory'
var productId = 'inventory-partners'
var apimSubscriptionId = 'partner-subscription'
var namedValueId = 'backend-secret'
// Consumption has no capacity units; every other tier starts at one.
var apimSkuCapacity = apimSkuName == 'Consumption' ? 0 : 1

//********************************************
// Function App: the Inventory backend
//********************************************

resource storageAccount 'Microsoft.Storage/storageAccounts@2025-01-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
}

resource appServicePlan 'Microsoft.Web/serverfarms@2024-11-01' = {
  name: appServicePlanName
  location: location
  kind: 'linux'
  sku: {
    name: appServicePlanSku
  }
  properties: {
    reserved: true
  }
}

var storageAccountKey = storageAccount.listKeys().keys[0].value
var storageEndpoints = storageAccount.properties.primaryEndpoints

resource functionApp 'Microsoft.Web/sites@2024-11-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  properties: {
    // Plain HTTP while the gateway calls this app over http:// -- the emulator serves the Function
    // App that way; with backendScheme = https the app accepts only HTTPS, as on real Azure.
    httpsOnly: backendScheme == 'https'
    reserved: true
    serverFarmId: appServicePlan.id
    siteConfig: {
      // On a Dedicated (App Service) plan the Functions host goes idle without this, and a gateway
      // call then waits for a cold start. Both sibling Function App samples set it.
      alwaysOn: true
      linuxFxVersion: toUpper('${runtimeName}|${runtimeVersion}')
      appSettings: [
        { name: 'FUNCTIONS_EXTENSION_VERSION', value: '~4' }
        { name: 'FUNCTIONS_WORKER_RUNTIME', value: runtimeName }
        { name: 'SCM_DO_BUILD_DURING_DEPLOYMENT', value: 'true' }
        { name: 'ENABLE_ORYX_BUILD', value: 'true' }
        // Explicit endpoints rather than an EndpointSuffix: the Functions host's storage clients
        // cannot parse a suffix that carries the emulator's port.
        { name: 'AzureWebJobsStorage', value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};AccountKey=${storageAccountKey};BlobEndpoint=${storageEndpoints.blob};QueueEndpoint=${storageEndpoints.queue};TableEndpoint=${storageEndpoints.table}' }
        // The same secret the gateway injects from its named value.
        { name: 'BACKEND_SECRET', value: backendSecret }
      ]
    }
  }
}

//********************************************
// API Management
//********************************************

resource apim 'Microsoft.ApiManagement/service@2024-05-01' = {
  name: apimName
  location: location
  sku: {
    name: apimSkuName
    capacity: apimSkuCapacity
  }
  properties: {
    publisherName: publisherName
    publisherEmail: publisherEmail
  }
}

// The shared secret lives in a secret named value; the policy refers to it as {{backend-secret}}.
resource backendSecretNamedValue 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apim
  name: namedValueId
  properties: {
    displayName: namedValueId
    secret: true
    value: backendSecret
  }
}

// Imported from the OpenAPI document shared with the other deployment variants, so its operations
// come from the document. The backend is the Function App: the emulator answers on plain HTTP under
// its own hostname (use https:// on real Azure).
resource inventoryApi 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: apim
  name: apiId
  properties: {
    displayName: 'Inventory API'
    description: 'Stock levels served by an Azure Function App and published through Azure API Management.'
    path: apiPath
    protocols: [
      'https'
    ]
    subscriptionRequired: true
    serviceUrl: '${backendScheme}://${functionApp.properties.defaultHostName}/api'
    format: 'openapi+json'
    value: loadTextContent('../apim/openapi.json')
  }
}

// Policies are validated when they are saved, and this one references the named value, so the
// named value has to exist first.
resource inventoryApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  parent: inventoryApi
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: loadTextContent('../apim/inventory-api-policy.xml')
  }
  dependsOn: [
    backendSecretNamedValue
  ]
}

resource partnersProduct 'Microsoft.ApiManagement/service/products@2024-05-01' = {
  parent: apim
  name: productId
  properties: {
    displayName: 'Inventory Partners'
    description: 'Partners reading stock levels through the Inventory API'
    subscriptionRequired: true
    approvalRequired: false
    state: 'published'
  }
}

resource partnersProductApi 'Microsoft.ApiManagement/service/products/apis@2024-05-01' = {
  parent: partnersProduct
  name: inventoryApi.name
}

// The subscription's key is what clients present. Its scope is the product, so the key opens every
// API the product contains and nothing else.
resource partnerSubscription 'Microsoft.ApiManagement/service/subscriptions@2024-05-01' = {
  parent: apim
  name: apimSubscriptionId
  properties: {
    displayName: 'Partner subscription'
    scope: partnersProduct.id
    state: 'active'
  }
}

//********************************************
// Outputs
//********************************************

output resourceGroupName string = resourceGroup().name
output functionAppName string = functionApp.name
output functionAppHostName string = functionApp.properties.defaultHostName
output apimName string = apim.name
output gatewayUrl string = apim.properties.gatewayUrl
output apiPath string = apiPath
output subscriptionName string = partnerSubscription.name
