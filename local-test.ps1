# JellyFin Bootstrap Local Testing Helper
# This script provides commands to test various bootstrap scenarios locally

param(
    [Parameter(Mandatory)]
    [ValidateSet("start", "stop", "reset", "test-h1-1", "test-h1-2", "test-h1-3", "test-h1-4", "test-bootstrap", "jellyroller", "logs", "inspect")]
    [string]$Action,
    
    [string]$Service = "jellyfin"
)

function Write-TestHeader {
    param([string]$Title)
    Write-Host ""
    Write-Host "=" * 60 -ForegroundColor Green
    Write-Host "🧪 $Title" -ForegroundColor Green  
    Write-Host "=" * 60 -ForegroundColor Green
}

function Write-Step {
    param([string]$Step)
    Write-Host "📋 $Step" -ForegroundColor Yellow
}

function Write-Success {
    param([string]$Message)
    Write-Host "✅ $Message" -ForegroundColor Green
}

function Write-Error {
    param([string]$Message)
    Write-Host "❌ $Message" -ForegroundColor Red
}

function Write-Info {
    param([string]$Message)
    Write-Host "💡 $Message" -ForegroundColor Blue
}

switch ($Action) {
    "start" {
        Write-TestHeader "Starting JellyFin Local Environment"
        Write-Step "Starting base services (JellyFin + Azurite)..."
        docker-compose up -d jellyfin azurite
        
        Write-Step "Waiting for services to be ready..."
        Start-Sleep 10
        
        Write-Step "Testing JellyFin connectivity..."
        try {
            $response = Invoke-WebRequest -Uri "http://localhost:8096/health" -UseBasicParsing -TimeoutSec 30
            Write-Success "JellyFin is running at http://localhost:8096"
        } catch {
            Write-Error "JellyFin not responding. Check logs with: .\local-test.ps1 logs jellyfin"
        }
        
        Write-Step "Testing Azurite connectivity..."
        try {
            $response = Invoke-WebRequest -Uri "http://localhost:10000" -UseBasicParsing -TimeoutSec 10
            Write-Success "Azurite is running (Blob: 10000, Queue: 10001, Table: 10002)"
        } catch {
            Write-Info "Azurite may still be starting up"
        }
    }
    
    "stop" {
        Write-TestHeader "Stopping JellyFin Local Environment"
        docker-compose down
        Write-Success "All containers stopped"
    }
    
    "reset" {
        Write-TestHeader "Resetting Environment (Simulating Scale-to-Zero)"
        Write-Step "Stopping all containers..."
        docker-compose down
        
        Write-Step "Removing JellyFin config volume (simulating ephemeral storage)..."
        docker volume rm jellyfinazure_jellyfin-config -f
        
        Write-Step "Keeping Azurite data (simulating persistent Azure Files)..."
        
        Write-Step "Restarting services..."
        docker-compose up -d jellyfin azurite
        
        Start-Sleep 10
        Write-Success "Environment reset - JellyFin should show setup wizard"
        Write-Info "Visit http://localhost:8096 to see fresh state"
    }
    
    "test-h1-1" {
        Write-TestHeader "H1.1: Testing JellyRoller Backup Contents"
        
        Write-Step "Starting JellyRoller container..."
        docker-compose run --rm jellyroller jellyroller --help
        
        Write-Info "Manual steps for H1.1:"
        Write-Host "1. Complete setup at http://localhost:8096" -ForegroundColor Cyan
        Write-Host "2. Create test users and configuration" -ForegroundColor Cyan
        Write-Host "3. Run: docker-compose run --rm jellyroller jellyroller create-backup" -ForegroundColor Cyan
        Write-Host "4. Examine backup contents in ./test-backups/" -ForegroundColor Cyan
        Write-Host "5. Reset environment and test restore" -ForegroundColor Cyan
    }
    
    "test-h1-2" {
        Write-TestHeader "H1.2: Testing SQLite Database vs Configuration Files"
        
        Write-Step "Inspecting JellyFin configuration directory..."
        docker-compose exec jellyfin find /config -type f -name "*.db*" -o -name "*.xml" -o -name "*.json" | Sort-Object
        
        Write-Info "Manual steps for H1.2:"
        Write-Host "1. Complete setup at http://localhost:8096" -ForegroundColor Cyan
        Write-Host "2. Run: .\local-test.ps1 inspect" -ForegroundColor Cyan
        Write-Host "3. Run: .\local-test.ps1 reset" -ForegroundColor Cyan
        Write-Host "4. Compare what files exist before/after" -ForegroundColor Cyan
    }
    
    "test-h1-3" {
        Write-TestHeader "H1.3: Testing Setup Wizard Bypass"
        
        Write-Info "Manual steps for H1.3:"
        Write-Host "1. Complete setup at http://localhost:8096" -ForegroundColor Cyan
        Write-Host "2. Copy all files: docker cp jellyfin-server:/config ./saved-config" -ForegroundColor Cyan
        Write-Host "3. Run: .\local-test.ps1 reset" -ForegroundColor Cyan
        Write-Host "4. Copy files back: docker cp ./saved-config/. jellyfin-server:/config" -ForegroundColor Cyan
        Write-Host "5. Restart: docker-compose restart jellyfin" -ForegroundColor Cyan
        Write-Host "6. Test if setup wizard is bypassed" -ForegroundColor Cyan
    }
    
    "test-h1-4" {
        Write-TestHeader "H1.4: Testing Persistent SQLite Storage"
        
        Write-Info "This test uses Docker volumes (persistent by default)"
        Write-Info "Manual steps for H1.4:"
        Write-Host "1. Complete setup at http://localhost:8096" -ForegroundColor Cyan
        Write-Host "2. Create test data (users, libraries)" -ForegroundColor Cyan
        Write-Host "3. Run: docker-compose stop jellyfin" -ForegroundColor Cyan
        Write-Host "4. Run: docker-compose start jellyfin" -ForegroundColor Cyan
        Write-Host "5. Verify data persists and no setup wizard" -ForegroundColor Cyan
        Write-Host "6. Check performance vs ephemeral storage" -ForegroundColor Cyan
    }
    
    "test-bootstrap" {
        Write-TestHeader "Testing Bootstrap Process"
        
        Write-Step "Starting bootstrap simulation..."
        docker-compose --profile bootstrap run --rm jellyfin-bootstrap
        
        Write-Info "For full bootstrap testing:"
        Write-Host "1. Create bootstrap configuration files in ./bootstrap-config/" -ForegroundColor Cyan
        Write-Host "2. Create test backup files in ./test-backups/" -ForegroundColor Cyan
        Write-Host "3. Modify bootstrap container command to run actual bootstrap script" -ForegroundColor Cyan
    }
    
    "jellyroller" {
        Write-TestHeader "Interactive JellyRoller Session"
        Write-Step "Starting JellyRoller container with shell access..."
        docker-compose run --rm jellyroller /bin/sh
    }
    
    "logs" {
        Write-TestHeader "Viewing Logs for $Service"
        docker-compose logs -f $Service
    }
    
    "inspect" {
        Write-TestHeader "Inspecting JellyFin Configuration"
        
        Write-Step "JellyFin configuration directory contents:"
        docker-compose exec jellyfin find /config -type f | Sort-Object
        
        Write-Step "SQLite database files:"
        docker-compose exec jellyfin find /config -name "*.db" -exec ls -la {} \;
        
        Write-Step "Configuration files:"
        docker-compose exec jellyfin find /config -name "*.xml" -exec ls -la {} \;
        
        Write-Step "Docker volume inspection:"
        docker volume ls | Where-Object { $_ -like "*jellyfin*" }
    }
}

# Usage instructions
if ($Action -eq "help") {
    Write-Host ""
    Write-Host "JellyFin Bootstrap Local Testing Helper" -ForegroundColor Green
    Write-Host ""
    Write-Host "Usage: .\local-test.ps1 <action>" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Actions:" -ForegroundColor Yellow
    Write-Host "  start       - Start JellyFin and Azurite services"
    Write-Host "  stop        - Stop all services"
    Write-Host "  reset       - Simulate scale-to-zero (reset config, keep media)"
    Write-Host "  test-h1-1   - Test backup contents (H1.1)"
    Write-Host "  test-h1-2   - Test state mapping (H1.2)"
    Write-Host "  test-h1-3   - Test setup bypass (H1.3)"
    Write-Host "  test-h1-4   - Test persistent storage (H1.4)"
    Write-Host "  jellyroller - Interactive JellyRoller session"
    Write-Host "  logs        - View service logs (specify -Service)"
    Write-Host "  inspect     - Inspect JellyFin configuration"
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor Yellow
    Write-Host "  .\local-test.ps1 start"
    Write-Host "  .\local-test.ps1 logs jellyfin"
    Write-Host "  .\local-test.ps1 reset"
    Write-Host ""
}