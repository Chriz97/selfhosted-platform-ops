#!/bin/bash
# =============================================================================
# sonarqube_update.sh — Upgrade SonarQube (real-directory installs only)
#
# Usage : sudo ./sonarqube_update.sh <path-to-sonarqube.zip>
# Example: sudo ./sonarqube_update.sh /tmp/sonarqube-26.2.0.119303.zip
#
#
#
# Author: Chriz97
# Testsystem: Alma Linux 10
# Sonarqube Version: 26.4 (Update from 26.3 to 26.4)
#
# What it does:
#   1. Backs up conf/, data/, and extensions/ to a timestamped archive
#   2. Stops the systemd service
#   3. Extracts the new version alongside the current install
#   4. Migrates preserved directories into the new version
#   5. Swaps the directories (old is renamed, new becomes /opt/sonarqube)
#   6. Fixes ownership, starts the service, and polls /api/system/status
#   7. Prunes old versioned directories beyond MAX_OLD_VERSIONS
#
# Rollback: see the instructions printed at the end of a successful run.
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
SONAR_BASE="/opt/sonarqube"     # Live install path (must be a real directory)
SONAR_USER="sonarqube"          # OS user that owns and runs SonarQube
SONAR_SERVICE="sonarqube"       # systemd service name
SONAR_PORT=9000                 # Port used for the post-start health check
INSTALL_PARENT="/opt"           # Parent directory for extraction and backups

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="/var/log/sonarqube_update_${TIMESTAMP}.log"

# Directories migrated from the old install into the new version.
# - conf       : sonar.properties and wrapper.conf (your site config)
# - data       : embedded H2 DB, search index, and other runtime data
# - logs       : previous log files (useful post-upgrade for comparison)
# - extensions : installed plugins
# - temp       : transient files (safe to carry over; cleaned on startup)
# - scripts    : SonarQube's own shell wrappers (sonar.sh etc.)
# - backups    : backup archives created by this script on previous runs
PRESERVE_DIRS=(conf data logs extensions temp scripts backups)

# How many renamed old-install directories to keep under /opt before pruning
MAX_OLD_VERSIONS=3

# -----------------------------------------------------------------------------
# Logging helpers
# -----------------------------------------------------------------------------
log()     { echo "[INFO]  $*" | tee -a "$LOG_FILE"; }
warn()    { echo "[WARN]  $*" | tee -a "$LOG_FILE"; }
error()   { echo "[ERROR] $*" | tee -a "$LOG_FILE"; exit 1; }
section() { echo -e "\n--- $* ---" | tee -a "$LOG_FILE"; }

# -----------------------------------------------------------------------------
# Pre-flight checks
# -----------------------------------------------------------------------------
section "Pre-flight checks"

[[ $EUID -ne 0 ]]  && error "Run this script as root (sudo)."

ZIP_FILE="${1:-}"
[[ -z "$ZIP_FILE" ]]   && error "Usage: $0 <path-to-sonarqube.zip>"
[[ ! -f "$ZIP_FILE" ]] && error "ZIP file not found: $ZIP_FILE"

command -v unzip     &>/dev/null || error "'unzip' is not installed. Run: dnf install unzip"
command -v systemctl &>/dev/null || error "systemd is not available on this host."

[[ -d "$SONAR_BASE" ]] || error "Current install not found at $SONAR_BASE."
[[ -L "$SONAR_BASE" ]] && error "$SONAR_BASE is a symlink — this script targets real-directory installs only."

# Derive the new version directory name from the zip filename,
# e.g. sonarqube-26.2.0.119303.zip → sonarqube-26.2.0.119303
NEW_VERSION_DIR=$(basename "$ZIP_FILE" .zip)
NEW_EXTRACT_PATH="${INSTALL_PARENT}/${NEW_VERSION_DIR}"
OLD_RENAMED_PATH="${INSTALL_PARENT}/sonarqube_old_${TIMESTAMP}"

log "ZIP file          : $ZIP_FILE"
log "New version dir   : $NEW_VERSION_DIR"
log "Temp extract path : $NEW_EXTRACT_PATH"
log "Old dir rename    : $SONAR_BASE -> $OLD_RENAMED_PATH"
log "Log file          : $LOG_FILE"

# -----------------------------------------------------------------------------
# Backup conf, data, and extensions
# -----------------------------------------------------------------------------
section "Creating backup archive"

BACKUP_DIR="${SONAR_BASE}/backups"
mkdir -p "$BACKUP_DIR"
BACKUP_ARCHIVE="${BACKUP_DIR}/sonarqube_backup_${TIMESTAMP}.tar.gz"

log "Archiving conf/, data/, extensions/ -> $BACKUP_ARCHIVE"
tar -czf "$BACKUP_ARCHIVE" \
    -C "$SONAR_BASE" \
    conf data extensions \
    2>>"$LOG_FILE" || warn "Some files were unreadable during backup (non-fatal)."

log "Backup size: $(du -sh "$BACKUP_ARCHIVE" | cut -f1)"

# -----------------------------------------------------------------------------
# Stop the service
# -----------------------------------------------------------------------------
section "Stopping SonarQube"

