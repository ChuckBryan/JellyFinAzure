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
            '''set -euo pipefail; echo "=== Jellyfin restore init container starting ==="; LATEST=$(az storage blob list --container-name "$BACKUP_CONTAINER" --account-name "$AZURE_STORAGE_ACCOUNT" --account-key "$AZURE_STORAGE_KEY" --auth-mode key --prefix "backup-" --query "max_by([?ends_with(name, ''.tar.gz'')], &properties.lastModified).name" -o tsv 2>/dev/null || echo ""); if [ -z "$LATEST" ]; then echo "No tar.gz backups found. Skipping restore; Jellyfin will start fresh."; mkdir -p /data/data; exit 0; fi; echo "Latest backup archive: $LATEST"; mkdir -p /data/data /tmp/restore; echo "Clearing existing DB files..."; rm -f /data/data/jellyfin.db* || true; rm -f /data/data/.jellyfin* || true; rm -rf /data/data/playlists || true; rm -rf /data/data/ScheduledTasks || true; rm -rf /data/data/SQLiteBackups || true; echo "Downloading archive to /tmp/restore.tar.gz..."; az storage blob download --container-name "$BACKUP_CONTAINER" --name "$LATEST" --file /tmp/restore.tar.gz --account-name "$AZURE_STORAGE_ACCOUNT" --account-key "$AZURE_STORAGE_KEY" --auth-mode key --overwrite; echo "Extracting archive into /data/data/..."; bsdtar -xzf /tmp/restore.tar.gz -C /data/data; echo "Contents after extract:"; ls -la /data/data; if [ ! -f /data/data/jellyfin.db ]; then echo "ERROR: jellyfin.db missing after restore"; exit 1; fi; echo "Found jellyfin.db ($(stat -c%s /data/data/jellyfin.db) bytes)"; if [ -f /data/data/jellyfin.db-wal ]; then echo "Found jellyfin.db-wal ($(stat -c%s /data/data/jellyfin.db-wal) bytes)"; fi; rm -f /tmp/restore.tar.gz; echo "=== Jellyfin restore completed successfully ==="'''
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
            '''set -euo pipefail; while true; do if [ -d /data/data ]; then TS=$(date +%Y%m%d%H%M%S); ARCHIVE="/tmp/jellyfin-backup-$TS.tar.gz"; BLOB_NAME="backup-$TS.tar.gz"; echo "Creating archive $ARCHIVE from /data/data..."; bsdtar -czf "$ARCHIVE" -C /data/data .; echo "Uploading $ARCHIVE to container $BACKUP_CONTAINER as $BLOB_NAME..."; az storage blob upload --container-name "$BACKUP_CONTAINER" --name "$BLOB_NAME" --file "$ARCHIVE" --account-name "$AZURE_STORAGE_ACCOUNT" --account-key "$AZURE_STORAGE_KEY" --auth-mode key --overwrite && echo "Backup complete: $BLOB_NAME" && rm -f "$ARCHIVE"; fi; sleep $INTERVAL; done'''
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