using 'main.bicep'

param prefix = 'local'
param suffix = 'test'
param runtimeName = 'python'
param runtimeVersion = '3.13'
param databaseName = 'PlannerDB'
param username = 'paolo'

// PostgreSQL flexible server
param pgAdminLogin = 'pgadmin'
// Passwords are supplied at deploy time via the PG_ADMIN_PASSWORD and PG_APP_PASSWORD env vars
// (see deploy.sh, which passes them as --parameters pgAdminPassword=... pgAppPassword=...). Do not commit them here.
param pgAdminPassword = readEnvironmentVariable('PG_ADMIN_PASSWORD', '')
param pgVersion = '16'
param pgSkuTier = 'Burstable'
param pgSkuName = 'Standard_B1ms'
param pgStorageSizeGB = 32
param pgBackupRetentionDays = 7

// Application role stored in Key Vault (pg-user and pg-password secrets) and referenced from App Configuration
param pgAppUser = 'testuser'
param pgAppPassword = readEnvironmentVariable('PG_APP_PASSWORD', '')

// App Configuration store and key vault
param appConfigurationSku = 'Standard'
param keyVaultSkuName = 'standard'
