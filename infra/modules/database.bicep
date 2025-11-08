param location string
param resourceToken string
param tags object
param administratorLogin string = 'jellyfinadmin'
@secure()
param administratorPassword string

// Azure SQL Server
resource sqlServer 'Microsoft.Sql/servers@2023-05-01-preview' = {
  name: 'sql-jellyfin-${resourceToken}'
  location: location
  tags: tags
  properties: {
    administratorLogin: administratorLogin
    administratorLoginPassword: administratorPassword
    version: '12.0'
    publicNetworkAccess: 'Enabled'
  }
}

// Jellyfin Database (Serverless)
resource jellyfinDatabase 'Microsoft.Sql/servers/databases@2023-05-01-preview' = {
  parent: sqlServer
  name: 'jellyfin'
  location: location
  tags: tags
  sku: {
    name: 'GP_S_Gen5_1'  // Serverless, 1 vCore
    tier: 'GeneralPurpose'
    family: 'Gen5'
    capacity: 1
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 5368709120  // 5GB max
    catalogCollation: 'SQL_Latin1_General_CP1_CI_AS'
    zoneRedundant: false
    readScale: 'Disabled'
    requestedBackupStorageRedundancy: 'Local'  // Cheapest option
    isLedgerOn: false
    autoPauseDelay: 60  // Auto-pause after 1 hour of inactivity
    minCapacity: json('0.5')  // Minimum 0.5 vCores
  }
}

// Firewall rule to allow Azure services
resource allowAzureServices 'Microsoft.Sql/servers/firewallRules@2023-05-01-preview' = {
  parent: sqlServer
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// Outputs
output serverName string = sqlServer.name
output serverFqdn string = sqlServer.properties.fullyQualifiedDomainName
output databaseName string = jellyfinDatabase.name
output administratorLogin string = administratorLogin
