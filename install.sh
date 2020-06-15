#!/bin/bash

echo "[Unit]
Description=RoLink Abuse Protection Service
After=NetworkManager-wait-online.service

[Service]
User=root
Type=simple
ExecStart=/opt/rolink/scripts/rlabp.sh
Restart=always
RestartSec=30
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target" > rlabp.service

if ! grep -q "RX=LocalVoter" /opt/rolink/conf/svxlink.conf; then
	cp /opt/rolink/conf/svxlink.conf /opt/rolink/conf/svxlink.conf.bak.$(date +%d%m%y)
	read -p "Press [Enter] to add the Voter section to your config"
	sudo nano /opt/rolink/conf/svxlink.conf
fi

if [ ! -f /opt/rolink/conf/svxlinknorx.conf ]; then
	cp rlabp.sh /opt/rolink/scripts && cp /opt/rolink/conf/svxlink.conf /opt/rolink/conf/svxlinknorx.conf
	read -p "Press [Enter] to open the clone configuration for editing"
	sudo nano /opt/rolink/conf/svxlinknorx.conf
	mv rlabp.service /lib/systemd/system
	sudo systemctl daemon-reload && systemctl enable rlabp.service && systemctl start rlabp
	read -p "Done! Press [Enter] to quit."
	exit 1
elif [ -f /lib/systemd/system/rlabp.service ]; then
	read -p "Previous installation detected. Press [Enter] to upgrade the script."
	cp -rf rlabp.sh /opt/rolink/scripts && systemctl restart rlabp && rm -f rlabp.service
elif [ ! -f /lib/systemd/system/rlabp.service ]; then
	read -p "Cron based installation detected. Press [Enter] to upgrade the script and install the service."
	cp -rf rlabp.service /lib/systemd/system && rm -f rlabp.service
	cp -rf rlabp.sh /opt/rolink/scripts && sudo systemctl daemon-reload &&\
	systemctl enable rlabp.service && systemctl start rlabp
fi

if [ -f /etc/cron.d/rlabp ]; then
	rm -f /etc/cron.d/rlabp && sudo service cron restart
	echo "Cron based version removed."
fi
