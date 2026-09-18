using 'main.bicep'

param prefix = 'local'
param suffix = 'test'

// The shared secret is generated per run by deploy.sh and passed via the environment.
param backendSecret = readEnvironmentVariable('BACKEND_SECRET')
