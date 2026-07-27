using 'main.bicep'

param prefix = 'local'
param suffix = 'payments'
param location = 'westeurope'
param eventHubSkuName = 'Standard'
param partitionCount = 4
param retentionTimeInHours = 24
param captureIntervalInSeconds = 60
param fraudAmountThreshold = 5000
param fraudVelocityCount = 5
