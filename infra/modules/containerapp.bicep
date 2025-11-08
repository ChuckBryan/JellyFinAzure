param location string
param resourceToken string
param tags object
param containerAppsEnvironmentId string
param storageAccountName string

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
      ]
    }
    template: {
      initContainers: [
        {
          image: 'mcr.microsoft.com/azure-cli'
          name: 'restore-db'
          env: [
            {
              name: 'AZURE_STORAGE_ACCOUNT'
              value: storageAccountName
            }
            {
              name: 'AZURE_STORAGE_KEY'
              secretRef: 'storage-account-key'
            }
            {
              name: 'BACKUP_CONTAINER'
              value: 'jellyfin-backups'
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
          ]
          command: [
            '/bin/bash'
            '-c'
          ]
          args: [
            'LATEST=$(az storage blob list --container-name $BACKUP_CONTAINER --account-name $AZURE_STORAGE_ACCOUNT --account-key $AZURE_STORAGE_KEY --auth-mode key --prefix "backup-" --query "sort_by([?name!=\'\'], &properties.lastModified)[-1].name" -o tsv); if [ -n "$LATEST" ]; then BACKUP_DIR=$(echo $LATEST | cut -d/ -f1); echo "Restoring from $BACKUP_DIR..."; mkdir -p /data/data; find /data/data -maxdepth 1 -type d -name "backup-*" -exec rm -rf {} +; az storage blob download-batch --source $BACKUP_CONTAINER --destination /data/data --account-name $AZURE_STORAGE_ACCOUNT --account-key $AZURE_STORAGE_KEY --pattern "$BACKUP_DIR/*" --auth-mode key && echo "Files downloaded. Checking structure..."; ls -la /data/data/; if [ -d "/data/data/$BACKUP_DIR" ]; then echo "Moving files out of nested directory..."; mv /data/data/$BACKUP_DIR/* /data/data/ && rmdir /data/data/$BACKUP_DIR && echo "Restore complete."; else echo "Files already in correct location. Restore complete."; fi; else echo "No backups found; starting fresh."; fi'
          ]
        }
      ]
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
              name: 'BACKUP_INTERVAL_SECONDS'
              value: '14400' // every 4 hours
            }
            {
              name: 'BACKUP_CONTAINER'
              value: 'jellyfin-backups'
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
        // Sidecar container to periodically back up the SQLite DB to Blob Storage
        {
          image: 'mcr.microsoft.com/azure-cli'
          name: 'backup-agent'
          env: [
            {
              name: 'AZURE_STORAGE_ACCOUNT'
              value: storageAccountName
            }
            {
              name: 'AZURE_STORAGE_KEY'
              secretRef: 'storage-account-key'
            }
            {
              name: 'BACKUP_CONTAINER'
              value: 'jellyfin-backups'
            }

            {
              name: 'INTERVAL'
              value: '14400'
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
          ]
          command: [
            '/bin/bash'
            '-c'
          ]
          args: [
            'while true; do if [ -d /data/data ]; then TS=$(date +%Y%m%d%H%M%S); BACKUP_PATH="backup-$TS"; echo "Starting backup to $BACKUP_PATH..."; find /data/data -maxdepth 1 -type d -name "backup-*" -exec rm -rf {} +; az storage blob upload-batch --source /data/data --destination $BACKUP_CONTAINER --destination-path "$BACKUP_PATH" --account-name $AZURE_STORAGE_ACCOUNT --account-key $AZURE_STORAGE_KEY --auth-mode key --overwrite && echo "Backup $TS complete"; fi; sleep $INTERVAL; done'
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
          name: 'config-volume'
          storageType: 'AzureFile'
          storageName: 'config-storage'
        }
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
resource configStorage 'Microsoft.App/managedEnvironments/storages@2025-01-01' = {
  parent: containerAppsEnvironment
  name: 'config-storage'
  properties: {
    azureFile: {
      accountName: storageAccountName
      accountKey: storageAccount.listKeys().keys[0].value
      shareName: 'jellyfin-config'
      accessMode: 'ReadWrite'
    }
  }
}

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