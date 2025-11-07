targetScope = 'subscription'

// Parameters
@minLength(1)
@maxLength(64)
@description('Primary location for all resources')
param location string = 'eastus'

@minLength(1)
@description('Name of the the environment which is used to generate a short unique hash used in all resources.')
param environmentName string

@description('Unique identifier for the deployment')
param principalId string = ''

// Generate unique suffix for resources
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var tags = {
  'azd-env-name': environmentName
  project: 'jellyfin-eastus'
  'cost-center': 'personal'
}

// Resource group
resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: 'rg-jellyfin-eastus-${resourceToken}'
  location: location
  tags: tags
}

// Storage module
module storage 'modules/storage.bicep' = {
  name: 'storage'
  scope: rg
  params: {
    location: location
    resourceToken: resourceToken
    tags: tags
    principalId: principalId
  }
}

// Container Apps Environment
module containerAppsEnvironment 'modules/environment.bicep' = {
  name: 'container-apps-environment'
  scope: rg
  params: {
    location: location
    resourceToken: resourceToken
    tags: tags
  }
}

// Jellyfin Container App
module jellyfinApp 'modules/containerapp.bicep' = {
  name: 'jellyfin-app'
  scope: rg
  params: {
    location: location
    resourceToken: resourceToken
    tags: tags
    containerAppsEnvironmentId: containerAppsEnvironment.outputs.environmentId
    storageAccountName: storage.outputs.storageAccountName
  }
}

// Monitoring
module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  scope: rg
  params: {
    location: location
    resourceToken: resourceToken
    tags: tags
  }
}

// Outputs
output AZURE_LOCATION string = location
output AZURE_RESOURCE_GROUP string = rg.name
output JELLYFIN_ENDPOINT string = jellyfinApp.outputs.jellyfinUrl
output STORAGE_ACCOUNT_NAME string = storage.outputs.storageAccountName
output CONTAINER_APP_NAME string = jellyfinApp.outputs.containerAppName