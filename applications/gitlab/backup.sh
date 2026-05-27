#!/usr/bin/env bash
# Author: Chriz 97
# Testserver: Oracle Linux 10
# Gitlab Version 19.0

# Exit immediately if a command exits with a non-zero status
set -e

# Configuration-
BACKUP_DIR="/var/backup-gitlab"
CONFIG_BACKUP_DIR="${BACKUP_DIR}/config"
LOG_FILE="/var/log/gitlab_backup.log"
KEEP_DAYS=7
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Ensure backup directories exist with strict permissions
mkdir -p "${BACKUP_DIR}" "${CONFIG_BACKUP_DIR}"
chmod 700 "${BACKUP_DIR}" "${CONFIG_BACKUP_DIR}"

# Redirect stdout and stderr to log file for cron tracking
exec > >(tee -ia "${LOG_FILE}") 2>&1

echo "GitLab Backup Started: $(date)"

# 1. Trigger the core GitLab application backup
echo "Starting GitLab core data backup..."
gitlab-backup create

# 2. Backup configuration and secrets
# WARNING: The secrets file contains the database encryption keys.
# Losing this file means you cannot restore your repositories.
echo "Backing up configuration files..."
tar -czf "${CONFIG_BACKUP_DIR}/gitlab_config_${TIMESTAMP}.tar.gz" -C / etc/gitlab

# 3. Clean up older backups to manage disk space
echo "Cleaning up backups older than ${KEEP_DAYS} days..."
# Delete old core backups (GitLab defaults to /var/opt/gitlab/backups unless changed in gitlab.rb)
# If you moved your default gitlab-backup location, adjust the path below.
find /var/opt/gitlab/backups/ -name "*_gitlab_backup.tar" -type f -mtime +${KEEP_DAYS} -delete

# Delete old configuration archives
find "${CONFIG_BACKUP_DIR}" -name "gitlab_config_*.tar.gz" -type f -mtime +${KEEP_DAYS} -delete

echo "GitLab Backup Completed Successfully: $(date)"

