#!/bin/bash
# Author: Chriz97
# Testsystem: Alma Linux 10
# Nextcloud Version: 33.04
set -euo pipefail

# === Configuration ===
NEXTCLOUD_PATH="/var/www/nextcloud"
BACKUP_ROOT="/var/backups/nextcloud"

DB_NAME="nextcloud_db"
DB_USER="nextcloud_user"
DB_HOST="/var/run/postgresql"   # usually correct for local Postgres
DB_PORT="5432"

WEB_USER="apache"               # change to www-data on Debian/Ubuntu

TIMESTAMP=$(date +"%F_%H-%M-%S")
BACKUP_DIR="$BACKUP_ROOT/backup_$TIMESTAMP"
TMP_DB_DUMP="/tmp/nextcloud_db_$TIMESTAMP.sql"

# === Ensure backup directory exists ===
mkdir -p "$BACKUP_DIR"

echo "🛠️   Enabling maintenance mode..."
sudo -u "$WEB_USER" php "$NEXTCLOUD_PATH/occ" maintenance:mode --on

# === Dump the PostgreSQL database ===
echo "💾 Dumping PostgreSQL database..."
sudo -u postgres pg_dump \
  --format=custom \
  --file="$TMP_DB_DUMP" \
  --dbname="$DB_NAME"

# === Backup data directory ===
echo "📦 Backing up data directory..."
rsync -Aax "$NEXTCLOUD_PATH/data/" "$BACKUP_DIR/data/"

# === Backup config directory ===
echo "⚙️  Backing up config directory..."
rsync -Aax "$NEXTCLOUD_PATH/config/" "$BACKUP_DIR/config/"

# === Copy database dump ===
cp "$TMP_DB_DUMP" "$BACKUP_DIR/"

# === Compress everything ===
echo "🗜️   Compressing backup..."
tar -czf "$BACKUP_ROOT/nextcloud_backup_$TIMESTAMP.tar.gz" \
  -C "$BACKUP_ROOT" "backup_$TIMESTAMP"

# === Cleanup ===
rm -rf "$BACKUP_DIR"
rm -f "$TMP_DB_DUMP"

echo "✅ Disabling maintenance mode..."
sudo -u "$WEB_USER" php "$NEXTCLOUD_PATH/occ" maintenance:mode --off

echo "✅ Backup completed:"
echo "   $BACKUP_ROOT/nextcloud_backup_$TIMESTAMP.tar.gz"