if systemctl is-active --quiet "$SONAR_SERVICE"; then
    log "Stopping $SONAR_SERVICE ..."
    systemctl stop "$SONAR_SERVICE"

    for i in {1..60}; do
        systemctl is-active --quiet "$SONAR_SERVICE" || break
        sleep 1
    done

    systemctl is-active --quiet "$SONAR_SERVICE" && \
        error "Service did not stop within 60s. Check: journalctl -u $SONAR_SERVICE -n 30"

    log "Service stopped."
else
    warn "Service '$SONAR_SERVICE' was not running — continuing."
fi

# -----------------------------------------------------------------------------
# Extract the new version
# -----------------------------------------------------------------------------
section "Extracting new version"

if [[ -d "$NEW_EXTRACT_PATH" ]]; then
    warn "Removing stale directory: $NEW_EXTRACT_PATH"
    rm -rf "$NEW_EXTRACT_PATH"
fi

log "Extracting to $INSTALL_PARENT ..."
unzip -q "$ZIP_FILE" -d "$INSTALL_PARENT" 2>>"$LOG_FILE"

[[ -d "$NEW_EXTRACT_PATH" ]] || \
    error "Extraction failed: $NEW_EXTRACT_PATH not found after unzip."

log "Extraction complete."

# -----------------------------------------------------------------------------
# Migrate preserved directories into the new version
# -----------------------------------------------------------------------------
section "Migrating preserved directories"

for DIR in "${PRESERVE_DIRS[@]}"; do
    SRC="${SONAR_BASE}/${DIR}"
    DST="${NEW_EXTRACT_PATH}/${DIR}"
    if [[ -d "$SRC" ]]; then
        log "  Migrating: $DIR"
        rm -rf "$DST"
        cp -a "$SRC" "$DST"
    else
        warn "  Not found, skipping: $SRC"
    fi
done

# -----------------------------------------------------------------------------
# Swap install directories
# -----------------------------------------------------------------------------
section "Swapping directories"

log "Old install: $SONAR_BASE -> $OLD_RENAMED_PATH"
mv "$SONAR_BASE" "$OLD_RENAMED_PATH"

log "New install: $NEW_EXTRACT_PATH -> $SONAR_BASE"
mv "$NEW_EXTRACT_PATH" "$SONAR_BASE"

# -----------------------------------------------------------------------------
# Fix ownership and permissions
# -----------------------------------------------------------------------------
section "Fixing ownership"

chown -R "${SONAR_USER}:${SONAR_USER}" "$SONAR_BASE"
chmod -R 750 "$SONAR_BASE"
log "Ownership set to ${SONAR_USER}:${SONAR_USER}"

# -----------------------------------------------------------------------------
# Start the service
# -----------------------------------------------------------------------------
section "Starting SonarQube"

systemctl start "$SONAR_SERVICE"
log "Waiting for service to become active ..."

STARTED=false
for i in {1..30}; do
    sleep 2
    if systemctl is-active --quiet "$SONAR_SERVICE"; then
        STARTED=true
        break
    fi
done

$STARTED || error "Service failed to reach active state. Check:
  journalctl -u $SONAR_SERVICE -n 50
  tail -f $SONAR_BASE/logs/sonar.log"

log "Service is active."

# -----------------------------------------------------------------------------
# Health check — poll /api/system/status until UP or timeout
# Note: DB migrations after a major upgrade can take several minutes.
# -----------------------------------------------------------------------------
section "Health check (port $SONAR_PORT)"

log "Polling /api/system/status for up to 120 seconds ..."
HEALTHY=false
for i in {1..60}; do
    RESPONSE=$(curl -sf "http://localhost:${SONAR_PORT}/api/system/status" 2>/dev/null || true)
    if echo "$RESPONSE" | grep -q '"status":"UP"'; then
        HEALTHY=true
        break
    fi
    sleep 2
done

if $HEALTHY; then
    log "SonarQube is UP."
else
    warn "Health check timed out — SonarQube may still be running DB migrations."
    warn "Monitor with:"
    warn "  tail -f $SONAR_BASE/logs/sonar.log"
    warn "  tail -f $SONAR_BASE/logs/web.log"
fi

# -----------------------------------------------------------------------------
# Prune old versioned directories
# -----------------------------------------------------------------------------
section "Pruning old installs (keeping $MAX_OLD_VERSIONS)"

mapfile -t OLD_DIRS < <(ls -1dt "${INSTALL_PARENT}"/sonarqube_old_* 2>/dev/null || true)
COUNT=${#OLD_DIRS[@]}

if [[ $COUNT -gt $MAX_OLD_VERSIONS ]]; then
    for DIR in "${OLD_DIRS[@]:$MAX_OLD_VERSIONS}"; do
        log "  Removing: $DIR"
        rm -rf "$DIR"
    done
else
    log "  $COUNT old install(s) present — nothing to prune."
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
section "Update complete"

log "Live install  : $SONAR_BASE  ($NEW_VERSION_DIR)"
log "Old install   : $OLD_RENAMED_PATH  (kept for rollback)"
log "Backup archive: $BACKUP_ARCHIVE"
log "Full log      : $LOG_FILE"

log ""
log "Rollback instructions (if needed):"
log "  sudo systemctl stop $SONAR_SERVICE"
log "  sudo mv $SONAR_BASE ${SONAR_BASE}_failed"
log "  sudo mv $OLD_RENAMED_PATH $SONAR_BASE"
log "  sudo systemctl start $SONAR_SERVICE"
