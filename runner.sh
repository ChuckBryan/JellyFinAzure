#!/bin/bash
set -euo pipefail

# Configuration from environment variables
JELLYFIN_URL="${JELLYFIN_URL:-http://localhost:8096}"
JELLYFIN_API_KEY="${JELLYFIN_API_KEY:-}"
AZURE_STORAGE_ACCOUNT="${AZURE_STORAGE_ACCOUNT:-}"
AZURE_STORAGE_KEY="${AZURE_STORAGE_KEY:-}"
BLOB_CONTAINER="${BLOB_CONTAINER:-jellyfin-backups}"
JELLYROLLER_ENABLED="${JELLYROLLER_ENABLED:-false}"
BACKUP_INTERVAL_SECONDS="${BACKUP_INTERVAL_SECONDS:-14400}"
STARTUP_DELAY_SECONDS="${STARTUP_DELAY_SECONDS:-60}"
MIN_BACKUP_SIZE_BYTES="${MIN_BACKUP_SIZE_BYTES:-1000000}"
RETENTION_KEEP="${RETENTION_KEEP:-30}"
RETRY_MAX="${RETRY_MAX:-5}"
RETRY_BACKOFF_SECONDS="${RETRY_BACKOFF_SECONDS:-15}"

JELLYFIN_BACKUP_DIR="/data/backups"
BLOB_PREFIX="jellyroller"

log() {
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"
}

check_jellyfin_health() {
    log "Checking Jellyfin availability at $JELLYFIN_URL..."
    for i in $(seq 1 "$RETRY_MAX"); do
        if curl -sf "$JELLYFIN_URL/System/Info/Public" >/dev/null 2>&1; then
            log "Jellyfin is ready"
            return 0
        fi
        log "Jellyfin not ready (attempt $i/$RETRY_MAX), waiting ${RETRY_BACKOFF_SECONDS}s..."
        sleep "$RETRY_BACKOFF_SECONDS"
    done
    log "ERROR: Jellyfin not available after $RETRY_MAX attempts"
    return 1
}

configure_jellyroller() {
    if [ -z "$JELLYFIN_API_KEY" ]; then
        log "ERROR: JELLYFIN_API_KEY not set"
        return 1
    fi
    
    # Create config file for JellyRoller
    mkdir -p ~/.config/jellyroller
    cat > ~/.config/jellyroller/config.toml <<EOF
server_url = "$JELLYFIN_URL"
api_key = "$JELLYFIN_API_KEY"
EOF
    log "JellyRoller configured"
}

create_backup() {
    log "=== Starting backup ==="

    mkdir -p "$JELLYFIN_BACKUP_DIR"

    if ! jellyroller create-backup; then
        log "ERROR: create-backup failed"
        return 1
    fi

    log "Waiting for backup to register..."
    sleep 5

    local backup_info
    backup_info=$(jellyroller get-backups -o json 2>/dev/null | jq -r '.[0]' || echo "")
    if [ -z "$backup_info" ] || [ "$backup_info" = "null" ]; then
        log "ERROR: No backup found after create-backup"
        return 1
    fi

    local backup_path
    backup_path=$(echo "$backup_info" | jq -r '.Path')
    if [ -z "$backup_path" ] || [ "$backup_path" = "null" ]; then
        log "ERROR: Could not determine backup path"
        return 1
    fi
    log "Backup reported path: $backup_path"

    local archive_file
    archive_file="${JELLYFIN_BACKUP_DIR}/$(basename "$backup_path")"

    # Wait for file appearance & stabilization
    local prev_size=0 curr_size=0
    for i in $(seq 1 12); do
        if [ ! -f "$archive_file" ]; then
            log "Waiting for archive file ($i/12)..."
            sleep 2
            continue
        fi
        curr_size=$(stat -c%s "$archive_file" 2>/dev/null || echo 0)
        if [ "$curr_size" -gt 0 ] && [ "$curr_size" -eq "$prev_size" ]; then
            break
        fi
        prev_size=$curr_size
        sleep 2
    done

    if [ ! -f "$archive_file" ]; then
        log "ERROR: Archive file not found at $archive_file"
        return 1
    fi

    local file_size
    file_size=$(stat -c%s "$archive_file" 2>/dev/null || echo 0)
    if [ "$file_size" -lt "$MIN_BACKUP_SIZE_BYTES" ]; then
        log "WARNING: Archive too small ($file_size < $MIN_BACKUP_SIZE_BYTES), skipping upload"
        return 1
    fi
    log "Archive ready: $(basename "$archive_file") ($file_size bytes)"

    local sha256
    sha256=$(sha256sum "$archive_file" | awk '{print $1}')
    log "SHA256: $sha256"

    local timestamp blob_name
    timestamp=$(date -u +%Y%m%d%H%M%S)
    blob_name="${BLOB_PREFIX}/backup-${timestamp}-$(basename "$archive_file")"
    log "Uploading blob: $blob_name"

    if ! az storage blob upload \
        --account-name "$AZURE_STORAGE_ACCOUNT" \
        --account-key "$AZURE_STORAGE_KEY" \
        --container-name "$BLOB_CONTAINER" \
        --name "$blob_name" \
        --file "$archive_file" \
        --overwrite \
        --metadata "source=jellyroller" "size=$file_size" "sha256=$sha256" "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"; then
        log "ERROR: Azure CLI upload failed"
        return 1
    fi
    log "Upload complete"

    log "last_backup_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ) size_bytes=$file_size"
    apply_retention
    log "=== Backup complete ==="
    return 0
}

