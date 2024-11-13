#!/bin/bash

# update path to env.sh script to export vars
. "$HOME/scripts/env.sh"

wake_server(){
	wakeonlan -i $BROADCAST_IP $1
	echo " "

	# ping ip, exit when successful
	for i in {1..20}; do
		ping -c 1 $2
		[[ $? == 0 ]] && {
			echo " " &&
			echo "--- Script exiting sucessfully ---" &&
			exit;
		}
	done

	# if not successful after 20 tries
	echo " "
	echo "--- ERROR: Script failed ---"
}

wake_server $mac_addr $ip_host

