#!/usr/bin/env pwsh

# Post-deployment hook for Jellyfin Azure setup
param(
    [string]$AZURE_RESOURCE_GROUP,
    [string]$JELLYFIN_ENDPOINT,
    [string]$STORAGE_ACCOUNT_NAME
)

Write-Host "🎬 Jellyfin deployment completed successfully!" -ForegroundColor Green
Write-Host ""

# Display connection information
Write-Host "📊 Deployment Summary:" -ForegroundColor Cyan
Write-Host "  Resource Group: $AZURE_RESOURCE_GROUP"
Write-Host "  Jellyfin URL: $JELLYFIN_ENDPOINT"
Write-Host "  Storage Account: $STORAGE_ACCOUNT_NAME"
Write-Host ""

# Storage Explorer setup instructions
Write-Host "📁 Setting up Azure Storage Explorer for media upload:" -ForegroundColor Yellow
Write-Host "  1. Download Azure Storage Explorer: https://azure.microsoft.com/features/storage-explorer/"
Write-Host "  2. Sign in with your Azure account"
Write-Host "  3. Navigate to Storage Accounts > $STORAGE_ACCOUNT_NAME > File Shares"
Write-Host "  4. Upload media to the jellyfin-media file share"
Write-Host ""

# Recommended folder structure
Write-Host "📂 Recommended folder structure in jellyfin-media:" -ForegroundColor Magenta
Write-Host "  jellyfin-media/"
Write-Host "  ├── movies/"
Write-Host "  │   ├── Movie Name (Year)/"
Write-Host "  │   │   └── Movie Name (Year).mp4"
Write-Host "  ├── tv-shows/"
Write-Host "  │   ├── Show Name/"
Write-Host "  │   │   ├── Season 01/"
Write-Host "  │   │   │   └── S01E01 - Episode Name.mp4"
Write-Host "  └── music/"
Write-Host "      ├── Artist Name/"
Write-Host "      │   ├── Album Name/"
Write-Host "      │   │   └── Track.mp3"
Write-Host ""

# Next steps
Write-Host "🚀 Next Steps:" -ForegroundColor Green
Write-Host "  1. Visit your Jellyfin server: $JELLYFIN_ENDPOINT"
Write-Host "  2. Complete the initial setup wizard"
Write-Host "  3. Configure SQL Server database connection (automatically configured)"
Write-Host "  4. Add media libraries pointing to /media/movies, /media/tv-shows, etc."
Write-Host "  5. Upload your media using Azure Storage Explorer"
Write-Host "  6. Enjoy your personal streaming service!"
Write-Host ""

# Database information
Write-Host "🗄️ Database Setup:" -ForegroundColor Cyan
Write-Host "  • Jellyfin is configured to use Azure SQL Database"
Write-Host "  • All configuration and metadata stored in SQL Server"
Write-Host "  • Automatic backups managed by Azure SQL Database"
Write-Host ""

# Cost monitoring reminder
Write-Host "💰 Cost Monitoring:" -ForegroundColor Red
Write-Host "  • Monitor your usage in Azure Portal > Cost Management"
Write-Host "  • You have budget alerts set at 80% and 100% of $50/month"
Write-Host "  • Container scales to zero when not in use to minimize costs"
Write-Host "  • 100GB storage and bandwidth included in free tier"
Write-Host ""

Write-Host "✅ Setup complete! Happy streaming! 🍿" -ForegroundColor Green