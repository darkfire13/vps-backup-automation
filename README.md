# VPS Backup Automation

## Overview
This repository contains a set of Bash scripts for automating backups on multiple VPS servers. The system securely creates, synchronizes, and stores backups using `rsync` and `rclone`, with Telegram notifications for status updates.

- 📌 For detailed setup and usage of `rclone`, see: [Rclone](https://wiki.dieg.info/rclone)
- 📌 If you need a reliable VPS for hosting your backups, you can find options on: [VPS & VDS Hosting](https://dieg.info/en/vps-vds-hosting/)

## Files in this repository

### 1. `backup_script_vps.sh`
This script runs directly on each VPS to:
- Create daily, weekly, and monthly backups of website files and MySQL databases.
- Compress and organize backups into a structured directory.
- Ensure old backups are rotated according to retention policies.
- Send notifications to Telegram about backup status.

**This script can work autonomously on any VPS** to handle local backup generation.

### 2. `sync_vps_backups.sh`
This script runs on a centralized backup server to:
- Connect via SSH to multiple VPS servers and fetch backups using `rsync`.
- Store retrieved backups in a local directory (`/root/google_sync/`).
- Upload backups to Google Drive using `rclone`, ensuring no files are lost.
- Keep deleted backups in a separate folder (`old_backups/`) on Google Drive for manual removal.
- Send a Telegram notification after sync completion.

### 3. `.backup_env`
A configuration file that stores environment variables such as:
- MySQL credentials (if `.my.cnf` is not used)
- Telegram bot token and chat ID

## Installation and Usage

### Step 1: Clone the repository
```bash
git clone https://github.com/YOUR_USERNAME/vps-backup-automation.git
cd vps-backup-automation
```

### Step 2: Configure environment variables
Create and edit `/root/.backup_env`:
```bash
nano /root/.backup_env
```
Example configuration:
```bash
TELEGRAM_BOT_TOKEN="your_telegram_bot_token"
TELEGRAM_CHAT_ID="your_chat_id"
DB_USER="your_mysql_user"
DB_PASS="your_mysql_password"
```

### Step 3: Set up SSH key authentication
Generate and copy SSH keys to all VPS servers:
```bash
ssh-keygen -t ed25519 -C "backup@server" -f ~/.ssh/id_ed25519
ssh-copy-id -i ~/.ssh/id_ed25519.pub root@your_vps_name
```
Ensure each VPS is added to `/etc/hosts` with a human-readable name.

### Step 4: Set up cron jobs
#### On each VPS (for local backups):
```bash
30 4 * * * /bin/bash /root/backup_script_vps.sh >> /var/log/backup.log 2>&1
```
#### On the backup server (for syncing and Google Drive upload):
```bash
0 6 * * * /bin/bash /root/sync_vps_backups.sh >> /var/log/backup_sync.log 2>&1
```

## Notes
- The `backup_script_vps.sh` can work independently on any VPS to generate backups.
- The `sync_vps_backups.sh` fetches all backups from multiple VPS and uploads them to Google Drive.
- Deleted backups are moved to `old_backups/` on Google Drive instead of being permanently deleted.
- Telegram notifications are sent in case of success or failure.
