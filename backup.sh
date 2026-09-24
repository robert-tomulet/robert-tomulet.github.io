#!/bin/bash
# Backup script for Aces Robotics CMS
# Run via cron daily: 0 2 * * * /var/www/acesrobotics.dev/html/backup.sh

BACKUP_DIR="/var/backups/acesrobotics"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
mkdir -p "$BACKUP_DIR"

cp /var/www/acesrobotics.dev/html/instance/aces.db "$BACKUP_DIR/aces_$TIMESTAMP.db"
rsync -a /var/www/acesrobotics.dev/html/uploads/ "$BACKUP_DIR/uploads_$TIMESTAMP/"

# Keep only last 7 backups
ls -t "$BACKUP_DIR"/aces_*.db | tail -n +8 | xargs -r rm
ls -td "$BACKUP_DIR"/uploads_* | tail -n +8 | xargs -r rm -rf

echo "Backup completed: $TIMESTAMP"
