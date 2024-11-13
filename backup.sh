#!/bin/bash

# update path to env.sh script to export vars
. "$HOME/scripts/env.sh"

# GLOBAL VARIABLES
# mnt="/path/to/mount"    # can add mount here as alternative to sourcing in env.sh
backup_dirs="/root /home /etc /opt /boot"
date=$(date +%Y%m%d)
host=$(hostname)
filename="${host}_bkp_${date}.tar.gz"
backup_dest="$mnt/backup/$host/"

# check log function is defined, attempt to source if not
type -t log > /dev/null || 
. $HOME/scripts/utils.sh || {
    echo "ERROR: log function not porvided & utils.sh cannot be found" 
    exit 1
}

log "Backing up to: $backup_dest"

# check if mount is mounted and exit if not
log "Checking $mnt is mounted"
counter=0
while [[ counter -lt 3 ]]; do
    mountpoint -q "$mnt" && { log "Mount confirmed"; break; }
    sudo mount -a   # mount from fstab 
    sleep 10s
    ((counter++))
done
mountpoint -q "$mnt" || { 
    log "ERROR: Unable to find mount, exiting"
    exit 1
}

# check if backup location exists
[[ -d "$backup_dest" ]] || {
    log "Unable to find $backup_dest, creating"
    mkdir "$backup_dest"
}
[[ -d "$backup_dest" ]] || { log "ERROR: Unable to create $backup_dest, exiting" ; exit 1; }

# define exclude file
[[ -f "$exclude_backup" ]] && 
log "excude list set from env variable" || {
    exclude_backup="$HOME/exclude_backup.txt"
    [[ -f "$exclude_backup" ]] &&
    log "exclude list set from ~/exclude_backup.txt" ||
    log "WARNING: Cannot find exclude list, backing up everyting"
}

[[ -f $exclude_backup ]] &&
tar_command="tar --exclude-from=$exclude_backup -czf $backup_dest$filename $backup_dirs" ||
tar_command="tar -czf $backup_dest$filename $backup_dirs"

# backup to NAS
log "Starting Backup of: $backup_dirs"
sudo bash -c "$tar_command" || {
    log "ERROR: Backup failed"
    exit 1
}
log "Backup Successful"
