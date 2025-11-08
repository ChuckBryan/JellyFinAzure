param location string
param resourceToken string
param tags object
param containerAppsEnvironmentId string
param storageAccountName string
param sqlServerFqdn string
param sqlDatabaseName string
param sqlAdminLogin string
@secure()
param sqlAdminPassword string

// Jellyfin Container App with Managed Identity
resource jellyfinApp 'Microsoft.App/containerApps@2025-01-01' = {
  name: 'ca-jellyfin-${resourceToken}'
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: containerAppsEnvironmentId
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 8096
        transport: 'http'
        allowInsecure: true // HTTPS can be added later via custom domain
      }
      secrets: [
        {
          name: 'storage-account-key'
          value: storageAccount.listKeys().keys[0].value
        }
        {
          name: 'sql-admin-password'
          value: sqlAdminPassword
        }
      ]
    }
    template: {
      containers: [
        {
          image: 'jellyfin/jellyfin:latest'
          name: 'jellyfin'
          env: [
            {
              name: 'JELLYFIN_DATA_DIR'
              value: '/data'
            }
            {
              name: 'JELLYFIN_DB_TYPE'
              value: 'SqlServer'
            }
            {
              name: 'JELLYFIN_DB_SERVER'
              value: sqlServerFqdn
            }
            {
              name: 'JELLYFIN_DB_DATABASE'
              value: sqlDatabaseName
            }
            {
              name: 'JELLYFIN_DB_USER'
              value: sqlAdminLogin
            }
            {
              name: 'JELLYFIN_DB_PASSWORD'
              secretRef: 'sql-admin-password'
            }
          ]
          resources: {
            cpu: json('1')
            memory: '2Gi'
          }
          volumeMounts: [
            {
              volumeName: 'media-volume'
              mountPath: '/media'
            }
            {
              volumeName: 'data-volume'
              mountPath: '/data'
            }
          ]
        }
      ]
      scale: {
        minReplicas: 0 // Allow scale-to-zero when idle
        maxReplicas: 1 // Single instance to minimize costs
        rules: [
          {
            name: 'http-scaling'
            http: {
              metadata: {
                concurrentRequests: '10'
              }
            }
          }
        ]
      }
      volumes: [
        {
          name: 'media-volume'
          storageType: 'AzureFile'
          storageName: 'media-storage'
        }
        {
          name: 'data-volume'
          storageType: 'EmptyDir'
        }
      ]
    }
  }
}

// Storage configurations for Azure Files
resource mediaStorage 'Microsoft.App/managedEnvironments/storages@2025-01-01' = {
  parent: containerAppsEnvironment
  name: 'media-storage'
  properties: {
    azureFile: {
      accountName: storageAccountName
      accountKey: storageAccount.listKeys().keys[0].value
      shareName: 'jellyfin-media'
      accessMode: 'ReadWrite'
    }
  }
}

// Reference to Container Apps Environment (for storage configuration)
resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2025-01-01' existing = {
  name: last(split(containerAppsEnvironmentId, '/'))
}

// RBAC for Container App Managed Identity
resource managedIdentityStorageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(resourceGroup().id, 'jellyfin-storage-rbac')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '0c867c2a-1d8c-454a-a3db-ab2ea1bdc8bb') // Storage File Data SMB Share Contributor
    principalId: jellyfinApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Reference to Storage Account
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageAccountName
}

// Outputs
output containerAppName string = jellyfinApp.name
output jellyfinUrl string = 'https://${jellyfinApp.properties.configuration.ingress.fqdn}'
output managedIdentityPrincipalId string = jellyfinApp.identity.principalId
