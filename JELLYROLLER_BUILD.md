# JellyRoller Runner Build & Deployment

## Build the image locally
```powershell
docker build -t jellyroller-runner:latest -f Dockerfile.jellyroller .
```

## Test locally
```powershell
docker run --rm `
  -e JELLYFIN_URL="http://your-jellyfin:8096" `
  -e JELLYFIN_API_KEY="your-api-key" `
  -e AZURE_STORAGE_ACCOUNT="youraccount" `
  -e AZURE_STORAGE_KEY="yourkey" `
  -e BLOB_CONTAINER="jellyfin-backups" `
  -e JELLYROLLER_ENABLED="true" `
  -e BACKUP_INTERVAL_SECONDS="300" `
  -e STARTUP_DELAY_SECONDS="10" `
  -v /path/to/jellyfin/data:/data `
  jellyroller-runner:latest
```

## Push to GitHub Container Registry
```powershell
# Login
docker login ghcr.io -u YOUR_GITHUB_USERNAME

# Tag
docker tag jellyroller-runner:latest ghcr.io/YOUR_GITHUB_USERNAME/jellyroller-runner:v1.0.0
docker tag jellyroller-runner:latest ghcr.io/YOUR_GITHUB_USERNAME/jellyroller-runner:latest

# Push
docker push ghcr.io/YOUR_GITHUB_USERNAME/jellyroller-runner:v1.0.0
docker push ghcr.io/YOUR_GITHUB_USERNAME/jellyroller-runner:latest
```

## Push to Azure Container Registry
```powershell
# Login
az acr login --name YOUR_ACR_NAME

# Tag
docker tag jellyroller-runner:latest YOUR_ACR_NAME.azurecr.io/jellyroller-runner:v1.0.0
docker tag jellyroller-runner:latest YOUR_ACR_NAME.azurecr.io/jellyroller-runner:latest

# Push
docker push YOUR_ACR_NAME.azurecr.io/jellyroller-runner:v1.0.0
docker push YOUR_ACR_NAME.azurecr.io/jellyroller-runner:latest
```

## Deploy with azd
```powershell
azd deploy --set enableJellyRoller=true `
  --set jellyRollerImage="ghcr.io/YOUR_GITHUB_USERNAME/jellyroller-runner:v1.0.0" `
  --set jellyfinApiKey="YOUR_JELLYFIN_API_KEY"
```

## Get Jellyfin API Key
1. Log into Jellyfin as admin
2. Dashboard → API Keys → New API Key
3. Copy the key and use it in the deployment

## Monitor logs
```powershell
az containerapp logs show `
  -n ca-jellyfin-RESOURCETOKEN `
  -g rg-jellyfin-eastus-RESOURCETOKEN `
  --container jellyroller-runner `
  --type console `
  --follow
```
