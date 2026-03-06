param location string
param serviceBusName string
param queueName string
param tags object

resource sb 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: serviceBusName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Standard'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
    zoneRedundant: false
  }
}

resource auth 'Microsoft.ServiceBus/namespaces/authorizationRules@2022-10-01-preview' = {
  name: '${sb.name}/RootManageSharedAccessKey'
  properties: {
    rights: [
      'Listen'
      'Send'
      'Manage'
    ]
  }
}

resource queue 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  name: '${sb.name}/${queueName}'
  properties: {
    enablePartitioning: false
    lockDuration: 'PT1M'
    maxDeliveryCount: 10
    requiresDuplicateDetection: false
  }
}

output serviceBusId string = sb.id
output serviceBusName string = sb.name
output queueName string = queueName
output serviceBusEndpoint string = sb.properties.serviceBusEndpoint
output serviceBusConnectionString string = listKeys(auth.id, auth.apiVersion).primaryConnectionString
