#!/bin/bash
# SonarQube Backup Script
# Author: Chriz97
# Testserver: Alma Linux 10
# Sonarqube Version: 26.4


BACKUP_BASE="/opt/sonarqube/backups"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="${BACKUP_BASE}/${TIMESTAMP}"
SONARQUBE_VERSION=$(grep -oP 'sonar.version=\K.*' /opt/sonarqube/lib/sonar-application-*.jar 2>/dev/null || echo "unknown")

echo "=== SonarQube Backup Started: ${TIMESTAMP} ==="
echo "SonarQube installation: /opt/sonarqube"

# Create backup directory
mkdir -p "${BACKUP_DIR}"

# 1. Backup PostgreSQL database
echo "Backing up PostgreSQL database..."
sudo -u postgres pg_dump sonarqube > "${BACKUP_DIR}/sonarqube-database.sql"
if [ $? -eq 0 ]; then
    echo "✓ Database backup complete"
else
    echo "✗ Database backup failed!"
    exit 1
fi

# 2. Stop SonarQube for consistent backup
echo "Stopping SonarQube service..."
systemctl stop sonarqube
sleep 5

# 3. Backup SonarQube data directory (contains plugins, ES data, etc.)
echo "Backing up SonarQube data directory..."
tar -czf "${BACKUP_DIR}/sonarqube-data.tar.gz" \
    -C /opt/sonarqube data
if [ $? -eq 0 ]; then
    echo "✓ Data directory backup complete"
else
    echo "✗ Data directory backup failed!"
fi

# 4. Backup SonarQube extensions directory
echo "Backing up SonarQube extensions..."
tar -czf "${BACKUP_DIR}/sonarqube-extensions.tar.gz" \
    -C /opt/sonarqube extensions
if [ $? -eq 0 ]; then
    echo "✓ Extensions backup complete"
else
    echo "✗ Extensions backup failed!"
fi

# 5. Backup configuration files
echo "Backing up configuration files..."
mkdir -p "${BACKUP_DIR}/configs"
cp /opt/sonarqube/conf/sonar.properties "${BACKUP_DIR}/configs/" 2>/dev/null
cp /etc/systemd/system/sonarqube.service "${BACKUP_DIR}/configs/" 2>/dev/null
cp /etc/nginx/conf.d/sonarqube.mayer-it.net.conf "${BACKUP_DIR}/configs/" 2>/dev/null
cp /etc/sysctl.conf "${BACKUP_DIR}/configs/sysctl.conf.backup" 2>/dev/null
cp /etc/security/limits.conf "${BACKUP_DIR}/configs/limits.conf.backup" 2>/dev/null

if [ $? -eq 0 ]; then
    echo "✓ Configuration backup complete"
fi

# 6. Backup installed plugins list
echo "Creating plugins inventory..."
ls -la /opt/sonarqube/extensions/plugins/ > "${BACKUP_DIR}/installed-plugins.txt" 2>/dev/null

# Start SonarQube again
echo "Starting SonarQube service..."
systemctl start sonarqube
sleep 3
systemctl status sonarqube --no-pager

# 7. Create restoration instructions
cat > "${BACKUP_DIR}/RESTORE-INSTRUCTIONS.txt" << EOF
SonarQube Backup - ${TIMESTAMP}
Installation: /opt/sonarqube

=== TO RESTORE ===

1. Stop SonarQube:
   systemctl stop sonarqube

2. Restore database:
   sudo -u postgres dropdb sonarqube
   sudo -u postgres createdb sonarqube -O sonarqube
   sudo -u postgres psql sonarqube < sonarqube-database.sql

3. Restore data directory:
   cd /opt/sonarqube
   rm -rf data
   tar -xzf ${BACKUP_DIR}/sonarqube-data.tar.gz

4. Restore extensions:
   cd /opt/sonarqube
   rm -rf extensions
   tar -xzf ${BACKUP_DIR}/sonarqube-extensions.tar.gz

5. Restore configurations:
   cp configs/sonar.properties /opt/sonarqube/conf/
   cp configs/sonarqube.service /etc/systemd/system/
   cp configs/sonarqube.mayer-it.net.conf /etc/nginx/conf.d/
   systemctl daemon-reload

6. Fix permissions:
   chown -R sonarqube:sonarqube /opt/sonarqube

7. Start SonarQube:
   systemctl start sonarqube
   systemctl status sonarqube

8. Check logs:
   tail -f /opt/sonarqube/logs/sonar.log

Backup location: ${BACKUP_DIR}
EOF

# 8. Create backup summary
BACKUP_SIZE=$(du -sh "${BACKUP_DIR}" | cut -f1)
cat > "${BACKUP_DIR}/backup-summary.txt" << EOF
Backup Summary
==============
Timestamp: ${TIMESTAMP}
Backup Size: ${BACKUP_SIZE}

Files included:
- Database: sonarqube-database.sql
- Data: sonarqube-data.tar.gz
- Extensions: sonarqube-extensions.tar.gz
- Configs: configs/

Detailed listing:
$(ls -lh "${BACKUP_DIR}")

Installed Plugins:
$(cat "${BACKUP_DIR}/installed-plugins.txt" 2>/dev/null)
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

echo ""
echo "=== Backup Summary ==="
cat "${BACKUP_DIR}/backup-summary.txt"

