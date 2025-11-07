param location string
param resourceToken string
param tags object

// Log Analytics Workspace (free tier monitoring)
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'law-jellyfin-${resourceToken}'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'pergb2018' // Pay-as-you-go with 5GB free per month
    }
    retentionInDays: 30 // Minimum retention for cost optimization
    features: {
      searchVersion: 1
      legacy: 0
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Application Insights (free tier)
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'ai-jellyfin-${resourceToken}'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Budget Alert for cost monitoring (optional - requires billing scope)
resource budgetAlert 'Microsoft.Consumption/budgets@2023-11-01' = {
  name: 'budget-jellyfin-${resourceToken}'
  properties: {
    timeGrain: 'Monthly'
    timePeriod: {
      startDate: '2025-12-01'
      endDate: '2026-12-31'
    }
    amount: 50 // $50 monthly budget alert
    category: 'Cost'
    notifications: {
      actual_GreaterThan_80_Percent: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 80
        contactEmails: [
          'cbryan@marathonus.com'
        ]
        thresholdType: 'Actual'
      }
      forecasted_GreaterThan_100_Percent: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 100
        contactEmails: [
          'cbryan@marathonus.com'
        ]
        thresholdType: 'Forecasted'
      }
    }
  }
}

// Output
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id
output applicationInsightsId string = applicationInsights.id
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString