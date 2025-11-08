#!/usr/bin/env pwsh
# List all database backups in blob storage

param(
    [Parameter(Mandatory=$false)]
    [string]$StorageAccount = "stjellyfinuopr4dp2rx5jg",
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroup = "rg-jellyfin-eastus-uopr4dp2rx5jg",
    
    [Parameter(Mandatory=$false)]
    [int]$Last = 20
)

Write-Host "Jellyfin Database Backups" -ForegroundColor Cyan
Write-Host "=========================`n" -ForegroundColor Cyan

# Get storage account key
$key = (az storage account keys list -n $StorageAccount -g $ResourceGroup --query [0].value -o tsv)

# List backups
$backups = az storage blob list `
    --container-name jellyfin-backups `
    --account-name $StorageAccount `
    --account-key $key `
    --query "sort_by([].{Name:name, Modified:properties.lastModified, Size:properties.contentLength}, &Modified)" `
    -o json | ConvertFrom-Json

if ($backups.Count -eq 0) {
    Write-Host "No backups found" -ForegroundColor Yellow
    exit 0
}

Write-Host "Total backups: $($backups.Count)" -ForegroundColor Green
Write-Host "Showing last $Last backups:`n" -ForegroundColor Yellow

$backups | Select-Object -Last $Last | Format-Table `
    Name, `
    @{Label="Modified"; Expression={$_.Modified}}, `
    @{Label="Size (KB)"; Expression={[math]::Round($_.Size/1KB, 2)}} `
    -AutoSize

$latest = $backups | Select-Object -Last 1
Write-Host "`nLatest backup: $($latest.Name)" -ForegroundColor Green
Write-Host "Created: $($latest.Modified)" -ForegroundColor Gray
