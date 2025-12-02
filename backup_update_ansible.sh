#! /bin/bash
. "$HOME/scripts/env.sh"
log_file="/home/james/logs/ansible/backup_update_$(date +"%Y%m%d").log"
export ANSIBLE_LOG_PATH="$log_file"

cd /home/james/ansible

ansible-playbook playbooks/backup_update.yml --vault-password-file .vault-pass.txt && {
    mail_subject="Backup & Update Completed Successfully"
    mail_body="No Issues, log file attached."
} || {
    mail_subject="ERROR: Backup & Update Issues"
    mail_body=$(grep -Ei -B 1 'failed|fatal|error|traceback' "$log_file")
}

echo "$mail_body" | mailx -s "$mail_subject" -A "$log_file" "$MAIL_TO"

sudo reboot
