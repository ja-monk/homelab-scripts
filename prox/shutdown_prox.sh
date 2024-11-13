#!/bin/bash

find_running(){
	running_cts=$(sudo pct list | awk -F ' ' 'NR>1 { if ($2!="stopped") print $1 }')
	running_vms=$(sudo qm list | awk -F ' ' 'NR>1 { if ($3!="stopped") print $1 }')
}

shutdown_cts(){
	for i in ${running_cts[@]}; do
		local hostname=$(sudo pct config $i | awk -F ': ' '{ if ($1=="hostname") print $2 }')

		echo "Shutting down CT $i ($hostname)"
		sudo timeout 30s pct shutdown "$i"

		[[ $? != 0 ]] && {
			echo "--- error: CT $i ($hostname) shutdown failed ---" &&
			echo "--- Exiting ---" &&
			exit;
		}
		sleep 5
	done
}

shutdown_vms(){
	for i in ${running_vms[@]}; do
		local hostname=$(sudo qm guest cmd $i get-host-name | jq -r '."host-name"')

		echo "Shutting down VM $i ($hostname)"
		sudo timeout 2m qm guest cmd "$i" shutdown 1>/dev/null

		[[ $? != 0 ]] && {
            echo "--- error: VM $i ($hostname) shutdown failed ---" &&
			echo "--- Exiting ---" &&
			exit;
        }
		sleep 5
	done
}

main(){
	find_running
	shutdown_cts
	shutdown_vms

	echo "All CTs & VMs shutdown"
	echo "Shutting down host"
	sudo shutdown now
}

main
