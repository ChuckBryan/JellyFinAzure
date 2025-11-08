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
- [Database Backups](#-database-backups)
- [Pre-Encode Recommendations](#-pre-encode-recommendations)
- [Troubleshooting](#-troubleshooting)
- [Additional Resources](#-additional-resources)
- [Tags](#-tags)

A cost-optimized Jellyfin media streaming server deployed on Azure using Container Apps, Azure Files, and Managed Identity for secure, scalable media streaming with SyncPlay support.

## 🏗️ Architecture

- **Azure Container Apps**: Serverless container hosting with scale-to-zero
- **Azure Files**: Persistent storage for media; configuration mount is optional and disabled by default to keep the DB local
- **Managed Identity**: System-assigned identity present; storage mounts/backups currently use the storage account key
- **Azure Monitor**: Free tier monitoring and cost alerts
- **Azure Developer CLI**: Complete lifecycle management

## 💰 Cost Optimization

This deployment is designed to maximize Azure's free tier:

- **Container Apps**: 180K vCPU seconds/month free
- **Azure Files**: 100GB storage free
- **Log Analytics**: 5GB logs/month free
- **Bandwidth**: 100GB outbound/month free
- **Scale-to-zero**: No charges when not streaming

**Estimated monthly cost**: $0-10 (within free tier limits)

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

- **Managed Identity**: Enabled on the Container App; not used for storage mounting today
- **Secrets**: Storage account key stored as a Container Apps secret and used by the backup sidecar and Azure Files mounts
- **RBAC**: Role assignment present for Files SMB, though mounts currently use the account key path
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

### Storage Management
```bash
# List file shares
az storage share list --account-name <storage-account> --output table

# Check storage usage
az storage account show-usage --name <storage-account>
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
4. Configure users and access permissions
5. Enable SyncPlay for watch-together functionality
6. Set Published Server URL (Dashboard → Networking): use the Container Apps FQDN shown after deploy, e.g. `https://<your-app>.azurecontainerapps.io`

## 🎉 Watch Party Checklist

- Published URL: Set Jellyfin Dashboard → Networking → "Published server URL" to your Container Apps FQDN so external clients get the right links.
- Users: Create accounts for participants (Dashboard → Users) and assign library access.
- SyncPlay: Enable in Dashboard → Playback → SyncPlay and choose allowed roles.
- Bitrate caps: For each user, set a reasonable max streaming bitrate (e.g., 4–8 Mbps) to control egress.
- Test direct play: Confirm a sample title plays without transcoding before inviting others.
- Cold start: If you need instant start, keep `minReplicas: 1` before the event; otherwise expect a brief cold start when scaled to zero.

## 🔄 Database Backups

SQLite is stored on an ephemeral local volume (`EmptyDir` mounted at `/data`) for reliability. A sidecar container periodically backs up the database to Azure Blob Storage.

### What Is Backed Up
- Source file: `/data/data/jellyfin.db`
- Destination: Blob container `jellyfin-backups`
- Filename pattern: `jellyfin-YYYYMMDDHHMMSS.db` (UTC)
- Media NOT included (media lives on the Azure Files share mounted at `/media`).

### How It Works
**Init container** (`restore-db`):
- Runs before Jellyfin starts.
- Queries blob container for the latest backup (sorted by last modified).
- If found, downloads it to `/data/data/jellyfin.db`.
- If none exists, Jellyfin starts fresh.

**Sidecar** (`backup-agent`):
- Runs alongside Jellyfin continuously.
- Loop every `INTERVAL` seconds (default 14400 = 4h).
- Checks for `SOURCE_DB_PATH` (`/data/data/jellyfin.db`).
- Copies to `/tmp/jellyfin.db` and uploads with `az storage blob upload` using the storage account key secret.

Key environment values (from `infra/modules/containerapp.bicep`):
```
JELLYFIN_DATA_DIR=/data
SOURCE_DB_PATH=/data/data/jellyfin.db
BACKUP_CONTAINER=jellyfin-backups
INTERVAL=14400
```

### Verify Backups
```powershell
$acct = "<storage-account-name>"
$rg   = "<resource-group>"
$key  = (az storage account keys list -n $acct -g $rg --query [0].value -o tsv)
az storage blob list --container-name jellyfin-backups --account-name $acct --account-key $key -o table
```
Expect entries like `jellyfin-YYYYMMDDHHMMSS.db`.

### Manual One-Off Backup
```powershell
az containerapp exec -n <containerapp-name> -g <rg> --container backup-agent --command "bash" -- -lc "TS=$(date +%Y%m%d%H%M%S); cp /data/data/jellyfin.db /tmp/jellyfin.db && az storage blob upload --container-name $BACKUP_CONTAINER --name jellyfin-$TS.db --file /tmp/jellyfin.db --account-name $AZURE_STORAGE_ACCOUNT --account-key $AZURE_STORAGE_KEY --auth-mode key --content-type application/octet-stream"
```

### Restore Procedure
1. List available backups:
   ```powershell
   az storage blob list --container-name jellyfin-backups --account-name $acct --account-key $key -o table
   ```
2. Download chosen blob into `/data` (overwrites current DB):
   ```powershell
   az containerapp exec -n <containerapp-name> -g <rg> --container backup-agent --command "bash" -- -lc "az storage blob download --container-name jellyfin-backups --name <blob-name> --file /data/data/jellyfin.db --account-name $AZURE_STORAGE_ACCOUNT --account-key $AZURE_STORAGE_KEY --auth-mode key --overwrite"
   ```
3. Restart active revision (recommended):
   ```powershell
   az containerapp revision list -n <containerapp-name> -g <rg> -o table
   az containerapp revision restart -n <containerapp-name> -g <rg> --revision <active-revision-name>
   ```

### Adjust Backup Frequency
Change `INTERVAL` env for `backup-agent` in `infra/modules/containerapp.bicep`, then:
```powershell
azd provision
```

### Retention
- Keep last 30–60 backups.
- Optionally enable Storage Lifecycle Management (delete blobs older than X days).

### Backup vs. Scale-to-Zero Trade‑off
- With `minReplicas: 1` (default here): one replica always runs, and the backup sidecar runs on schedule. This costs a small, continuous amount but guarantees periodic backups.
- With `minReplicas: 0`: the app scales to zero when idle, reducing compute cost to near-zero. However, no replicas means no sidecar and therefore no backups while idle. Backups only occur when the app is scaled up (e.g., after a request).

Recommended:
- Keep `minReplicas: 1` during initial setup and periods when you want guaranteed backups.
- If minimizing cost is more important, set `minReplicas: 0` and accept that backups will only run when the app is active.

Commands to toggle:
```powershell
# Allow scale-to-zero
az containerapp update -n <containerapp-name> -g <rg> --min-replicas 0

# Keep always-on backups
az containerapp update -n <containerapp-name> -g <rg> --min-replicas 1
```

### Security
- Uses storage account key in a Container Apps secret.
- Managed identity currently not used for blob ops (could migrate to SAS + MI later).
- Rotate storage account key periodically.

### Troubleshooting Backups
```powershell
az containerapp logs show -n <containerapp-name> -g <rg> --container backup-agent --tail 100
```
Check:
- Blob container exists.
- DB file path present: `az containerapp exec ... --container jellyfin --command "bash" -- -lc "ls -l /data/data"`.
- Correct storage account name/key.

### Why Not Put DB on Azure Files?
SQLite over SMB encounters locking & migration failures. `EmptyDir` avoids that; backups mitigate ephemerality.

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