param location string
param resourceToken string
param tags object
param principalId string

// Storage Account optimized for free tier
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: 'stjellyfin${resourceToken}'
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS' // Cheapest option for free tier
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowSharedKeyAccess: true // Needed for Container Apps file share mounting
  }
}

// File Shares for Jellyfin
resource configFileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-01-01' = {
  name: '${storageAccount.name}/default/jellyfin-config'
  properties: {
    shareQuota: 10 // 10GB for config - well within free tier
    enabledProtocols: 'SMB'
  }
}

resource mediaFileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-01-01' = {
  name: '${storageAccount.name}/default/jellyfin-media'
  properties: {
    shareQuota: 90 // 90GB for media - stays within 100GB free tier
    enabledProtocols: 'SMB'
  }
}

// Blob container for database backups (uploaded by sidecar)
resource backupBlobContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: '${storageAccount.name}/default/jellyfin-backups'
  properties: {
    publicAccess: 'None'
  }
}

// RBAC for user account (Storage Explorer access)
resource userStorageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(principalId)) {
  scope: storageAccount
  name: guid(storageAccount.id, principalId, 'Storage File Data SMB Share Contributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '0c867c2a-1d8c-454a-a3db-ab2ea1bdc8bb') // Storage File Data SMB Share Contributor
    principalId: principalId
    principalType: 'User'
  }
}

// Outputs
output storageAccountName string = storageAccount.name
output storageAccountId string = storageAccount.id
output configShareName string = configFileShare.name
output mediaShareName string = mediaFileShare.name
output backupBlobContainerName string = backupBlobContainer.name