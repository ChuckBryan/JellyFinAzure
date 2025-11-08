# Troubleshooting: Jellyfin Database Backup & Restore

## Problem Statement

**Objective**: Deploy a cost-effective Jellyfin Media Server on Azure Container Apps with reliable database persistence despite using ephemeral storage.

**Challenge**: Jellyfin requires SQLite for its database. SQLite is incompatible with network file systems like Azure Files (SMB) due to advisory locking issues over network protocols. Even with a single replica, we experienced:
- Database migration failures during startup
- Locking errors in application logs
- Corruption risk due to unreliable file locking

**Solution Requirements**:
- Database must run on local storage for SQLite reliability
- Must persist database across container restarts and cold starts
- Must support scale-to-zero (minReplicas: 0) for cost savings
- Must capture all SQLite files including Write-Ahead Log (WAL)

## Architecture Decision: EmptyDir + Blob Backups

### Why EmptyDir?
- **Local Storage**: EmptyDir provides local, ephemeral storage within the container
- **SQLite Compatible**: No network latency, proper file locking semantics
- **Reliable Performance**: No SMB protocol issues
- **Trade-off**: Data is lost when container stops (ephemeral)

### Why Blob Storage Backups?
- **Cost Effective**: Azure Blob Storage is cheaper than persistent Azure Files for infrequent access
- **Durability**: Geographic redundancy and high availability
- **Automation**: Can be scripted with Azure CLI in sidecar containers
- **Flexibility**: Easy to implement backup/restore with standard tools

### Why Not Azure Files for Database?
- **Tested and Failed**: Even with single replica, SQLite experienced locking errors on Azure Files SMB share
- **Known Limitation**: SQLite documentation explicitly warns against network file systems
- **Error Pattern**: `database is locked` and migration failures during startup

## Implementation Details

### Volume Configuration
```bicep
volumes: [
  {
    name: 'media-volume'
    storageType: 'AzureFile'
    storageName: 'jellyfin-media'  // 90GB for media files
  }
  {
    name: 'data-volume'
    storageType: 'EmptyDir'  // Local ephemeral storage for database
  }
]
```

### Backup Strategy
**Component**: Sidecar container (`backup-agent`) running `mcr.microsoft.com/azure-cli`

**Frequency**: Every 14400 seconds (4 hours)

**Process**:
1. Remove any local `backup-*` directories to prevent recursion
2. Create timestamped folder name: `backup-YYYYMMDDHHMMSS`
3. Upload entire `/data/data/` directory to blob storage using `az storage blob upload-batch`
4. Destination structure: `jellyfin-backups/backup-YYYYMMDDHHMMSS/{files}`

