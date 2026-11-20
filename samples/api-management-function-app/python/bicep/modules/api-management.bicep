//********************************************
// Parameters
//********************************************

@description('Specifies the name of the API Management service.')
param name string

@description('Specifies the location.')
param location string = resourceGroup().location

@description('Specifies the SKU of the API Management service. Consumption provisions in minutes; the classic tiers take much longer.')
param skuName string = 'Consumption'

@description('Specifies the name of the organisation publishing the APIs.')
param publisherName string

@description('Specifies the e-mail address API Management sends its notifications to.')
param publisherEmail string

@description('Specifies the id of the secret named value the policy refers to as {{backend-secret}}.')
param namedValueId string = 'backend-secret'

@description('Specifies the shared secret the gateway adds to every backend call.')
@secure()
param backendSecret string

@description('Specifies the id of the API.')
param apiId string = 'inventory-api'

@description('Specifies the URL suffix of the API on the gateway.')
param apiPath string = 'inventory'

@description('Specifies the URL of the backend the API forwards to: the Function App.')
param serviceUrl string

@description('Specifies the OpenAPI document the API is imported from.')
param openApiDocument string

@description('Specifies the policy of the API, in raw XML.')
param apiPolicy string

@description('Specifies the id of the product.')
param productId string = 'inventory-partners'

@description('Specifies the id of the subscription whose key clients present.')
param subscriptionId string = 'partner-subscription'

@description('Specifies the resource id of the Log Analytics workspace.')
param workspaceId string

@description('Specifies the name of the diagnostic settings.')
param diagnosticSettingsName string = 'default'

@description('Specifies the log categories enabled by the diagnostic settings. The Consumption tier doesn\'t support the collection of resource logs, so none is enabled there; on the other tiers GatewayLogs records every request through the gateway.')
param logCategories array = skuName == 'Consumption' ? [] : [
  'GatewayLogs'
]

@description('Specifies the metric categories enabled by the diagnostic settings.')
param metricCategories array = [
  'AllMetrics'
]

@description('Specifies where the diagnostic settings write the logs in the workspace: Dedicated writes the gateway logs to the resource-specific ApiManagementGatewayLogs table, AzureDiagnostics to the shared AzureDiagnostics table.')
@allowed([
  'AzureDiagnostics'
  'Dedicated'
])
param logAnalyticsDestinationType string = 'Dedicated'

@description('Specifies the resource tags.')
param tags object = {}

//********************************************
// Variables
//********************************************

// Consumption has no capacity units; every other tier starts at one.
var skuCapacity = skuName == 'Consumption' ? 0 : 1
var logs = [
  for category in logCategories: {
    category: category
    enabled: true
  }
]
var metrics = [
  for category in metricCategories: {
    category: category
    enabled: true
  }
]

//********************************************
// Resources
//********************************************

resource apim 'Microsoft.ApiManagement/service@2024-05-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: skuName
    capacity: skuCapacity
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

// Imported from the OpenAPI document shared with the other deployment variants, so its operations come from the
// document. The backend is the Function App.
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
    serviceUrl: serviceUrl
    format: 'openapi+json'
    value: openApiDocument
  }
}

// Policies are validated when they are saved, and this one references the named value, so the named value has to
// exist first.
resource inventoryApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  parent: inventoryApi
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: apiPolicy
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

// The subscription's key is what clients present. Its scope is the product, so the key opens every API the product
// contains and nothing else.
resource partnerSubscription 'Microsoft.ApiManagement/service/subscriptions@2024-05-01' = {
  parent: apim
  name: subscriptionId
  properties: {
    displayName: 'Partner subscription'
    scope: partnersProduct.id
    state: 'active'
  }
}

resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(workspaceId)) {
  name: diagnosticSettingsName
  scope: apim
  properties: {
    workspaceId: workspaceId
    logAnalyticsDestinationType: logAnalyticsDestinationType
    logs: logs
    metrics: metrics
  }
}

//********************************************
// Outputs
//********************************************

output id string = apim.id
output name string = apim.name
output gatewayUrl string = apim.properties.gatewayUrl
output apiPath string = inventoryApi.properties.path
output subscriptionName string = partnerSubscription.name
