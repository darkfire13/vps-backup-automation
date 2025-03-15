#!/bin/bash

# Server identifier for Telegram notifications
HOSTNAME=$(hostname -f)

# Load environment variables from /root/.backup_env if it exists
if [ -f /root/.backup_env ]; then
    source /root/.backup_env
fi

# Check if required variables are set
if [[ -z "$TELEGRAM_BOT_TOKEN" || -z "$TELEGRAM_CHAT_ID" ]]; then
    echo "Error: TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID is not set!"
    exit 1
fi

# Backup retention settings
KEEP_DAILY=3     # Number of daily backups to keep
KEEP_WEEKLY=2    # Number of weekly backups to keep
KEEP_MONTHLY=1   # Number of monthly backups to keep

# Root directory for backups
BACKUP_ROOT_DIR="/root/backups"
DATE=$(date +"%Y_%m_%d")
DAILY_DIR="$BACKUP_ROOT_DIR/daily/$DATE"
WEEKLY_DIR="$BACKUP_ROOT_DIR/weekly"
MONTHLY_DIR="$BACKUP_ROOT_DIR/monthly"

# Disk partition for free space check (empty = no check)
DISK_PARTITION="/dev/vda2"

# List of site directories to back up
SITE_PATHS=(
    "/var/www/www-root/data/www/site1"
    "/var/www/mirax/data/www/site2"
    "/var/www/sint/data/www/site3"
)

# Function to send Telegram notifications
send_telegram() {
    MESSAGE=$(cat /tmp/backup_log)
    curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
        -d "chat_id=$TELEGRAM_CHAT_ID" \
        -d "text=$MESSAGE" > /dev/null
}

# Function to log errors
log_error() {
    echo "$1" >> /tmp/backup_log
}
# Function to check free disk space
check_disk_space() {
    if [[ -n "$DISK_PARTITION" ]]; then
        FREE_SPACE=$(df -BG "$DISK_PARTITION" | awk 'NR==2 {print $4}' | sed 's/G//')
        if [[ $FREE_SPACE -lt 5 ]]; then
            log_error "Error: Not enough disk space! Only ${FREE_SPACE}GB available on $HOSTNAME."
            send_telegram
            exit 1
        fi
    fi
}

# Cleanup old log
> /tmp/backup_log

# Ensure backup directory exists
mkdir -p $BACKUP_ROOT_DIR

# Check disk space before starting backup (if enabled)
check_disk_space

# Create backup directories
mkdir -p $DAILY_DIR $WEEKLY_DIR $MONTHLY_DIR

echo "Starting backup on $HOSTNAME - $DATE" >> /tmp/backup_log

# MySQL Database Backup
echo "Starting MySQL database backup..." >> /tmp/backup_log

if [ -f /root/.my.cnf ]; then
    echo "Using MySQL credentials from /root/.my.cnf" >> /tmp/backup_log
    DB_LIST=$(mysql -e "SHOW DATABASES;" | awk '{ print $1 }' | grep -v 'Database\|information_schema\|performance_schema\|sys')

    for DB_NAME in $DB_LIST; do
        mysqldump $DB_NAME | gzip > $DAILY_DIR/${DB_NAME}_db_$DATE.sql.gz || log_error "Failed to back up database: $DB_NAME"
    done
else
    if [[ -z "$DB_USER" || -z "$DB_PASS" ]]; then
        log_error "Error: MySQL credentials are not set!"
        send_telegram
        exit 1
    fi

    DB_LIST=$(mysql -u"$DB_USER" -p"$DB_PASS" -e "SHOW DATABASES;" | awk '{ print $1 }' | grep -v 'Database\|information_schema\|performance_schema\|sys')

    for DB_NAME in $DB_LIST; do
        mysqldump -u"$DB_USER" -p"$DB_PASS" $DB_NAME | gzip > $DAILY_DIR/${DB_NAME}_db_$DATE.sql.gz || log_error "Failed to back up database: $DB_NAME"
    done
fi

echo "MySQL database backup completed." >> /tmp/backup_log

# Site Files Backup
echo "Starting site files backup..." >> /tmp/backup_log

for SITE_PATH in "${SITE_PATHS[@]}"; do
    SITE_NAME=$(basename $SITE_PATH)
    tar -czf $DAILY_DIR/${SITE_NAME}_files_$DATE.tar.gz -C $SITE_PATH . || log_error "Failed to archive site files: $SITE_NAME"
done

echo "Site files backup completed." >> /tmp/backup_log

# Cleanup & Rotation
find $BACKUP_ROOT_DIR/daily -mindepth 1 -maxdepth 1 -type d | sort | head -n -$KEEP_DAILY | xargs rm -rf
find $BACKUP_ROOT_DIR/weekly -mindepth 1 -maxdepth 1 -type d | sort | head -n -$KEEP_WEEKLY | xargs rm -rf
find $BACKUP_ROOT_DIR/monthly -mindepth 1 -maxdepth 1 -type d | sort | head -n -$KEEP_MONTHLY | xargs rm -rf

# Move to weekly backup every Sunday
if [ $(date +%u) -eq 7 ]; then
    cp -r $DAILY_DIR $WEEKLY_DIR/
fi

# Move to monthly backup on the 1st of the month
if [ $(date +%d) -eq 1 ]; then
    cp -r $DAILY_DIR $MONTHLY_DIR/
fi

echo "Full backup process completed on $HOSTNAME" >> /tmp/backup_log
send_telegram