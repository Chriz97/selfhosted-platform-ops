#!/bin/bash
# Keycloak Backup Script
# Author: Chriz97
# Testsystem: Alma Linux 10
# Keycloak Version: 26.6.1


BACKUP_BASE="/opt/keycloak/backups"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="${BACKUP_BASE}/${TIMESTAMP}"
CURRENT_VERSION=$(readlink /opt/keycloak/current | xargs basename)

echo "=== Keycloak Backup Started: ${TIMESTAMP} ==="
echo "Current version: ${CURRENT_VERSION}"

# Create backup directory
mkdir -p "${BACKUP_DIR}"

# 1. Backup PostgreSQL database
echo "Backing up PostgreSQL database..."
sudo -u postgres pg_dump keycloak > "${BACKUP_DIR}/keycloak-database.sql"
if [ $? -eq 0 ]; then
    echo "✓ Database backup complete"
else
    echo "✗ Database backup failed!"
    exit 1
fi

# 2. Backup current Keycloak installation
echo "Backing up Keycloak installation (${CURRENT_VERSION})..."
tar -czf "${BACKUP_DIR}/keycloak-${CURRENT_VERSION}.tar.gz" \
    -C /opt/keycloak "${CURRENT_VERSION}"
if [ $? -eq 0 ]; then
    echo "✓ Keycloak directory backup complete"
else
    echo "✗ Keycloak directory backup failed!"
    exit 1
fi

# 3. Backup configuration files
echo "Backing up configuration files..."
mkdir -p "${BACKUP_DIR}/configs"
cp /etc/systemd/system/keycloak.service "${BACKUP_DIR}/configs/" 2>/dev/null
cp /etc/keycloak.conf "${BACKUP_DIR}/configs/" 2>/dev/null
if [ $? -eq 0 ]; then
    echo "✓ Configuration backup complete"
fi

# 4. Create restoration instructions
cat > "${BACKUP_DIR}/RESTORE-INSTRUCTIONS.txt" << EOF
Keycloak Backup - ${TIMESTAMP}
Version: ${CURRENT_VERSION}

=== TO RESTORE ===

1. Stop Keycloak:
   systemctl stop keycloak

2. Restore database:
   sudo -u postgres psql keycloak < keycloak-database.sql

3. Restore Keycloak directory:
   cd /opt/keycloak
   tar -xzf ${BACKUP_DIR}/keycloak-${CURRENT_VERSION}.tar.gz

4. Update symlink:
   ln -sfn /opt/keycloak/${CURRENT_VERSION} /opt/keycloak/current

5. Restore configs (if needed):
   cp configs/keycloak.service /etc/systemd/system/
   cp configs/keycloak.conf /etc/
   systemctl daemon-reload

6. Start Keycloak:
   systemctl start keycloak
   systemctl status keycloak

Backup location: ${BACKUP_DIR}
EOF

# 5. Create backup summary
BACKUP_SIZE=$(du -sh "${BACKUP_DIR}" | cut -f1)
cat > "${BACKUP_DIR}/backup-summary.txt" << EOF
Backup Summary
==============
Timestamp: ${TIMESTAMP}
Keycloak Version: ${CURRENT_VERSION}
Backup Size: ${BACKUP_SIZE}
Database: keycloak-database.sql
Installation: keycloak-${CURRENT_VERSION}.tar.gz

Files included:
$(ls -lh "${BACKUP_DIR}")
EOF

echo ""
echo "=== Backup Complete ==="
echo "Backup location: ${BACKUP_DIR}"
echo "Backup size: ${BACKUP_SIZE}"
echo ""
ls -lh "${BACKUP_DIR}"

# Optional: Clean up old backups (keep last 5)
echo ""
echo "Cleaning up old backups (keeping last 5)..."
cd "${BACKUP_BASE}"
ls -t | tail -n +6 | xargs -r rm -rf
echo "✓ Cleanup complete"

