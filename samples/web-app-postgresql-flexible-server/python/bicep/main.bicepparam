using 'main.bicep'

param prefix = 'local'
param suffix = 'test'
param runtimeName = 'python'
param runtimeVersion = '3.13'
param databaseName = 'PlannerDB'
param username = 'paolo'

// PostgreSQL flexible server
param pgAdminLogin = 'pgadmin'
// Password is supplied at deploy time via the PG_ADMIN_PASSWORD env var
// (see deploy.sh — it passes it as --parameters pgAdminPassword=...). Do not commit it here.
param pgAdminPassword = readEnvironmentVariable('PG_ADMIN_PASSWORD', '')
// The password of the application user is supplied the same way (deploy.sh passes --parameters pgAppPassword=...).
param pgAppPassword = readEnvironmentVariable('PG_APP_PASSWORD', '')
param pgVersion = '16'
param pgSkuTier = 'Burstable'
param pgSkuName = 'Standard_B1ms'
param pgStorageSizeGB = 32
param pgBackupRetentionDays = 7
