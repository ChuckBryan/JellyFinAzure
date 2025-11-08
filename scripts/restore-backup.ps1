#!/usr/bin/env pwsh
# Restore the Jellyfin database from a backup in blob storage

param(
    [Parameter(Mandatory=$false)]
    [string]$BlobName,
    
    [Parameter(Mandatory=$false)]
    [string]$ContainerAppName = "ca-jellyfin-uopr4dp2rx5jg",
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroup = "rg-jellyfin-eastus-uopr4dp2rx5jg",
    
    [Parameter(Mandatory=$false)]
    [string]$StorageAccount = "stjellyfinuopr4dp2rx5jg",
    
    [Parameter(Mandatory=$false)]
    [switch]$Latest
)

Write-Host "Jellyfin Database Restore Tool" -ForegroundColor Cyan
Write-Host "================================`n" -ForegroundColor Cyan

# Get storage account key
$key = (az storage account keys list -n $StorageAccount -g $ResourceGroup --query [0].value -o tsv)

# List available backups
Write-Host "Available backups:" -ForegroundColor Yellow
$backups = az storage blob list `
    --container-name jellyfin-backups `
    --account-name $StorageAccount `
    --account-key $key `
    --query "sort_by([].{Name:name, Modified:properties.lastModified, Size:properties.contentLength}, &Modified)" `
    -o json | ConvertFrom-Json

if ($backups.Count -eq 0) {
    Write-Host "✗ No backups found in blob storage" -ForegroundColor Red
    exit 1
}

# Display backups
$backups | Select-Object -Last 10 | Format-Table Name, Modified, @{Label="Size (KB)"; Expression={[math]::Round($_.Size/1KB, 2)}}

# Determine which backup to restore
if ($Latest) {
    $BlobName = ($backups | Select-Object -Last 1).Name
    Write-Host "`nUsing latest backup: $BlobName" -ForegroundColor Green
} elseif (-not $BlobName) {
    $BlobName = Read-Host "`nEnter backup name to restore (or press Enter for latest)"
    if ([string]::IsNullOrWhiteSpace($BlobName)) {
        $BlobName = ($backups | Select-Object -Last 1).Name
        Write-Host "Using latest backup: $BlobName" -ForegroundColor Green
    }
}

# Confirm
Write-Host "`nThis will overwrite the current database with: $BlobName" -ForegroundColor Yellow
$confirm = Read-Host "Continue? (y/n)"
if ($confirm -ne 'y') {
    Write-Host "Restore cancelled" -ForegroundColor Yellow
    exit 0
}

# Restore
Write-Host "`nRestoring database..." -ForegroundColor Cyan

az containerapp exec `
    -n $ContainerAppName `
    -g $ResourceGroup `
    --container backup-agent `
    --command "/bin/sh" `
    --args "-c" `
    --args "mkdir -p /data/data && az storage blob download --container-name jellyfin-backups --name $BlobName --file /data/data/jellyfin.db --account-name `$AZURE_STORAGE_ACCOUNT --account-key `$AZURE_STORAGE_KEY --auth-mode key --overwrite && echo 'Database restored successfully'"

if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ Database restored successfully" -ForegroundColor Green
    
    # Get active revision
    Write-Host "`nRestarting container app..." -ForegroundColor Cyan
    $revisions = az containerapp revision list -n $ContainerAppName -g $ResourceGroup --query "[?properties.active].name" -o tsv
    
    if ($revisions) {
        $activeRevision = $revisions | Select-Object -First 1
        az containerapp revision restart -n $ContainerAppName -g $ResourceGroup --revision $activeRevision
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ Container app restarted" -ForegroundColor Green
            Write-Host "`nRestore complete! Your Jellyfin server should now have the restored database." -ForegroundColor Green
        } else {
            Write-Host "⚠ Database restored but restart failed. Restart manually." -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "✗ Restore failed" -ForegroundColor Red
    exit 1
}
