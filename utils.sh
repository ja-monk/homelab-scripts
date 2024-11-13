#!/bin/bash 

log(){
    local base_name="$(basename $0)"
    local trimmed_name="${base_name%%.*}"
    local log_dir="$HOME/logs/$trimmed_name"
    log_file="$log_dir/${trimmed_name}_$(date +"%Y%m%d").log"
    export log_file
    [[ -d $log_dir ]] || mkdir -p $log_dir
    [[ -f $log_file ]] || touch $log_file
    echo "[$(date +"%d-%m-%Y %T")] - $1" | tee -a $log_file
}