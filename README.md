# Jellyfin Azure Media Server

A cost-optimized Jellyfin media streaming server deployed on Azure using Container Apps, Azure Files, and Managed Identity for secure, scalable media streaming with SyncPlay support.

## 🏗️ Architecture

- **Azure Container Apps**: Serverless container hosting with scale-to-zero
- **Azure Files**: Persistent storage for media and configuration
- **Managed Identity**: Secure, keyless authentication
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

- **Managed Identity**: No stored credentials or keys
- **RBAC**: Least-privilege access to storage
- **HTTPS**: Secure communication (can be enhanced with custom domain)
- **Private networking**: Resources deployed in virtual network

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