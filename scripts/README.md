# Jellyfin Azure - Management Scripts

Quick PowerShell scripts for common Jellyfin database backup operations.

## Prerequisites

- Azure CLI installed and authenticated (`az login`)
- PowerShell 7+ recommended (works with Windows PowerShell 5.1)

## Scripts

### `list-backups.ps1`
List all database backups in blob storage.

```powershell
# List last 20 backups (default)
.\scripts\list-backups.ps1

# List last 50 backups
.\scripts\list-backups.ps1 -Last 50
```

### `backup-now.ps1`
Trigger an immediate backup of the current database.

```powershell
# Create a backup now
.\scripts\backup-now.ps1
```

### `restore-backup.ps1`
Restore a database backup from blob storage.

```powershell
# Interactive: select from list
.\scripts\restore-backup.ps1

# Restore latest backup automatically
.\scripts\restore-backup.ps1 -Latest

# Restore specific backup
.\scripts\restore-backup.ps1 -BlobName "jellyfin-20251107234345.db"
```

## Default Values

All scripts use these defaults (can be overridden with parameters):
- Container App: `ca-jellyfin-uopr4dp2rx5jg`
- Resource Group: `rg-jellyfin-eastus-uopr4dp2rx5jg`
- Storage Account: `stjellyfinuopr4dp2rx5jg`

Override example:
```powershell
.\scripts\backup-now.ps1 -ContainerAppName "my-app" -ResourceGroup "my-rg"
```

## Notes

- Backups are stored in the `jellyfin-backups` blob container
- Backup naming: `jellyfin-YYYYMMDDHHMMSS.db` (UTC timestamp)
- Restore operations will restart the container app automatically
- The init container restores the latest backup on every cold start
