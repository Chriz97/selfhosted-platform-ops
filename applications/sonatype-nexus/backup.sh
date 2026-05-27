#!/bin/bash
# Sonatype Nexus Backup Script (PostgreSQL)
# Author: Chriz97
# Testserver: Alma Linux 10
# Nexus Version 3.92
# PostgresQL Version: 18

set -e

BACKUP_BASE="/opt/nexus/backups"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="${BACKUP_BASE}/${TIMESTAMP}"
CURRENT_VERSION=$(readlink /opt/nexus/current | xargs basename)
PG_DB="nexus"
PG_USER="nexus"

echo "=== Nexus Backup Started: ${TIMESTAMP} ==="
echo "Current version: ${CURRENT_VERSION}"

# Create backup directory
mkdir -p "${BACKUP_DIR}"

# 1. Stop Nexus for consistent filesystem backup
echo "Stopping Nexus service..."
systemctl stop nexus
echo "✓ Nexus stopped"

# 2. Backup PostgreSQL database
echo "Backing up PostgreSQL database (${PG_DB})..."
sudo -u postgres pg_dump -Fc "${PG_DB}" \
  > "${BACKUP_DIR}/nexus-postgres.dump"
echo "✓ PostgreSQL backup complete"

# 3. Backup sonatype-work directory (blobs, config, cache)
echo "Backing up sonatype-work directory..."
tar -czf "${BACKUP_DIR}/nexus-sonatype-work.tar.gz" \
    -C /opt/nexus sonatype-work
echo "✓ Data directory backup complete"

# 4. Backup current Nexus installation
echo "Backing up Nexus installation (${CURRENT_VERSION})..."
tar -czf "${BACKUP_DIR}/nexus-${CURRENT_VERSION}.tar.gz" \
    -C /opt/nexus "${CURRENT_VERSION}"
echo "✓ Nexus directory backup complete"

# 5. Backup configuration files
echo "Backing up configuration files..."
mkdir -p "${BACKUP_DIR}/configs"
cp /etc/systemd/system/nexus.service "${BACKUP_DIR}/configs/" 2>/dev/null || true
cp /opt/nexus/current/bin/nexus.vmoptions "${BACKUP_DIR}/configs/" 2>/dev/null || true
cp /opt/nexus/sonatype-work/nexus3/etc/nexus.properties "${BACKUP_DIR}/configs/" 2>/dev/null || true
echo "✓ Configuration backup complete"

# 6. Restart Nexus
echo "Restarting Nexus service..."
systemctl start nexus
echo "✓ Nexus restarted"

# 7. Create restoration instructions
cat > "${BACKUP_DIR}/RESTORE-INSTRUCTIONS.txt" << EOF
Nexus Backup - ${TIMESTAMP}
Version: ${CURRENT_VERSION}

=== TO RESTORE (PostgreSQL) ===

1. Stop Nexus:
   systemctl stop nexus

2. Restore PostgreSQL database:
   sudo -u postgres dropdb ${PG_DB}
   sudo -u postgres createdb -O nexus ${PG_DB}
   sudo -u postgres pg_restore -d ${PG_DB} nexus-postgres.dump

3. Restore sonatype-work directory:
   cd /opt/nexus
   rm -rf sonatype-work
   tar -xzf nexus-sonatype-work.tar.gz

4. Restore Nexus installation:
   cd /opt/nexus
   tar -xzf nexus-${CURRENT_VERSION}.tar.gz
   ln -sfn /opt/nexus/${CURRENT_VERSION} /opt/nexus/current

5. Restore configs (if needed):
   cp configs/nexus.vmoptions /opt/nexus/current/bin/
   cp configs/nexus.properties /opt/nexus/sonatype-work/nexus3/etc/
   systemctl daemon-reload

6. Fix permissions:
   chown -R nexus:nexus /opt/nexus

7. Start Nexus:
   systemctl start nexus
   systemctl status nexus

IMPORTANT:
- PostgreSQL database is restored BEFORE starting Nexus
- sonatype-work contains blobs and runtime data
- Verify UI and repositories after restore
EOF

# 8. Backup summary
BACKUP_SIZE=$(du -sh "${BACKUP_DIR}" | cut -f1)
WORK_SIZE=$(du -sh /opt/nexus/sonatype-work | cut -f1)

cat > "${BACKUP_DIR}/backup-summary.txt" << EOF
Backup Summary
==============
Timestamp: ${TIMESTAMP}
Nexus Version: ${CURRENT_VERSION}
Backup Size: ${BACKUP_SIZE}
sonatype-work Size: ${WORK_SIZE}

Files:
$(ls -lh "${BACKUP_DIR}")
EOF

echo ""
echo "=== Backup Complete ==="
echo "Backup location: ${BACKUP_DIR}"
echo "Backup size: ${BACKUP_SIZE}"

# 9. Cleanup old backups (keep last 5)
echo "Cleaning up old backups (keeping last 5)..."
cd "${BACKUP_BASE}"
ls -t | tail -n +6 | xargs -r rm -rf
echo "✓ Cleanup complete"

# 10. Nexus status
echo ""
echo "=== Nexus Status ==="
systemctl status nexus --no-pager -l