apply_retention() {
    log "Applying retention policy (keep $RETENTION_KEEP)..."
    local names
    names=$(az storage blob list \
        --account-name "$AZURE_STORAGE_ACCOUNT" \
        --account-key "$AZURE_STORAGE_KEY" \
        --container-name "$BLOB_CONTAINER" \
        --prefix "$BLOB_PREFIX/" \
        --query "sort_by([?properties.contentLength > \`0\` && (ends_with(name, '.zip') || ends_with(name, '.tar.gz'))].{n:name,t:properties.lastModified}, &t)[].n" -o tsv 2>/dev/null || true)

    local count
    count=$(echo "$names" | grep -c . || echo 0)
    if [ "$count" -le "$RETENTION_KEEP" ]; then
        log "Retention OK ($count <= $RETENTION_KEEP)"
        return 0
    fi
    local prune=$((count - RETENTION_KEEP))
    log "Pruning $prune old backup(s)"
    echo "$names" | head -n "$prune" | while IFS= read -r old; do
        [ -z "$old" ] && continue
        log "Deleting old blob: $old"
        az storage blob delete --account-name "$AZURE_STORAGE_ACCOUNT" --account-key "$AZURE_STORAGE_KEY" --container-name "$BLOB_CONTAINER" --name "$old" || log "WARN: Failed to delete $old"
    done
}

main() {
    log "JellyRoller backup runner starting"
    
    if [ "$JELLYROLLER_ENABLED" != "true" ]; then
        log "JELLYROLLER_ENABLED is not true, exiting"
        exit 0
    fi
    
    if [ -z "$AZURE_STORAGE_ACCOUNT" ] || [ -z "$AZURE_STORAGE_KEY" ]; then
        log "ERROR: Azure Storage credentials not set"
        exit 1
    fi
    
    # Initial delay
    log "Waiting ${STARTUP_DELAY_SECONDS}s before first backup..."
    sleep "$STARTUP_DELAY_SECONDS"
    
    # Check Jellyfin health
    if ! check_jellyfin_health; then
        log "ERROR: Jellyfin health check failed, exiting"
        exit 1
    fi
    
    # Configure JellyRoller
    if ! configure_jellyroller; then
        log "ERROR: JellyRoller configuration failed, exiting"
        exit 1
    fi
    
    # Backup loop
    while true; do
        if create_backup; then
            log "Backup succeeded"
        else
            log "WARNING: Backup failed, will retry on next interval"
        fi
        
        log "Sleeping for ${BACKUP_INTERVAL_SECONDS}s..."
        sleep "$BACKUP_INTERVAL_SECONDS"
    done
}

main
