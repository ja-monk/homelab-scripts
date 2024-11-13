#!/bin/bash

# update path to env.sh script to export vars
. "$HOME/scripts/env.sh"

# source utils.sh for log function
. "$SCRIPT_DIR/utils.sh"

# create list to exclude from update by reading exclude_file
create_exclude_list() {
    log "Reading list to exclude from $exclude_update"
    while read line; do
        # if line begins with '#' then ignore
        [[ $line =~ ^# ]] || exclude+=($line)
    done < $exclude_update
    # create pipe seperated list for egrep command
    printf -v exclude_piped '%s|' "${exclude[@]}"
}

# make sure host is turned on before continuing
host_on_check() {
    host_init_state="off"
    local i=0
    while ((i<3)); do
        local on_flag=false
        log "Checking host is turned on"
        ping -c 10 "$ip_host" 1>/dev/null 2>&1

        if [[ $? == 0 ]]; then
            log "Confirmed host is on"
            local on_flag=true
            [[ $i -eq 0 ]] && host_init_state="on"
            break
        fi

        log "Failed to ping host. Attempting to turn on"
        wakeonlan -i "$BROADCAST_IP" "$mac_addr"
        log "Waiting 5 mins for services to start"
        sleep 5m
        ((i++))
    done

    [[ $on_flag == "false" ]] && log "ERROR: Failed to start host" && exit 1
}

find_cts() {
    log "Checking for CTs and applying exclusions"
    local cts_string=$(ssh $user@$ip_host "sudo pct list" | egrep -v ${exclude_piped%|} | awk -F ' ' 'NR>1 { print $1 }')   
    # convert newline delimited string to array
    [[ -z  $cts_string ]] || readarray cts <<< "$cts_string"
}

find_vms() {
    log "Checking for VMs and applying exclusions"
    local vms_string=$(ssh $user@$ip_host "sudo qm list" | egrep -v ${exclude_piped%|} | awk -F ' ' 'NR>1 { print $1 }')
    # convert newline delimited string to array
    [[ -z  $vms_string ]] || readarray vms <<< "$vms_string"
}

check_found() {
    [[ ${#cts[@]} -gt 0 || ${#vms[@]} -gt 0 ]] || { 
        log "ERROR: Could not find any CTs or VMs to update" &&
        exit 1
    }
    
    [[ ${#cts[@]} -gt 0 ]] && log "found ${#cts[@]} CT(s) to update: $(echo ${cts[@]})" ||
    log "WARNING: Could not find any CTs to update"

    [[ ${#vms[@]} -gt 0 ]] && log "found ${#vms[@]} VM(s) to update: $(echo ${vms[@]})" ||
    log "WARNING: Could not find any VMs to update"    
}

start_cts() {
    log "Starting CTs"
    for i in ${cts[@]}; do
        log "Starting CT $i"
        local status_check=$(ssh $user@$ip_host "sudo pct status $i")

        # ${var##*: } removes longest possible pattern from start of var which ends with ': '
        # here status check returns for example 'status: running', which is trimmed to 'running'
        local j=0
        while [[ ! "${status_check##*: }" == "running" && "$j" < 3 ]]; do        
            log "CT $i stopped, starting container"
            ssh $user@$ip_host "sudo pct start $i"
            log "Waiting 2 mins"
            sleep 2m
            local status_check=$(ssh $user@$ip_host "sudo pct status $i")
            ((j++))
        done
        
        [[ "${status_check##*: }" == "running" ]] && log "CT $i is running" || {
            log "ERROR: Failed to start CT $i"
        }
    done
}

start_vms() {
    log "Starting VMs"
    for i in ${vms[@]}; do
        log "Starting VM $i"
        local status_check=$(ssh $user@$ip_host "sudo qm status $i")

        # ${var##*: } removes longest possible pattern from start of var which ends with ': '
        # here status check returns for example 'status: running', which is trimmed to 'running'
        local j=0
        while [[ ! "${status_check##*: }" == "running" && "$j" < 3 ]]; do        
            log "VM $i stopped, attempting to start"
            ssh $user@$ip_host "sudo qm start $i"
            log "Waiting 2 mins"
            sleep 2m
            local status_check=$(ssh $user@$ip_host "sudo qm status $i")
            ((j++))
        done
        
        [[ "${status_check##*: }" == "running" ]] && log "VM $i is running" || {
            log "ERROR: Failed to start VM $i"
        }
    done
}

update_ct() {
    local status_check=$(ssh $user@$ip_host "sudo pct status $1")
    # ${var##*: } removes longest possible pattern from start of var which ends with ': '
    # here status check returns for example 'status: running', which is trimmed to 'running'
    [[ "${status_check##*: }" == "running" ]] || {
        log "WARNING: CT $1 not running, skipping" && 
        return 1 
    }

    local hostname=$(ssh $user@$ip_host "sudo pct exec $1 hostname")
    local os=$(ssh $user@$ip_host "sudo pct config $1" | awk -F ': ' '{ if ($1=="ostype") print $2 }')
    log "Updating CT $1: $hostname"

    # script relies on apt package manager, can add further distros that use apt
    [[ "$os" == "debian" || "$os" == "ubuntu" ]] || {
        log "WARNING: Skipping due to unrecognised OS: $os" &&
        return 1
    }

    ssh $user@$ip_host "sudo pct exec $1 -- apt-get update" > /dev/null || {
        log "ERROR: apt-get update error CT $1" &&
        return 1
    }
    
    ssh $user@$ip_host "sudo pct exec $1 -- apt-get upgrade -y" > /dev/null || {
        log "ERROR: apt-get upgrade error CT $1" &&
        return 1
    }
}

update_vm() {
    local status_check=$(ssh $user@$ip_host "sudo qm status $1")
    # ${var##*: } removes longest possible pattern from start of var which ends with ': '
    # here status check returns for example 'status: running', which is trimmed to 'running'
    [[ "${status_check##*: }" == "running" ]] || {
        log "WARNING: VM $1 not running, skipping" && 
        return 1 
    }

    # qm returns info in JSON, parse with jq  
    local hostname=$(ssh $user@$ip_host "sudo qm agent $1 get-host-name" | jq -r '."host-name"')
    local os=$(ssh $user@$ip_host "sudo qm agent $1 get-osinfo" | jq -r '."id"')
    log "Updating VM $1: $hostname"

    # script relies on apt package manager, can add further distros that use apt
    [[ "$os" == "debian" || "$os" == "ubuntu" ]] || {
        log "WARNING: Skipping due to unrecognised OS: $os" &&
        return 1
    }

    # execute apt update on vm
    ssh $user@$ip_host "sudo qm guest exec $1 --timeout 0 -- apt-get update" > /dev/null || {
        log "ERROR: apt-get update error VM $1" &&
        return 1
    } 
    
    # execute apt upgrade on vm
    ssh $user@$ip_host "sudo qm guest exec $1 --timeout 0 -- bash -c 'apt-get upgrade -y'" > /dev/null || {
        log "ERROR: apt-get upgrade error VM $1" &&
        return 1
    }
}

initial_state() {
    # return host to initial on/off state
    [[ $host_init_state == "on" ]] && {
        log "Host was on ... will restart"
        log "Shuttting down host"
        ssh $user@$ip_host 'bash -s' < $SCRIPT_DIR/prox/shutdown_prox.sh
        log "Sleeping 2 mins"
        sleep 2m
        log "Starting host"
        $SCRIPT_DIR/prox/wake_prox.sh     
    } || {
        log "Host was off ... Shutting Down"
        # shutdown script used to shutdown VMs & CTs in safe order
        ssh $user@$ip_host 'bash -s' < $SCRIPT_DIR/prox/shutdown_prox.sh
    }
}

backup_ct() {
    log "Starting Backup process for CT $1"

    # parse JSON to obtain IP
    local ct_ip=$(ssh $user@$ip_host sudo pct exec $1 -- ip -j a | jq -r '.[] | 
    select(."ifname"=="eth0") | ."addr_info" | .[] | 
    select(."family"=="inet") | ."local"') 
    
    # ** TODO: Validate IP **

    # test ssh connection 
    ssh -o BatchMode=yes -o ConnectTimeout=300 $user@$ct_ip exit && {
        log "SSH connection to CT $1 confirmed"
    } || {
        log "ERROR: SSH issue for CT $1"
        return 1
    }

    # check if exclude_backup.txt exists and attempt to copy over if not
    log "checking for exlcude_backup.txt file"
    file_check=$(ssh $user@$ct_ip '[[ -f $HOME/exclude_backup.txt ]] && echo "true" || echo "false"')
    [[ "$file_check" == "true" ]] && log "exclude_backup.txt file confirmed" || {
        log "exclude_backup.txt not found, attempting to scp"
        scp "$exclude_backup" $user@$ct_ip:~/
    }

    log "Running backup script on CT $1"

    # run backup script on CT, redirect stdout & stderr to log file
    ssh -o BatchMode=yes -o ConnectTimeout=300 $user@$ct_ip "bash -c '
        $(declare -f log)
        $(cat $SCRIPT_DIR/backup.sh)
    '" >> $log_file 2>&1 &&
    log "Backup of CT $1 complete successfully" || {
        log "ERROR: Backup script failed on CT $1"
        return 1
    } 
}

backup_vm() {
    log "Starting Backup process for VM $1"

    # parse JSON to obtain IP
    local vm_ip=$(ssh $user@$ip_host sudo qm guest exec $1 -- ip -j a | \
    jq -r '."out-data"' | jq -r '.[] | 
    select(."ifname"=="ens18") | ."addr_info" | .[] | 
    select(."family"=="inet") | ."local"')

    # ** TODO: Validate IP **

    # test ssh connection
    ssh -o BatchMode=yes -o ConnectTimeout=300 $user@$vm_ip exit && {
        log "SSH connection to VM $1 confirmed"
    } || {
        log "ERROR: SSH issue for VM $1"
        return 1
    }

    log "checking for exlcude_backup.txt file"
    file_check=$(ssh $user@$vm_ip '[[ -f $HOME/exclude_backup.txt ]] && echo "true" || echo "false"')
    [[ "$file_check" == "true" ]] && log "exclude_backup.txt file confirmed" || {
        log "exclude_backup.txt not found, attempting to scp"
        scp "$exclude_backup" $user@$vm_ip:~/
    }

    log "Running backup script on VM $1"

    # run backup script on VM, redirect stdout & stderr to log file
    ssh -o BatchMode=yes -o ConnectTimeout=300 $user@$vm_ip "bash -c '
        $(declare -f log)
        $(cat $SCRIPT_DIR/backup.sh)
    '" >> $log_file 2>&1 &&
    log "Backup of VM $1 complete successfully" || {
        log "ERROR: Backup script failed on VM $1"
        return 1
    }
}

vms_bckp_update() {
    log "Starting VM Backups & Updates"
    for i in ${vms[@]}; do
        backup_vm $i && {
            log "Backup Successful for VM $i, starting update"
        } || {
            log "ERROR: Backup failed for VM $i"
            continue
        }

        update_vm $i && {
            log "Update of VM $i succesful"
        } || {
            log "ERROR: Update failed for VM $i"
            continue
        }
    done
    log "All VM Backups & Updates attempted"
}

cts_bckp_update() {
    log "Starting CT Backups & Updates"
    for i in ${cts[@]}; do
        backup_ct $i && {
            log "Backup Successful for CT $i, starting update"
        } || {
            log "ERROR: Backup failed for CT $i"
            continue
        }

        update_ct $i && {
            log "Update of CT $i succesful"
        } || {
            log "ERROR: Update failed for CT $i"
            continue
        }
    done
    log "All CT Backups & Updates attempted"
}

update_bckp_local() {
    log "Backing up $(hostname)"
    # run backup script on local machine, redirect stdout & stderr to log file
    $SCRIPT_DIR/backup.sh >> $log_file 2>&1 &&
    log "Backup of $(hostname) complete successfully" || {
        log "ERROR: Backup script failed on $(hostname)"
        return 1
    }

    # local apt update & upgrade
    log "Updating $(hostname)"
    sudo apt-get update || {
        log "ERROR: Update failed for $(hostname)"
        return 1
    }

    sudo apt-get upgrade -y || {
        log "ERROR: Upgrade failed for $(hostname)"
        return 1
    }
}

mail_status() {
    [[ "$mail_sent_flag" == "false" ]] || {
        log "Mail already attempted - Skipping"
        return
    }

    # create email subject & body to email status of script
    log "Checking Status & Sending email"
    if [[ $(grep 'ERROR' "$log_file" | wc -l) -gt 0 ]]; then
        local subject="ERROR: Update Script Completed with Errors"
        local mail_body=$(egrep 'ERROR|WARNING' "$log_file")
    elif [[ $(grep 'WARNING' "$log_file" | wc -l) -gt 0 ]]; then
        local subject="WARNING: Update Script Completed with Warnings"
        local mail_body=$(egrep 'WARNING' "$log_file")
    else
        local subject="Update Script Completed Succesfully"
        local mail_body="No Warnings or Errors found."
    fi

    # capture errors/warnings not produced by scipt log function, ignore expected tar warnings
    if [[ $(egrep -v "^\[|Removing leading|socket ignored" "$log_file" | wc -l) -gt 0 ]]; then
        local mail_body+=$'\n'$'\n'
        local mail_body+="--- None Captured Errors / Warnings ---"$'\n'
        local mail_body+=$(egrep -v "^\[|Removing leading|socket ignored" "$log_file")
    fi

    # send mail with overal status, all errors/warnings in body and full log attached
    echo "$mail_body" | mailx -s "$subject" -A "$log_file" "$MAIL_TO" &&
    log "Status Email Sent" ||
    log "ERROR: Error Sending Status Email"
    mail_sent_flag="true"
} 

# ************************************************************************* #
#                                  Main                                     # 
# ************************************************************************* #

log "######## Beginning Prox Update ########"

trap 'mail_status' EXIT

mail_sent_flag="false"

host_on_check

create_exclude_list

find_cts
find_vms

check_found

start_cts
start_vms

cts_bckp_update
vms_bckp_update

update_bckp_local

initial_state

mail_status

log "Rebooting $(hostname)"
log "########       Exiting        ########"
sudo reboot
