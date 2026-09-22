using 'main.bicep'

// deploy.sh exports these; the defaults are what an emulator run uses, and a cloud run overrides
// PREFIX/SUFFIX because the API Management service, storage account and Function App names are
// globally unique on Azure.
param prefix = readEnvironmentVariable('PREFIX', 'local')
param suffix = readEnvironmentVariable('SUFFIX', 'test')
param backendScheme = readEnvironmentVariable('BACKEND_SCHEME', 'http')

// The shared secret is generated per run by deploy.sh and passed via the environment.
param backendSecret = readEnvironmentVariable('BACKEND_SECRET')
