param location string
param resourceToken string
param tags object
param containerAppsEnvironmentId string
param storageAccountName string
param enableJellyRoller bool = false
param jellyRollerImage string = ''
param jellyfinApiKey string = ''
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
      secrets: concat([
        {
          name: 'storage-account-key'
          value: storageAccount.listKeys().keys[0].value
        }
        {
          name: 'sql-connection-string'
          value: 'Server=tcp:${sqlServerFqdn},1433;Initial Catalog=${sqlDatabaseName};Persist Security Info=False;User ID=${sqlAdminLogin};Password=${sqlAdminPassword};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'
        }
      ], enableJellyRoller && !empty(jellyfinApiKey) ? [
        {
          name: 'jellyfin-api-key'
          value: jellyfinApiKey
        }
      ] : [])
    }
    template: {
      containers: concat([
        {
          image: 'jellyfin/jellyfin:latest'
          name: 'jellyfin'
          env: [
            {
              name: 'JELLYFIN_DATA_DIR'
              value: '/data'
            }
            {
              name: 'ConnectionStrings__DefaultConnection'
              secretRef: 'sql-connection-string'
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
      ], enableJellyRoller && !empty(jellyRollerImage) ? [
        // JellyRoller API-driven backup sidecar (spike)
        {
          image: jellyRollerImage
          name: 'jellyroller-runner'
          env: [
            {
              name: 'JELLYFIN_URL'
              value: 'http://localhost:8096'
            }
            {
              name: 'JELLYFIN_API_KEY'
              secretRef: 'jellyfin-api-key'
            }
            {
              name: 'AZURE_STORAGE_ACCOUNT'
              value: storageAccountName
            }
            {
              name: 'AZURE_STORAGE_KEY'
              secretRef: 'storage-account-key'
            }
            {
              name: 'BLOB_CONTAINER'
              value: 'jellyfin-backups'
            }
            {
              name: 'JELLYROLLER_ENABLED'
              value: 'true'
            }
            {
              name: 'BACKUP_INTERVAL_SECONDS'
              value: '14400'
            }
            {
              name: 'STARTUP_DELAY_SECONDS'
              value: '60'
            }
            {
              name: 'MIN_BACKUP_SIZE_BYTES'
              value: '1000000'
            }
            {
              name: 'RETENTION_KEEP'
              value: '30'
            }
            {
              name: 'RETRY_MAX'
              value: '5'
            }
            {
              name: 'RETRY_BACKOFF_SECONDS'
              value: '15'
            }
          ]
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
          volumeMounts: [
            {
              volumeName: 'data-volume'
              mountPath: '/data'
            }
            {
              volumeName: 'backups-volume'
              mountPath: '/data/backups'
            }
            {
              volumeName: 'backups-volume'
              mountPath: '/data/data/backups'
            }
            {
              volumeName: 'jellyroller-config'
              mountPath: '/home/app/.config/jellyroller'
            }
          ]
        }
      ] : [])
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
      volumes: concat([
        {
          name: 'media-volume'
          storageType: 'AzureFile'
          storageName: 'media-storage'
        }
        {
          name: 'data-volume'
          storageType: 'EmptyDir'
        }
      ], enableJellyRoller ? [
        {
          name: 'jellyroller-config'
          storageType: 'EmptyDir'
        }
      ] : [])
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
  dependsOn: [
    jellyfinApp
  ]
}

// Reference to Storage Account
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageAccountName
}

// Outputs
output containerAppName string = jellyfinApp.name
output jellyfinUrl string = 'https://${jellyfinApp.properties.configuration.ingress.fqdn}'
output managedIdentityPrincipalId string = jellyfinApp.identity.principalId