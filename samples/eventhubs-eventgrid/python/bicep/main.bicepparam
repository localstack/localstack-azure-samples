using 'main.bicep'

param prefix = 'local'
param suffix = 'telemetry'
param eventHubSkuName = 'Standard'
param telemetryPartitionCount = 4
param retentionTimeInHours = 24
param captureIntervalInSeconds = 60
param temperatureLimit = 80
