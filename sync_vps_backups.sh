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

# Backup settings
LOCAL_BACKUP_DIR="/root/google_sync"
REMOTE_BACKUP_DIR="remotegd:/Backups"
DATE=$(date +"%Y_%m_%d")

# Disk partition for free space check (empty = no check)
DISK_PARTITION="/dev/vda2"

# List of VPS and backup root paths (use /etc/hosts for human-readable names)
declare -A VPS_BACKUPS=(
    ["pq_austria"]="/root/backups/"
    ["vps2"]="/root/backups/"
    ["vps3"]="/root/backups/"
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

echo "Starting remote backup synchronization on $HOSTNAME - $DATE" >> /tmp/backup_log

# Ensure local backup directory exists
mkdir -p "$LOCAL_BACKUP_DIR"

# Check disk space before starting backup
check_disk_space

# Step 1: Sync backups from each VPS
for VPS in "${!VPS_BACKUPS[@]}"; do
    REMOTE_PATH="${VPS_BACKUPS[$VPS]}"
    LOCAL_VPS_DIR="$LOCAL_BACKUP_DIR/$VPS"

    echo "Checking connection to $VPS..." >> /tmp/backup_log

    # Check if the VPS is reachable
    if ! ping -c 1 -W 2 "$VPS" &> /dev/null; then
        log_error "Warning: VPS $VPS is unreachable. Skipping..."
        continue
    fi

    echo "Syncing all backups from $VPS ($REMOTE_PATH)..." >> /tmp/backup_log

    # Rsync to fetch all backups (daily, weekly, monthly) from remote VPS
    rsync -avz --delete "$VPS:$REMOTE_PATH" "$LOCAL_VPS_DIR/" || {
        log_error "Failed to sync backups from $VPS. Skipping upload to Google Drive."
        continue
    }

    # If the folder is empty after sync, remove it
    if [[ ! "$(ls -A "$LOCAL_VPS_DIR")" ]]; then
        log_error "No backups found for $VPS. Removing empty directory."
        rmdir "$LOCAL_VPS_DIR"
    fi

done

echo "All VPS backups synchronized to $LOCAL_BACKUP_DIR." >> /tmp/backup_log

# Step 2: Sync backups to Google Drive
for VPS in "${!VPS_BACKUPS[@]}"; do
    LOCAL_VPS_DIR="$LOCAL_BACKUP_DIR/$VPS"
    GOOGLE_DRIVE_PATH="$REMOTE_BACKUP_DIR/$VPS"

    # Skip upload if the local directory does not exist
    if [[ ! -d "$LOCAL_VPS_DIR" ]]; then
        log_error "Skipping upload for $VPS: no local backup found."
        continue
    fi

    echo "Uploading all backups for $VPS to Google Drive ($GOOGLE_DRIVE_PATH)..." >> /tmp/backup_log

    # Sync to Google Drive (no auto-deletion)
    rclone sync "$LOCAL_VPS_DIR" "$GOOGLE_DRIVE_PATH" --progress --backup-dir "$REMOTE_BACKUP_DIR/old_backups" || log_error "Failed to upload backups for $VPS to Google Drive"
done

echo "Backup sync to Google Drive completed." >> /tmp/backup_log

# Send report to Telegram
send_telegram
