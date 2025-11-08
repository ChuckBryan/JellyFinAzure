#!/usr/bin/env pwsh

# Pre-destroy hook for Jellyfin Azure cleanup
param(
    [string]$AZURE_RESOURCE_GROUP,
    [string]$STORAGE_ACCOUNT_NAME
)

Write-Host "🗑️ Preparing to destroy Jellyfin infrastructure..." -ForegroundColor Yellow
Write-Host ""

# Warn about data loss
Write-Host "⚠️ WARNING: This will permanently delete:" -ForegroundColor Red
Write-Host "  • SQL Server database (all Jellyfin configuration and metadata)"
Write-Host "  • All uploaded media files in Azure Storage"
Write-Host "  • All monitoring data"
Write-Host "  • The entire resource group: $AZURE_RESOURCE_GROUP"
Write-Host ""

# Backup reminder
Write-Host "💾 Backup Reminder:" -ForegroundColor Cyan
Write-Host "  • Download important media from Azure Storage Explorer"
Write-Host "  • Export SQL Server database if you want to preserve configuration"
Write-Host "  • Azure SQL Database automatic backups will also be deleted"
Write-Host ""

# Cost savings note
Write-Host "💰 After destruction:" -ForegroundColor Green
Write-Host "  • All Azure costs will stop immediately"
Write-Host "  • No residual charges from storage or compute"
Write-Host "  • Budget alerts will be removed"
Write-Host ""

# Confirmation
$confirmation = Read-Host "Type 'DELETE' to confirm destruction of all resources"
if ($confirmation -ne "DELETE") {
    Write-Host "❌ Destruction cancelled. No resources were deleted." -ForegroundColor Red
    exit 1
}

Write-Host "✅ Confirmed. Proceeding with resource destruction..." -ForegroundColor Yellow