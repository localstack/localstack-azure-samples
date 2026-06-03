using 'main.bicep'

param prefix = 'local'
param suffix = 'test'
param runtimeName = 'python'
param runtimeVersion = '3.13'
param databaseName = 'PlannerDB'
param username = 'paolo'

// MySQL flexible server
param mysqlAdminLogin = 'myadmin'
// Password is supplied at deploy time via the MYSQL_ADMIN_PASSWORD env var
// (see deploy.sh — it passes it as --parameters mysqlAdminPassword=...). Do not commit it here.
param mysqlAdminPassword = readEnvironmentVariable('MYSQL_ADMIN_PASSWORD', '')
param mysqlVersion = '8.0.21'
param mysqlSkuTier = 'Burstable'
param mysqlSkuName = 'Standard_B1ms'
param mysqlStorageSizeGB = 32
param mysqlBackupRetentionDays = 7
