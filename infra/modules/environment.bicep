param location string
param resourceToken string
param tags object

// Log Analytics Workspace for monitoring (free tier)
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'law-jellyfin-${resourceToken}'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'pergb2018' // Pay-as-you-go, free tier includes 5GB/month
    }
    retentionInDays: 30 // Minimum retention to stay in free tier
    features: {
      searchVersion: 1
    }
  }
}

// Container Apps Environment
resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2025-01-01' = {
  name: 'cae-jellyfin-${resourceToken}'
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsWorkspace.properties.customerId
        sharedKey: logAnalyticsWorkspace.listKeys().primarySharedKey
      }
    }
    zoneRedundant: false // Single zone to minimize costs
  }
}

// Outputs
output environmentId string = containerAppsEnvironment.id
output environmentName string = containerAppsEnvironment.name
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id