#!/usr/bin/env pwsh
# Trigger an immediate backup of the Jellyfin database to blob storage
# This version waits for the backup sidecar to run its next cycle

param(
    [Parameter(Mandatory=$false)]
    [string]$StorageAccount = "stjellyfinuopr4dp2rx5jg",
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroup = "rg-jellyfin-eastus-uopr4dp2rx5jg",
    
    [Parameter(Mandatory=$false)]
    [int]$WaitSeconds = 30
)

Write-Host "Checking current backup status..." -ForegroundColor Cyan

# Get storage account key
$key = (az storage account keys list -n $StorageAccount -g $ResourceGroup --query [0].value -o tsv) 2>$null

if (-not $key) {
    Write-Host "✗ Failed to get storage account key" -ForegroundColor Red
    exit 1
}

# Get current latest backup
$currentBackups = az storage blob list `
    --container-name jellyfin-backups `
    --account-name $StorageAccount `
    --account-key $key `
    --query "sort_by([].{Name:name, Modified:properties.lastModified}, &Modified)" `
    -o json 2>$null | ConvertFrom-Json

$latestBefore = $currentBackups | Select-Object -Last 1

if ($latestBefore) {
    Write-Host "Latest existing backup: $($latestBefore.Name) from $($latestBefore.Modified)" -ForegroundColor Gray
} else {
    Write-Host "No existing backups found" -ForegroundColor Yellow
}

Write-Host "`nNote: The backup sidecar runs every 4 hours (14400 seconds) automatically." -ForegroundColor Yellow
Write-Host "To force an immediate backup, the sidecar needs to complete its cycle." -ForegroundColor Yellow
Write-Host "`nOptions:" -ForegroundColor Cyan
Write-Host "  1. Wait for the next scheduled backup (recommended)" -ForegroundColor White
Write-Host "  2. Restart the container app to trigger a new backup cycle" -ForegroundColor White
Write-Host "  3. Reduce BACKUP_INTERVAL_SECONDS in infra and redeploy" -ForegroundColor White

Write-Host "`nWaiting $WaitSeconds seconds to check for new backup..." -ForegroundColor Cyan
Start-Sleep -Seconds $WaitSeconds

# Check again
$newBackups = az storage blob list `
    --container-name jellyfin-backups `
    --account-name $StorageAccount `
    --account-key $key `
    --query "sort_by([].{Name:name, Modified:properties.lastModified}, &Modified)" `
    -o json 2>$null | ConvertFrom-Json

$latestAfter = $newBackups | Select-Object -Last 1

if ($latestAfter -and ($latestAfter.Name -ne $latestBefore.Name)) {
    Write-Host "✓ New backup detected: $($latestAfter.Name)" -ForegroundColor Green
    Write-Host "Created: $($latestAfter.Modified)" -ForegroundColor Gray
} else {
    Write-Host "No new backup yet. The sidecar will create one at its next interval." -ForegroundColor Yellow
    Write-Host "`nTo force immediate backup, restart the app:" -ForegroundColor Cyan
    Write-Host "  az containerapp revision restart -n ca-jellyfin-uopr4dp2rx5jg -g $ResourceGroup --revision <active-revision>" -ForegroundColor Gray
}

Write-Host "`nAll backups:" -ForegroundColor Cyan
$newBackups | Select-Object -Last 5 | Format-Table Name, Modified -AutoSize
