# Local JellyFin Bootstrap Testing

This setup allows you to test JellyFin bootstrap scenarios locally using Docker, eliminating the need for constant Azure deployments during development.

## 🏗️ Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   JellyFin      │    │    Azurite       │    │   JellyRoller   │
│  (Port 8096)    │    │ (Azure Storage   │    │    CLI Tool     │
│                 │    │  Emulator)       │    │                 │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
                    ┌─────────────────────┐
                    │  Docker Network     │
                    │  (jellyfin-network) │
                    └─────────────────────┘
```

## 🚀 Quick Start

### Prerequisites
- Docker Desktop installed and running
- PowerShell (for Windows users)

### Start the Environment
```powershell
# Start JellyFin and Azurite services
.\local-test.ps1 start

# JellyFin will be available at: http://localhost:8096
# Azurite storage emulator will be running on ports 10000-10002
```

### Reset Environment (Simulate Scale-to-Zero)
```powershell
# This simulates what happens when Azure Container Apps scales to zero
# It removes the config volume but keeps persistent storage
.\local-test.ps1 reset
```

### Stop Everything
```powershell
.\local-test.ps1 stop
```

## 🧪 Testing HERO Hypotheses

### H1.1: Backup Contents Analysis
```powershell
# Start the test scenario
.\local-test.ps1 test-h1-1

# Then follow manual steps:
# 1. Complete setup at http://localhost:8096
# 2. Create test users and configuration
# 3. Create backup:
docker-compose run --rm jellyroller jellyroller create-backup

# 4. Examine backup files:
ls ./test-backups/

# 5. Reset environment and test restore
.\local-test.ps1 reset
docker-compose run --rm jellyroller jellyroller apply-backup --filename <backup-file>
```

### H1.2: SQLite vs Configuration Files
```powershell
# Test what gets stored where
.\local-test.ps1 test-h1-2

# Inspect current config:
.\local-test.ps1 inspect

# Complete setup, then inspect again to see what changed
```

### H1.3: Setup Wizard Bypass
```powershell
# Test if copying config files bypasses setup wizard
.\local-test.ps1 test-h1-3

# Manual steps will guide you through:
# 1. Complete setup
# 2. Save config files  
# 3. Reset environment
# 4. Restore config files
# 5. Test bypass
```

### H1.4: Persistent SQLite Storage
```powershell
# Test SQLite on persistent volume
.\local-test.ps1 test-h1-4

# This tests if Docker volumes persist correctly (simulating Azure Files)
```

## 🛠️ Development Workflow

### Interactive JellyRoller Session
```powershell
# Get a shell inside JellyRoller container
.\local-test.ps1 jellyroller

# Then you can run commands like:
# jellyroller --help
# jellyroller get-backups
# jellyroller initialize --username admin --password mypass --server-url http://jellyfin:8096
```

### Inspect Environment
```powershell
# See what files JellyFin created
.\local-test.ps1 inspect

# View logs
.\local-test.ps1 logs jellyfin
.\local-test.ps1 logs azurite
```

## 📁 Directory Structure

```
JellyFinAzure/
├── docker-compose.yml          # Container orchestration
├── local-test.ps1             # Testing helper script
├── bootstrap-config/          # Bootstrap configuration files
├── test-backups/             # Backup storage location
├── test-media/               # Sample media files
└── saved-config/             # Temporary config storage for testing
```

## 🔧 Container Details

### JellyFin Container
- **Image**: `jellyfin/jellyfin:latest`
- **Port**: 8096 → http://localhost:8096
- **Volumes**:
  - `jellyfin-config`: JellyFin configuration and SQLite database
  - `jellyfin-cache`: Cache files
  - `./test-media`: Media files (read-only)

### Azurite Container
- **Image**: `mcr.microsoft.com/azure-storage/azurite:latest`
- **Ports**: 10000 (Blob), 10001 (Queue), 10002 (Table)
- **Purpose**: Simulates Azure Storage for testing

### JellyRoller Container
- **Image**: `swampyfox/jellyroller-runner:latest`
- **Usage**: On-demand for testing bootstrap scenarios
- **Profiles**: `testing` (manual), `bootstrap` (automated)

## 🎯 Benefits of Local Testing

1. **Fast Iteration**: No Azure deployment delays
2. **Cost-Free**: No Azure resource costs during development
3. **Debugging**: Easy access to logs and container inspection
4. **Repeatability**: Consistent test environment
5. **Offline Work**: No internet dependency for testing

## 🔄 Simulating Azure Scenarios

| Azure Behavior | Local Simulation |
|---|---|
| Scale to Zero | `docker-compose down` |
| Scale to One | `docker-compose up` |
| Ephemeral Storage | Remove Docker volume |
| Persistent Storage | Keep Docker volume |
| Azure Files | Azurite + Docker volumes |
| Init Containers | Bootstrap profile containers |

## 📊 Test Results Tracking

As you complete each hypothesis test, update the `BOOTSTRAP_PLAN.md` with results:

```markdown
### Testing Phase: 🔄 IN PROGRESS
- [x] H1.1: Backup contents analysis - PASSED/FAILED
- [ ] H1.2: State mapping (SQLite vs filesystem)
- [ ] H1.3: Setup wizard bypass testing
- [ ] H1.4: Persistent SQLite storage testing
```

This local setup should dramatically speed up your hypothesis testing cycle! 🚀