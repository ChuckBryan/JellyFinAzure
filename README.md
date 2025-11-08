# Jellyfin Azure Media Server

## Table of Contents
- [Architecture](#-architecture)
- [Cost Optimization](#-cost-optimization)
- [Quick Start](#-quick-start)
- [Media Management](#-media-management)
- [Watch Party Checklist](#-watch-party-checklist)
- [Security Features](#-security-features)
- [Monitoring & Alerts](#-monitoring--alerts)
- [Management Commands](#-management-commands)
- [Cleanup](#-cleanup)
- [Resource Naming Convention](#-resource-naming-convention)
- [Jellyfin Configuration](#-jellyfin-configuration)
- [Database Management](#-database-management)
- [Pre-Encode Recommendations](#-pre-encode-recommendations)
- [Troubleshooting](#-troubleshooting)
- [Additional Resources](#-additional-resources)
- [Tags](#-tags)

A cost-optimized Jellyfin media streaming server deployed on Azure using Container Apps, Azure Files, and Managed Identity for secure, scalable media streaming with SyncPlay support.

## 🏗️ Architecture

- **Azure Container Apps**: Serverless container hosting with scale-to-zero
- **Azure SQL Database**: Managed SQL Server database for all Jellyfin data and metadata
- **Azure Files**: Persistent storage for media files only
- **Managed Identity**: System-assigned identity for secure Azure resource access
- **Azure Monitor**: Free tier monitoring and cost alerts
- **Azure Developer CLI**: Complete lifecycle management

## 💰 Cost Optimization

This deployment is designed to maximize Azure's free tier:

- **Container Apps**: 180K vCPU seconds/month free
- **Azure Files**: 100GB storage free
- **Azure SQL Database**: Basic tier with 2GB included
- **Log Analytics**: 5GB logs/month free
- **Bandwidth**: 100GB outbound/month free
- **Scale-to-zero**: No charges when not streaming

**Estimated monthly cost**: $5-15 (Azure SQL Database Basic tier ~$5/month)

## 🚀 Quick Start

### Prerequisites

- Azure CLI installed and logged in

- Azure Developer CLI (`azd`) installed
- Azure subscription with appropriate permissions

### Deployment

1. **Clone and initialize**:
   ```bash
   git clone <repository-url>
   cd JellyFinAzure
   azd auth login
   ```

2. **Deploy infrastructure**:
   ```bash
   azd up
   ```

3. **Follow post-deployment instructions** for Azure Storage Explorer setup

### Environment Variables

During deployment, you'll be prompted for:
- Environment name (e.g., "dev")
- Azure location (configured for "eastus")
- SQL Database administrator password (secure password for database access)

## 📁 Media Management

### Azure Storage Explorer Setup

1. Download [Azure Storage Explorer](https://azure.microsoft.com/features/storage-explorer/)
2. Sign in with your Azure account
3. Navigate to your storage account
4. Upload media to the appropriate file shares

### Recommended Folder Structure

```
jellyfin-media/
├── movies/
│   └── Movie Name (Year)/
│       └── Movie Name (Year).mp4
├── tv-shows/
│   └── Show Name/
│       └── Season 01/
│           └── S01E01 - Episode Name.mp4
└── music/
    └── Artist Name/
        └── Album Name/
            └── Track.mp3
```

## 🔒 Security Features

- **Managed Identity**: Enabled on the Container App for secure Azure resource access
- **Azure SQL Database**: Encrypted at rest and in transit with managed authentication
- **Secrets**: Database credentials stored as Container Apps secrets
- **RBAC**: Role assignments for file share access
- **HTTPS**: Public HTTP ingress by default; can be enhanced with custom domain + managed certificate

## 📊 Monitoring & Alerts

- **Application Insights**: Performance monitoring
- **Log Analytics**: Centralized logging
- **Budget Alerts**: Cost monitoring at 80% and 100% thresholds
- **Health Checks**: Container app availability monitoring

## 🛠️ Management Commands

### Scale Management
```bash
# Scale to zero (stop costs)
az containerapp update --name <app-name> --resource-group <rg-name> --min-replicas 0

# Scale up for use
az containerapp update --name <app-name> --resource-group <rg-name> --min-replicas 1
```

### Database Management
```bash
# Connect to SQL Database (requires Azure CLI)
az sql db show-connection-string --server <sql-server-name> --name <database-name>

# Check database size and usage
az sql db show --resource-group <rg-name> --server <sql-server-name> --name <database-name>
```

### Cost Monitoring
```bash
# Check current costs
az consumption usage list --start-date <YYYY-MM-DD> --end-date <YYYY-MM-DD>
```

## 🗑️ Cleanup

To completely remove all resources and stop all costs:

```bash
azd down
```

This will:
- Delete all Azure resources
- Stop all charges immediately
- Remove monitoring and alerts
- Require confirmation before deletion

## 📋 Resource Naming Convention

All resources follow the pattern: `<type>-jellyfin-<unique-suffix>`

- `rg-jellyfin-eastus-<suffix>`: Resource Group
- `ca-jellyfin-<suffix>`: Container App
- `stjellyfin<suffix>`: Storage Account
- `cae-jellyfin-<suffix>`: Container Apps Environment
- `law-jellyfin-<suffix>`: Log Analytics Workspace

## 🎬 Jellyfin Configuration

After deployment:

1. Navigate to your Jellyfin URL (provided in deployment output)
2. Complete the setup wizard
3. Add media libraries:
   - Movies: `/media/movies`
   - TV Shows: `/media/tv-shows`
   - Music: `/media/music`
4. Configure SQL Server database connection (automatically configured during deployment)
5. Configure users and access permissions
6. Enable SyncPlay for watch-together functionality
7. Set Published Server URL (Dashboard → Networking): use the Container Apps FQDN shown after deploy, e.g. `https://<your-app>.azurecontainerapps.io`

## 🎉 Watch Party Checklist

- Published URL: Set Jellyfin Dashboard → Networking → "Published server URL" to your Container Apps FQDN so external clients get the right links.
- Users: Create accounts for participants (Dashboard → Users) and assign library access.
- SyncPlay: Enable in Dashboard → Playback → SyncPlay and choose allowed roles.
- Bitrate caps: For each user, set a reasonable max streaming bitrate (e.g., 4–8 Mbps) to control egress.
- Test direct play: Confirm a sample title plays without transcoding before inviting others.
- Cold start: If you need instant start, keep `minReplicas: 1` before the event; otherwise expect a brief cold start when scaled to zero.

## �️ Database Management

Jellyfin is configured to use Azure SQL Database for all data storage including configuration, user data, libraries, and metadata.

### Database Features
- **Automatic Backups**: Azure SQL Database automatically creates backups
  - Point-in-time restore for up to 7 days (Basic tier)
  - Geo-redundant backups for disaster recovery
- **High Availability**: Built-in redundancy and failover
- **Encryption**: Data encrypted at rest and in transit
- **Scaling**: Can upgrade database tier as needed

### Database Connection
Jellyfin connects to SQL Server using these environment variables:
- `JELLYFIN_DB_TYPE=SqlServer`
- `JELLYFIN_DB_SERVER`: SQL Server FQDN
- `JELLYFIN_DB_DATABASE`: Database name
- `JELLYFIN_DB_USER`: Admin username
- `JELLYFIN_DB_PASSWORD`: Admin password (from secrets)

### Backup and Recovery
**Automatic Backups:**
- Azure SQL Database handles all backups automatically
- No manual backup scripts needed
- Point-in-time restore available through Azure Portal

**Manual Backup (if needed):**
```bash
# Export database to bacpac file
az sql db export --resource-group <rg-name> --server <server-name> --name <db-name> \
  --admin-user <admin-user> --admin-password <password> \
  --storage-key <storage-key> --storage-key-type StorageAccessKey \
  --storage-uri "https://<storage-account>.blob.core.windows.net/<container>/backup.bacpac"
```

**Restore Database:**
- Use Azure Portal → SQL Database → Restore
- Choose point-in-time or restore from backup file
- Can restore to new database if needed

### Database Monitoring
```bash
# Check database status
az sql db show --resource-group <rg-name> --server <server-name> --name <db-name>

# View database metrics
az monitor metrics list --resource <database-resource-id> --metric "dtu_consumption_percent"
```

### Cost Management
- **Basic Tier**: ~$5/month for 2GB database
- **Upgrade**: Can scale to Standard/Premium tiers as needed
- **Monitor**: Use Azure Cost Management to track database costs

## 🎞️ Pre-Encode Recommendations

Aim for direct play on most clients to avoid CPU-heavy transcoding and reduce bandwidth spikes.

- Container: MP4 or MKV
- Video codec: H.264 (AVC), 8-bit, yuv420p
- Profile/Level: High@4.1 for 1080p; High@3.1–4.0 for 720p
- Rate control: Constant Quality (CRF/RF)
   - 1080p: RF 20–22 (lower = higher quality/bitrate)
   - 720p: RF 18–20
- Encoder preset: x264 "fast" or "veryfast" (balance quality/CPU)
- Audio: AAC (Stereo 160–192 kbps; 5.1 at 320–384 kbps)
- Subtitles: Prefer text (SRT/ASS). Avoid image-based/forced burn-in to keep direct play.
- MP4 tip: Enable "Web Optimized" (moves moov atom to beginning) to improve streaming start.

HandBrake quick steps:
- Preset: "Fast 1080p30" (as a base), then tweak RF and audio as above.
- Video tab: Encoder "H.264 (x264)", Framerate "Same as source" (Constant), Tune "none", Preset "fast/veryfast".
- Audio tab: Mixdown "Stereo" or "5.1", Codec "AAC (avcodec)", Bitrate per above.
- Subtitles tab: Add SRT as soft subs; avoid Burn In unless needed.
- Save your custom preset and batch encode your library.

## 🔧 Troubleshooting

### Container Won't Start
```bash
# Check container logs
az containerapp logs show --name <app-name> --resource-group <rg-name>
```

### Storage Access Issues
```bash
# Verify RBAC assignments
az role assignment list --assignee <managed-identity-id> --resource-group <rg-name>
```

### Cost Overruns
```bash
# Check bandwidth usage
az monitor metrics list --resource <container-app-id> --metric "Requests"
```

## 📚 Additional Resources

- [Jellyfin Documentation](https://jellyfin.org/docs/)
- [Azure Container Apps Documentation](https://docs.microsoft.com/azure/container-apps/)
- [Azure Files Documentation](https://docs.microsoft.com/azure/storage/files/)
- [Azure Developer CLI Documentation](https://docs.microsoft.com/azure/developer/azure-developer-cli/)

## 🏷️ Tags

- jellyfin
- azure
- container-apps
- media-server
- streaming
- cost-optimized
- managed-identity
- azure-files