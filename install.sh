#!/bin/bash

if [ ! -f /opt/rolink/conf/svxlinknorx.conf ]; then
	cp rlabp.sh /opt/rolink/scripts && cp rlabp /etc/cron.d && cp /opt/rolink/conf/svxlink.conf /opt/rolink/conf/svxlinknorx.conf
	read -p "Press [Enter] to open the clone configuration for editing"
        sudo nano /opt/rolink/conf/svxlinknorx.conf
        sudo service cron restart
        read -p "Done! Press [Enter] to quit."
        exit 1
else
        read -p "Previous installation detected. Press [Enter] to upgrade the script."
        cp -rf rlabp.sh /opt/rolink/scripts
fi
