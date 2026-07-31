//********************************************
// Event Grid: a system topic over the Event Hubs namespace, and a subscription
// that delivers its events into an event hub.
//
// The system topic is how a subscriber reaches the events a resource raises about itself. Event
// Hubs raises exactly one: Microsoft.EventHub.CaptureFileCreated, when Capture writes a file.
// https://learn.microsoft.com/en-us/azure/event-grid/event-schema-event-hubs
//********************************************

@description('Name of the Event Grid system topic.')
param systemTopicName string

@description('Name of the event subscription on that system topic.')
param subscriptionName string

@description('Specifies the location for all resources.')
param location string

@description('Resource id of the Event Hubs namespace the system topic watches.')
param eventHubNamespaceId string

@description('Resource id of the event hub the notifications are delivered to.')
param notificationHubId string

@description('Specifies the tags for all resources.')
param tags object = {}

resource systemTopic 'Microsoft.EventGrid/systemTopics@2024-06-01-preview' = {
  name: systemTopicName
  location: location
  tags: tags
  properties: {
    source: eventHubNamespaceId
    topicType: 'Microsoft.Eventhub.Namespaces'
  }
}

// An EventHub destination turns the notification into a stream event, so an ordinary Event Hubs
// trigger can consume it - no public webhook, and the backlog is durable if the processor is down.
resource captureSubscription 'Microsoft.EventGrid/systemTopics/eventSubscriptions@2024-06-01-preview' = {
  parent: systemTopic
  name: subscriptionName
  properties: {
    destination: {
      endpointType: 'EventHub'
      properties: {
        resourceId: notificationHubId
      }
    }
    eventDeliverySchema: 'EventGridSchema'
  }
}

output systemTopicName string = systemTopic.name
output eventSubscriptionName string = captureSubscription.name
