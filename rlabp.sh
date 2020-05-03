#!/bin/bash
# Script anti abuz pe NET/RF & external trigger - YO6NAM

# Set your limits below (bantime in seconds)
max_rf_ptt=4
max_net_ptt=10
bantime=1800

# Begin, nothing to edit below
rf_ptt_bc=$(tail -22 /tmp/svxlink.log | grep -c "OPEN")
rf_ptt_bt=$(awk -v d1="$(date --date="-20 sec" "+%Y-%m-%d %H:%M:%S:")" \
-v d2="$(date "+%Y-%m-%d %H:%M:%S:")" '$0 > d1 && $0 < d2 || $0 ~ d2' \
/tmp/svxlink.log | grep -c "OPEN")
net_ptt=$(awk -v d1="$(date --date="-30 sec" "+%Y-%m-%d %H:%M:%S:")" \
-v d2="$(date "+%Y-%m-%d %H:%M:%S:")" '$0 > d1 && $0 < d2 || $0 ~ d2' \
/tmp/svxlink.log | grep -c "Talker stop")

if [ $rf_ptt_bc -gt $max_rf_ptt ]; then
	abuse=$(($rf_ptt_bc));
elif [ $rf_ptt_bt -gt $max_rf_ptt ] && [ !$abuse ]; then
	abuse=$(($rf_ptt_bt));
elif [ $rf_ptt_bt -gt 1 ]; then
	logger "ABP Normal C:$rf_ptt_bc/T:$rf_ptt_bt"
elif [ "$1" = "2" ]; then
	rm -f /tmp/rolink.flg
	sudo /sbin/iptables -D INPUT -s reflector.439100.ro,rolink.rolink-net.ro -j DROP
	cat /dev/null > /tmp/svxlink.log
	/opt/rolink/scripts/rolink-start.sh
	exit 1
elif [ "$1" = "1" ]; then
	logger -p User.alert "External trigger, switching to TX only mode."
	[ "$(pidof svxlink)" != "" ] && killall -v svxlink && sleep 1
	/opt/rolink/bin/svxlink --daemon --config=/opt/rolink/conf/svxlinknorx.conf --logfile=/tmp/svxlink.log \
	--runasuser=svxlink --pidfile=/var/run/svxlink.pid
	cat /dev/null > /tmp/svxlink.log && touch /tmp/rolink.flg
	exit 1
elif [ "$1" = "0" ]; then
	logger -p User.alert "External trigger, switching to Normal Operation."
	rm -f /tmp/rolink.flg && cat /dev/null > /tmp/svxlink.log
	/opt/rolink/scripts/rolink-start.sh
	exit 1
fi

if [ $abuse ]; then
	logger -p User.alert "Abuse from RF detected ($abuse PTTs within 20 seconds)."
	[ "$(pidof svxlink)" != "" ] && killall -v svxlink && sleep 3
	/opt/rolink/bin/svxlink --daemon --config=/opt/rolink/conf/svxlinknorx.conf --logfile=/tmp/svxlink.log \
	--runasuser=svxlink --pidfile=/var/run/svxlink.pid
	cat /dev/null > /tmp/svxlink.log && touch /tmp/rolink.flg
fi

if [ ! -f /tmp/rolink.flg ] && [ $net_ptt -gt $max_net_ptt ]; then
	touch /tmp/rolink.flg
	sudo /sbin/iptables -I INPUT -s reflector.439100.ro,rolink.rolink-net.ro -j DROP
	/opt/rolink/rolink-start.sh
	logger -p User.alert "Abuse from network detected ($net_ptt), blocking traffic."
fi

if [ -f /tmp/rolink.flg ] && [ "$(( $(date +"%s") - $(stat -c "%Y" /tmp/rolink.flg) ))" -gt $bantime ]; then
	rm -f /tmp/rolink.flg
	sudo /sbin/iptables -D INPUT -s reflector.439100.ro,rolink.rolink-net.ro -j DROP
	cat /dev/null > /tmp/svxlink.log
	/opt/rolink/scripts/rolink-start.sh
fi

if [ $net_ptt -gt 2 ]; then
	logger "ABP Net $net_ptt"
fi
