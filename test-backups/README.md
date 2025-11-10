# Test Backups Directory

This directory will contain JellyFin backup files created during testing.

## How backups are created:

```powershell
# Using JellyRoller in Docker container
docker-compose run --rm jellyroller jellyroller create-backup

# Backups will appear in this directory and can be restored with:
docker-compose run --rm jellyroller jellyroller apply-backup --filename <backup-file>
```

## Backup file naming:
JellyRoller typically creates backups with timestamps in the filename.

Example: `jellyfin-backup-2024-11-10-12-34-56.tar.gz`

## Testing with backups:
1. Create a "golden master" backup from fully configured server
2. Use this backup to test restore scenarios
3. Test bootstrap processes that restore from backup on startup