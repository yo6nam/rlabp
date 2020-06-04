#!/bin/bash
# Serviciu anti-abuz dinspre RF/retea & activare externa & penalizare progresiva - YO6NAM

# Set your limits below (ext_trig_btm sets the value in minutes for external trigger events)
max_rf_ptt=4
max_net_ptt=10
reflector=reflector.439100.ro,rolink.rolink-net.ro,svx.dstar-yo.ro
ext_trig_btm=10
run_as=svxlink # change to root where needed
debug=false # set to 'true' if you want cu check the timers

# Begin, nothing to edit below
while true
do

# Start the loop
rf_ptt_bc=$(tail -20 /tmp/svxlink.log | grep -c "OPEN")
rf_ptt_bt=$(awk -v d1="$(date --date="-20 sec" "+%Y-%m-%d %H:%M:%S:")" \
-v d2="$(date "+%Y-%m-%d %H:%M:%S:")" '$0 > d1 && $0 < d2 || $0 ~ d2' \
/tmp/svxlink.log | grep -c "OPEN")
net_ptt=$(awk -v d1="$(date --date="-30 sec" "+%Y-%m-%d %H:%M:%S:")" \
-v d2="$(date "+%Y-%m-%d %H:%M:%S:")" '$0 > d1 && $0 < d2 || $0 ~ d2' \
/tmp/svxlink.log | grep -c "Talker stop")

# Progressive penalty timer
if [ ! -f /tmp/rlpt ]; then
    echo "1" > /tmp/rlpt
fi
bantime=$(($(cat /tmp/rlpt) * 60))

# Abuse check / status
if [ $rf_ptt_bc -gt $max_rf_ptt ]; then
	abuse=$(($rf_ptt_bc));
elif [ $rf_ptt_bt -gt $max_rf_ptt ] && [ !$abuse ]; then
	abuse=$(($rf_ptt_bt));
elif [ $rf_ptt_bc -gt 3 ] || [ $net_ptt -gt 9 ]; then
	logger "RLABP status Count: $rf_ptt_bc / Timed: $rf_ptt_bt / Net: $net_ptt"
fi

# External triggers
if [ "$1" = "s" ]; then
	logger -p User.alert "External trigger, service mode."
	sudo poff -a; sleep 2 && sudo pon rlcfg
	exit 1
elif [ "$1" = "9" ]; then
	logger -p User.alert "External trigger, reboot."
	sudo reboot -f
	exit 1
elif [ "$1" = "3" ]; then
	logger -p User.alert "External trigger, blocking traffic for $ext_trig_btm minutes."
	touch /tmp/rolink.flg
	sudo /sbin/iptables -I INPUT -s $reflector -j DROP
	echo $ext_trig_btm > /tmp/rlpt
	/opt/rolink/rolink-start.sh
	exit 1
elif [ "$1" = "2" ]; then
	logger -p User.alert "External trigger, unblocking traffic."
	echo "1" > /tmp/rlpt
	rm -f /tmp/rolink.flg
	sudo /sbin/iptables -D INPUT -s $reflector -j DROP
	cat /dev/null > /tmp/svxlink.log
	/opt/rolink/scripts/rolink-start.sh
	exit 1
elif [ "$1" = "1" ]; then
	logger -p User.alert "External trigger, switching to <<TX Only>> mode for $ext_trig_btm minutes."
	echo $ext_trig_btm > /tmp/rlpt
	[ "$(pidof svxlink)" != "" ] && killall -v svxlink && sleep 1
	export LD_LIBRARY_PATH="/opt/rolink/lib"
	/opt/rolink/bin/svxlink --daemon --config=/opt/rolink/conf/svxlinknorx.conf --logfile=/tmp/svxlink.log \
	--runasuser=$run_as --pidfile=/var/run/svxlink.pid
	cat /dev/null > /tmp/svxlink.log && touch /tmp/rolink.flg
	exit 1
elif [ "$1" = "0" ]; then
	logger -p User.alert "External trigger, switching to Normal Operation."
	echo "1" > /tmp/rlpt
	sudo /sbin/iptables -D INPUT -s $reflector -j DROP
	rm -f /tmp/rolink.flg && cat /dev/null > /tmp/svxlink.log
	/opt/rolink/scripts/rolink-start.sh
	exit 1
fi

# Disable RX
if [ $abuse ]; then
	logger -p User.alert "Abuse from RF detected ($abuse PTTs within 20 seconds). <<RX disabled>> for $((($(cat /tmp/rlpt) * 60) / 60)) minutes."
	[ "$(pidof svxlink)" != "" ] && killall -v svxlink && sleep 3
	export LD_LIBRARY_PATH="/opt/rolink/lib"
	/opt/rolink/bin/svxlink --daemon --config=/opt/rolink/conf/svxlinknorx.conf --logfile=/tmp/svxlink.log \
	--runasuser=$run_as --pidfile=/var/run/svxlink.pid
	cat /dev/null > /tmp/svxlink.log && touch /tmp/rolink.flg
	unset abuse
	echo $(($(cat /tmp/rlpt) + 5 )) > /tmp/rlpt
fi

# Disable traffic
if [ ! -f /tmp/rolink.flg ] && [ $net_ptt -gt $max_net_ptt ]; then
	touch /tmp/rolink.flg
	sudo /sbin/iptables -I INPUT -s $reflector -j DROP
	/opt/rolink/rolink-start.sh
	logger -p User.alert "Abuse from network detected ($net_ptt), <<blocking traffic>> for $((($(cat /tmp/rlpt) * 60) / 60)) minutes."
fi

# Reset the timer
if [ -f /tmp/rolink.flg ] && [ "$(( $(date +"%s") - $(stat -c "%Y" /tmp/rolink.flg) ))" -gt $bantime ]; then
	rm -f /tmp/rolink.flg
	sudo /sbin/iptables -D INPUT -s $reflector -j DROP
	cat /dev/null > /tmp/svxlink.log
	/opt/rolink/scripts/rolink-start.sh
fi

# Reset the penalty multiplication factor
if [ -f /tmp/rlpt ] && [ "$(( $(date +"%s") - $(stat -c "%Y" /tmp/rlpt) ))" -gt 3600 ]; then
	echo "1" > /tmp/rlpt
fi

if $debug; then
	logger "D: Count: $rf_ptt_bc / Timed: $rf_ptt_bt / Net: $net_ptt, Ban time set to $((($(cat /tmp/rlpt) * 60) / 60)) minutes, Penalty factor is $(cat /tmp/rlpt)"
	if [ -f /tmp/rolink.flg ]; then
		logger "D: Flag is $(( $(date +"%s") - $(stat -c "%Y" /tmp/rolink.flg) )) seconds old."
	fi
fi

# End loop
sleep 1
done
