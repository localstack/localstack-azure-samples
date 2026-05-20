using 'main.bicep'

param queueName = 'myqueue'
param zoneRedundant = false
param tags = {
  environment: 'test'
  iac: 'bicep'
}
