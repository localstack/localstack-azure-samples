using 'main.bicep'

param prefix = 'local'
param suffix = 'test'
param imageName = 'custom-image-webapp'
param imageTag = 'v1'
param tags = {
  environment: 'test'
  project: 'custom-image-webapp'
}
