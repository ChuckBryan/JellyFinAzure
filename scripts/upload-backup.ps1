#!/usr/bin/env pwsh
# Upload a local Jellyfin backup archive to Azure Files jellyfin-backups share

param(
    [Parameter(Mandatory=$true)]
    [string]$LocalFilePath,
    
    [Parameter(Mandatory=$false)]
    [string]$StorageAccount = "",
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroup = ""
)

Write-Host "=== Upload Jellyfin Backup to Azure Files ===" -ForegroundColor Cyan

# Get values from azd environment if not provided
if ([string]::IsNullOrEmpty($StorageAccount)) {
    $StorageAccount = azd env get STORAGE_ACCOUNT_NAME
    if (-not $StorageAccount) {
        Write-Host "✗ Failed to get STORAGE_ACCOUNT_NAME from azd environment" -ForegroundColor Red
        Write-Host "  Either run 'azd provision' first or provide -StorageAccount parameter" -ForegroundColor Yellow
        exit 1
    }
}

if ([string]::IsNullOrEmpty($ResourceGroup)) {
    $ResourceGroup = azd env get AZURE_RESOURCE_GROUP
    if (-not $ResourceGroup) {
        Write-Host "✗ Failed to get AZURE_RESOURCE_GROUP from azd environment" -ForegroundColor Red
        exit 1
    }
}

# Validate local file exists
if (-not (Test-Path $LocalFilePath)) {
    Write-Host "✗ Local file not found: $LocalFilePath" -ForegroundColor Red
    exit 1
}

$fileInfo = Get-Item $LocalFilePath
Write-Host "Local file: $($fileInfo.FullName)" -ForegroundColor Gray
Write-Host "Size: $([math]::Round($fileInfo.Length / 1MB, 2)) MB" -ForegroundColor Gray

# Get storage account key
Write-Host "`nRetrieving storage account key..." -ForegroundColor Cyan
$key = az storage account keys list -n $StorageAccount -g $ResourceGroup --query [0].value -o tsv 2>$null

if (-not $key) {
    Write-Host "✗ Failed to get storage account key" -ForegroundColor Red
    exit 1
}

# Upload to jellyfin-backups file share
$shareName = "jellyfin-backups"
$remoteFileName = $fileInfo.Name

Write-Host "Uploading to Azure Files share: $shareName" -ForegroundColor Cyan
Write-Host "Remote path: $remoteFileName" -ForegroundColor Gray

try {
    az storage file upload `
        --account-name $StorageAccount `
        --account-key $key `
        --share-name $shareName `
        --source $LocalFilePath `
        --path $remoteFileName `
        --no-progress 2>&1 | Out-Null
    
    if ($LASTEXITCODE -ne 0) {
        throw "Upload command failed with exit code $LASTEXITCODE"
    }
    
    Write-Host "✓ Upload complete" -ForegroundColor Green
    
    # List files in share
    Write-Host "`nFiles in $shareName share:" -ForegroundColor Cyan
    az storage file list `
        --account-name $StorageAccount `
        --account-key $key `
        --share-name $shareName `
        --query "[].{Name:name, Size:properties.contentLength, Modified:properties.lastModified}" `
        -o table
    
    Write-Host "`n✓ Backup uploaded successfully" -ForegroundColor Green
    Write-Host "  The backup will be available to Jellyfin at /data/backups/$remoteFileName" -ForegroundColor Gray
    Write-Host "  JellyRoller can now discover and restore from this archive" -ForegroundColor Gray
    
} catch {
    Write-Host "✗ Upload failed: $_" -ForegroundColor Red
    exit 1
}