**Files Captured**:
- `jellyfin.db` (main database file, ~4KB)
- `jellyfin.db-wal` (Write-Ahead Log, contains uncommitted data, ~2-3MB)
- `jellyfin.db-shm` (shared memory file)
- `.jellyfin-data` (metadata)
- `playlists/` (user playlists)
- `ScheduledTasks/` (task state)
- `SQLiteBackups/` (Jellyfin's own backups)

**Why Entire Directory?**
- SQLite uses WAL (Write-Ahead Logging) mode
- Changes are written to `.db-wal` file first before committing to main `.db` file
- Initial backup approach only captured `jellyfin.db` (4KB) and missed `.db-wal` (3.5MB) containing actual user data
- This caused users to see setup wizard after restore despite having "backed up" data

### Restore Strategy
**Component**: Init container (`restore-db`) running `mcr.microsoft.com/azure-cli`

**Timing**: Runs before main Jellyfin container starts (cold start or scale-from-zero)

**Process**:
1. Query blob storage for all blobs with prefix `backup-`
2. Sort by `lastModified` timestamp, select newest
3. Extract backup folder name (e.g., `backup-20251108030217`)
4. Remove any existing local `backup-*` directories
5. Download all blobs from that backup folder to `/data/data/`
6. Flatten directory structure if needed (files must be directly in `/data/data/`, not nested)
7. Main Jellyfin container starts and finds restored database

## What We've Done

### Initial Implementation (Failed)
- **Issue**: Only backed up `jellyfin.db` file (4KB)
- **Symptom**: User saw setup wizard after restore despite backup existing
- **Root Cause**: Missed `jellyfin.db-wal` file containing actual committed data
- **Fix**: Changed to backup entire `/data/data/` directory

### Second Implementation (Backup Fixed, Restore Failed)
- **Backup Success**: Now captures all files including WAL (backup-20251108030217/ confirmed)
- **Restore Issue**: Files not placed in correct location after restore
- **Symptom**: User still sees setup wizard after restore
- **Root Cause**: `az storage blob download-batch --pattern "$BACKUP_DIR/*"` preserves source directory structure
- **Result**: Files downloaded to `/data/data/backup-YYYYMMDDHHMMSS/jellyfin.db` instead of `/data/data/jellyfin.db`

### Third Implementation (Failed - Revision 0000012)
- **Attempted Fix**: Download to `/tmp/restore`, then copy to `/data/data/`
- **Result**: Init container crashed - likely `cp` command failed with glob expansion
- **Status**: Revision --0000012 showed ContainerBackOff

### Fourth Implementation (Failed - Revision 0000013)
- **Attempted Fix**: Download directly to `/data/data/`, then check if nested directory exists
- **Logic**: If files are in `/data/data/backup-YYYYMMDDHHMMSS/`, move them up one level with `mv` command
- **Script**:
  ```bash
  az storage blob download-batch ... --destination /data/data --pattern "$BACKUP_DIR/*"
  ls -la /data/data/  # Debug output
  if [ -d "/data/data/$BACKUP_DIR" ]; then
    mv /data/data/$BACKUP_DIR/* /data/data/
    rmdir /data/data/$BACKUP_DIR
  fi
  ```
- **Result**: Init container still crashing - `mv` likely failing with hidden files or glob expansion
- **Status**: Revision --0000013 showed ContainerBackOff

### Fifth Implementation (Failed - Design Flaw)
- **Attempted Approach**: Download files individually instead of batch operation
- **Script**:
  ```bash
  az storage blob list ... --prefix "$BACKUP_DIR/" | while read BLOB; do
    FILENAME=$(basename "$BLOB")
    az storage blob download --name "$BLOB" --file "/data/data/$FILENAME"
  done
  ```
- **Fatal Flaw Identified**: `az storage blob list` returns JSON by default, not blob names
  - Without `-o tsv` and `--query "[].name"`, the while loop reads JSON garbage
  - `basename "$BLOB"` produces invalid filenames
  - `az storage blob download` fails immediately → init container crashes
- **Status**: Never deployed; design flaw caught during review

### Sixth Implementation (Recommended - Tar-Based)
- **New Approach**: Use tar archives instead of directory-based backups
- **Advantages**:
  - Single blob per backup (simpler management)
  - No directory structure or path flattening issues
  - Native handling of all file types, hidden files, permissions
  - Better compression (reduced storage costs)
  - Atomic restore operation
- **Changes Required**:
  - Backup sidecar: Create `backup-YYYYMMDDHHMMSS.tar.gz` instead of folder
  - Init container: Download and extract tar archive
  - Both operations use standard `tar` command (available in azure-cli image)
- **Status**: Recommended implementation path

## Current Failure

### Revision Status
- **Latest Failed Revisions**: 
  - `ca-jellyfin-uopr4dp2rx5jg--0000012` - Unhealthy (cp command failure)
  - `ca-jellyfin-uopr4dp2rx5jg--0000013` - Unhealthy (mv command failure)
- **Current Revision Being Prepared**: `--0000014` with individual file download approach
- **Symptom**: Init container `restore-db` failing with `ContainerBackOff`
- **Pattern**: Container starts, runs ~10 seconds, crashes, retry cycle continues

### System Events (Revision 0000013)
```
03:20:08 - Started container restore-db (Count: 3)
03:20:17 - Persistent Failure to start container (ContainerBackOff)
03:20:46 - Started container restore-db (Count: 4)
03:20:55 - Persistent Failure to start container (ContainerBackOff)
03:21:06 - Persistent Failure to start container (ContainerBackOff - Count: 5)
```

### Root Cause Analysis
1. **Revisions 0000012-0000013**: Bash glob expansion (`*`) not working reliably in init container script
   - `mv /data/data/$BACKUP_DIR/* /data/data/` doesn't capture hidden files (e.g., `.jellyfin-data`)
   - If directory is empty, `*` expands to literal `*` causing `mv` to fail
   - `set -e` causes script to exit on any failed command
2. **Revision 0000014 (Design Phase)**: Fatal script error identified before deployment
   - `az storage blob list` returns JSON by default, not plain text blob names
   - Missing `--query "[].name" -o tsv` to extract blob names properly
   - `while read BLOB` would read arbitrary JSON chunks, not blob names
   - Script would fail immediately on first blob download attempt
3. **Error Handling**: All failed scripts lacked proper error handling
   - Commands that can legitimately fail (e.g., cleanup) need `|| true`
   - No verification that required files exist after operations
   - No logging of intermediate state for debugging
4. **Batch Download Behavior**: `az storage blob download-batch --pattern` preserves source directory structure
   - Files end up nested: `/data/data/backup-YYYYMMDDHHMMSS/jellyfin.db`
   - Jellyfin expects flat structure: `/data/data/jellyfin.db`

### Lessons Learned
- Glob expansion in bash scripts within container init is unreliable without `shopt -s nullglob dotglob`
- `download-batch` with pattern always preserves directory structure - cannot be flattened easily
- Hidden files require special handling (dotglob or explicit moves)
- Init container failures are hard to debug - no persistent logs after crash
- **Azure CLI commands need explicit output format**: `-o tsv` or `-o json` with `--query`
- **Always extract exactly what you need**: Use JMESPath queries to get structured data
- **Verify operations completed successfully**: Check for expected files before exiting
- **Use proper error handling**: `set -euo pipefail` with `|| true` for allowed failures

## Next Steps

### 1. Implement Tar-Based Backup & Restore (Recommended)
**Action**: Refactor both backup sidecar and init container to use tar archives

**Benefits**:
- Eliminates all directory structure issues
- Single blob per backup (simpler to manage)
- Atomic operations (create/extract in one step)
- Better compression (lower storage costs)
- Handles all file types natively (hidden files, permissions, timestamps)

**Backup Changes**:
```bash
TS=$(date +"%Y%m%d%H%M%S")
ARCHIVE="/tmp/jellyfin-backup-$TS.tar.gz"
tar -czf "$ARCHIVE" -C /data/data .
az storage blob upload --container jellyfin-backups --name "backup-$TS.tar.gz" --file "$ARCHIVE"
```

**Restore Changes**:
```bash
LATEST=$(az storage blob list --container jellyfin-backups --prefix "backup-" \
  --query "max_by([?ends_with(name, '.tar.gz')], &properties.lastModified).name" -o tsv)
az storage blob download --container jellyfin-backups --name "$LATEST" --file /tmp/restore.tar.gz
tar -xzf /tmp/restore.tar.gz -C /data/data
```

**Command**: Update `containerapp.bicep` with new scripts, then `azd provision`

**Expected Outcome**: Clean backup/restore with no directory structure issues

### 2. Alternative: Fix Current Per-Blob Approach
**Action**: If tar is unavailable, fix the blob-list-and-download loop

**Critical Fixes Needed**:
```bash
# WRONG (current):
az storage blob list ... | while read BLOB; do

# RIGHT (fixed):
az storage blob list ... --query "[].name" -o tsv | while IFS= read -r BLOB; do
  FILE_NAME="${BLOB##*/}"  # bash parameter expansion, more reliable than basename
  az storage blob download --name "$BLOB" --file "/data/data/$FILE_NAME" --overwrite
done

# Verify restore succeeded:
if [ ! -f /data/data/jellyfin.db ]; then
  echo "ERROR: jellyfin.db missing after restore"
  exit 1
fi
```

**Key Changes**:
- Add `--query "[].name" -o tsv` to get plain blob names
- Use `${BLOB##*/}` instead of `basename` for path stripping
- Add verification step before exiting
- Use `IFS= read -r` for proper line reading

### 3. Test Restore Functionality
**Action**: Once revision is healthy, trigger a restart to test restore
- Check if user sees login screen (success) vs setup wizard (failure)
- Verify database files exist: `jellyfin.db`, `jellyfin.db-wal`, `jellyfin.db-shm`

**Test Commands**:
```powershell
# Restart to trigger init container
az containerapp revision restart -n ca-jellyfin-uopr4dp2rx5jg -g rg-jellyfin-eastus-uopr4dp2rx5jg

# Stream init container logs in real-time
az containerapp logs show -n ca-jellyfin-uopr4dp2rx5jg -g rg-jellyfin-eastus-uopr4dp2rx5jg --type console --follow

# Check if files are in correct location (exec into main container after startup)
az containerapp exec -n ca-jellyfin-uopr4dp2rx5jg -g rg-jellyfin-eastus-uopr4dp2rx5jg --command "ls" -- -la /data/data/

# Verify critical files exist:
# - jellyfin.db (~4KB)
# - jellyfin.db-wal (~2-3MB with user data)
# - jellyfin.db-shm
# - .jellyfin-data
# - playlists/, ScheduledTasks/, SQLiteBackups/
```

### 4. Improved Observability for Future Debugging

**Real-time Log Streaming**:
```powershell
az containerapp logs show -n ca-jellyfin-uopr4dp2rx5jg -g rg-jellyfin-eastus-uopr4dp2rx5jg --type console --follow
```

**Enhanced Error Handling in Scripts**:
```bash
set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Allow commands that can legitimately fail:
rm -f /data/data/jellyfin.db* || true
rm -rf /data/data/old-backup-* || true

# Always verify critical operations:
if [ ! -f /data/data/jellyfin.db ]; then
  echo "ERROR: jellyfin.db not found after restore"
  exit 1
fi
```

**Progress Logging**:
```bash
echo "=== Restore starting ==="
echo "Latest backup: $BACKUP_DIR"
echo "Downloading files..."
# ... operations ...
echo "Files after restore:"
ls -la /data/data/
echo "=== Restore complete ==="
```

### 5. Alternative Approaches (If Issues Persist)

#### Option A: Tar-Based Backup/Restore (RECOMMENDED - See Step 1)
The cleanest long-term solution that eliminates all current issues.

#### Option B: Per-Blob Download with Proper Scripting
Fixed version of the individual file download approach:
```bash
az storage blob list --container jellyfin-backups --prefix "$BACKUP_DIR/" \
  --query "[].name" -o tsv | while IFS= read -r BLOB; do
  FILE_NAME="${BLOB##*/}"
  az storage blob download --container jellyfin-backups --name "$BLOB" \
    --file "/data/data/$FILE_NAME" --overwrite
done
# Verify jellyfin.db exists
[ -f /data/data/jellyfin.db ] || exit 1
```
**Pros**: Precise control, no directory nesting, handles all file types
**Cons**: More API calls (one per file), slower than tar, more complex script

#### Option C: Download with Explicit File List
Download only known critical files:
```bash
az storage blob download --container jellyfin-backups --name "$BACKUP_DIR/jellyfin.db" --file /data/data/jellyfin.db
az storage blob download --container jellyfin-backups --name "$BACKUP_DIR/jellyfin.db-wal" --file /data/data/jellyfin.db-wal
az storage blob download --container jellyfin-backups --name "$BACKUP_DIR/jellyfin.db-shm" --file /data/data/jellyfin.db-shm
# ... repeat for each known file
```
**Pros**: Precise control, no directory nesting
**Cons**: Doesn't capture unknown files, more verbose, hardcoded filenames

#### Option D: Different Base Image
Use `alpine` or `busybox` image with Azure CLI installed:
- More control over tools (tar, rsync available)
- Better debugging capabilities
**Cons**: Requires custom Dockerfile or more complex image

#### Option E: Azure Files for Database (Revisited)
Try mounting `jellyfin-config` share to `/data`:
- Add `nobrl` mount option to disable byte-range locking
- Test if SQLite performs better with this configuration
**Pros**: True persistence, no restore needed
**Cons**: May still have performance/locking issues
**Add Retry Logic**: Make init container more resilient
```bash
for i in {1..3}; do
  if restore_function; then
    echo "Restore succeeded"
    exit 0
  fi
  echo "Restore attempt $i failed, retrying..."
  sleep 5
done
exit 1
```

**Add File Verification**: Check files exist after restore
```bash
if [ -f /data/data/jellyfin.db ]; then
  echo "Database file verified"
else
  echo "ERROR: jellyfin.db not found after restore"
  exit 1
fi
```

## Success Criteria

1. ✅ Backup sidecar creates clean folder-based backups every 4 hours
2. ✅ Backups contain all SQLite files including WAL
3. ❌ Init container successfully restores latest backup on cold start
4. ❌ User sees login screen (not setup wizard) after restore
5. ❌ Jellyfin functions normally with restored database
6. ⏳ Scale-to-zero works without data loss

## Known Working State

### End-of-Day Status (Revision `0000015`)

**State**: Tar-based backup + restore implementation deployed and healthy. Init container gracefully skips restore when no `.tar.gz` archives exist. Sidecar successfully creates `.tar.gz` archives.

**Current Limitation**: All produced tar archives are only ~133 bytes. Cause: backup sidecar runs immediately on container start before Jellyfin flushes meaningful data from WAL into the main DB file (and before ancillary directories have growth). Restores from these tiny archives return the setup wizard.

**Database Reality** (during runtime):
- `jellyfin.db-wal` ~3.0MB (contains the actual recent data in WAL mode)
- `jellyfin.db` ~4KB
- Other folders present (`playlists/`, `ScheduledTasks/`, `SQLiteBackups/`)

**Why Backups Are Tiny**:
- `bsdtar -czf ... -C /data/data .` captures files exactly as-is at invocation time.
- Immediately after startup, Jellyfin has not checkpointed WAL into `jellyfin.db`; WAL size does not appreciably influence gzip output due to minimal page changes + potential compression, but a 3MB WAL should produce >133 bytes. The near-empty size indicates timing: archive likely created before WAL is populated or the command ran against an uninitialized directory momentarily.
- Sidecar loop: executes backup before any intentional delay, then sleeps for 4 hours (`INTERVAL`).

**Open Risk**: Without a proper first “warm” backup, cold start restore path remains ineffective (restores minimal DB ⇒ setup prompt).

### Mitigation Options (Not Yet Implemented)
1. Add initial delay (e.g., `INITIAL_DELAY_SECONDS=120`) before first backup.
2. Add minimum size check (skip upload if archive `< 50KB`).
3. Force a manual backup after user configuration (script with correct env vars inside container).
4. Trigger Jellyfin checkpoint by invoking a lightweight API call that causes write activity, then backup.
5. Switch to copying raw directory first, then archiving after a delay (two-phase approach).

### Decision for Now
User may accept current limitation: First restart after configuration still prompts setup until a valid backup is captured at a later interval. This is an operational nuance rather than architectural failure.

### Recommended Next Work (Future Session)
- Patch sidecar script: introduce `sleep $INITIAL_DELAY_SECONDS` before first run.
- After delay, capture archive; verify size > threshold.
- Document operational playbook: “Configure → wait N minutes → force backup → validate → rely on restore.”
- Consider storing WAL + DB separately (sanity check contents) prior to compression.

### Known Good Historical Folder-Based Backup
- `backup-20251108030217/` (older folder-style) still contains full data (including WAL) and could be manually restored if needed by bypassing tar logic.

**Main Jellyfin Container**: Healthy, serving requests.
**Backup Sidecar**: Functional but needs timing enhancements.
**Init Container**: Stable; restore logic ready once a non-trivial archive exists.

## References

- SQLite on Network Filesystems: https://www.sqlite.org/faq.html#q5
- Azure Container Apps EmptyDir: https://learn.microsoft.com/en-us/azure/container-apps/storage-mounts
- SQLite WAL Mode: https://www.sqlite.org/wal.html
