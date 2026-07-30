using 'main.bicep'

param prefix = 'local'
param suffix = 'test'
param runtimeName = 'python'
param webRuntimeVersion = '3.13'
param functionRuntimeVersion = '3.11'

// Secrets are generated per run by deploy.sh and passed via the environment.
param postgresAdminPassword = readEnvironmentVariable('POSTGRES_ADMIN_PASSWORD')
param signKey = readEnvironmentVariable('SIGN_KEY')
param internalToken = readEnvironmentVariable('INTERNAL_TOKEN')
