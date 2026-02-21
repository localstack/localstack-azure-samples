using 'main.bicep'

param serverNamePrefix = 'pgflex'
param administratorLogin = 'pgadmin'
param administratorLoginPassword = 'P@ssw0rd12345!'
param version = '16'
param skuName = 'B_Standard_B1ms'
param skuTier = 'Burstable'
param storageSizeGB = 32
param databaseName = 'sampledb'
param firewallRuleName = 'allow-all'
param firewallStartIp = '0.0.0.0'
param firewallEndIp = '255.255.255.255'
