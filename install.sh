#!/bin/bash
# Install script

cp rlabp.sh /opt/rolink/scripts && cp rlabp /etc/cron.d && cp /opt/rolink/conf/svxlink.conf /opt/rolink/conf/svxlinknorx.conf
read -p "Press [Enter] to open the clone configuration for editing"
sudo nano /opt/rolink/conf/svxlinknorx.conf
sudo service cron restart
read -p "Done! Press [Enter] to quit."
exit 1
