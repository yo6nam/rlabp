#!/bin/bash
# Serviciu anti-abuz dinspre RF/retea & activare externa & penalizare progresiva
# https://github.com/yo6nam/rlabp

# Set your options below
max_rf_ptt=4		# RF side
max_net_ptt=10		# Network side
reflector=reflector.439100.ro,rolink.rolink-net.ro,svx.dstar-yo.ro
init_btm=1		# Ban time value (minutes) for automatic triggered events
ext_trig_btm=10		# Ban time value (minutes) for external triggered events
pf=5			# Increase ban time after each recurring abuse with how many minutes?
pf_reset=3600		# Reset the penalty factor to 1 after how many seconds?
run_as=svxlink		# change to root where needed
debug=false		# 'true' if you want cu check the timers
debug_frq=10		# how often to print debug lines (seconds)

# Check for SvxLink logs
if [ ! -f /tmp/svxlink.log ]; then
	printf '' | tee /tmp/svxlink.log
	logger -p user.warning "[RLABP]: Protection started, waiting for logs..."
	sleep 15
fi

# Starting the loop
while true; do

# Process the svxlink.log
rf_ptt_bc=$(tail -22 /tmp/svxlink.log | grep -c "OPEN")
rf_ptt_bt=$(awk -v d1="$(date --date="-20 sec" "+%Y-%m-%d %H:%M:%S:")" \
-v d2="$(date "+%Y-%m-%d %H:%M:%S:")" '$0 > d1 && $0 < d2 || $0 ~ d2' \
/tmp/svxlink.log | grep -c "OPEN")
net_ptt=$(awk -v d1="$(date --date="-40 sec" "+%Y-%m-%d %H:%M:%S:")" \
-v d2="$(date "+%Y-%m-%d %H:%M:%S:")" '$0 > d1 && $0 < d2 || $0 ~ d2' \
/tmp/svxlink.log | grep -c "Talker stop")

# Progressive penalty timer
if [ ! -f /tmp/rlpt ]; then echo $init_btm > /tmp/rlpt; fi
bantime=$(($(cat /tmp/rlpt) * 60))

# Abuse check / status
if [ $rf_ptt_bc -gt $max_rf_ptt ]; then
	abuse=$(($rf_ptt_bc));
elif [ $rf_ptt_bt -gt $max_rf_ptt ] && [ !$abuse ]; then
	abuse=$(($rf_ptt_bt));
elif [ $rf_ptt_bc -gt 3 ] || [ $net_ptt -gt 9 ] && [ !$debug ]; then
	logger "[RLABP PTT STATUS] - Count: $rf_ptt_bc / Timed: $rf_ptt_bt / Net: $net_ptt"
fi

# Delete blocking rules
function del_fw_rules {
	while (/sbin/iptables -C INPUT -s $reflector -j DROP; echo $? | grep -q "0"); do
		((fr++))
		/sbin/iptables -D INPUT -s $reflector -j DROP
	done
	if $debug && [ ! -z $fr ];then logger "[RLABP Debug]: $fr firewall rule(s) found and deleted."; fi
}

# External triggers
etmsg="External trigger,"
if [ "$1" = "s" ]; then
	logger -p user.alert "$etmsg [SERVICE-MODE]."
	poff -a; sleep 2 && pon rlcfg
	exit 1
elif [ "$1" = "9" ]; then
	logger -p user.alert "$etmsg [REBOOT]."
	reboot -f
	exit 1
elif [ "$1" = "3" ]; then
	logger -p user.alert "$etmsg [TRAFFIC-BLOCK] for $ext_trig_btm minutes."
	touch /tmp/rolink.flg; echo $ext_trig_btm > /tmp/rlpt
	/sbin/iptables -I INPUT -s $reflector -j DROP
	/opt/rolink/rolink-start.sh
	exit 1
elif [ "$1" = "2" ]; then
	logger -p user.alert "$etmsg [TRAFFIC-UNBLOCK]."
	rm -f /tmp/rolink.flg; rm -f /tmp/rlpt; del_fw_rules
	printf '' | tee /tmp/svxlink.log
	/opt/rolink/scripts/rolink-start.sh
	exit 1
elif [ "$1" = "1" ]; then
	logger -p user.alert "$etmsg switching to [TX-ONLY] mode for $ext_trig_btm minutes."
	touch /tmp/rolink.flg; echo $ext_trig_btm > /tmp/rlpt; printf '' | tee /tmp/svxlink.log
	[ "$(pidof svxlink)" != "" ] && killall -v svxlink && sleep 1
	export LD_LIBRARY_PATH="/opt/rolink/lib"
	/opt/rolink/bin/svxlink --daemon --config=/opt/rolink/conf/svxlinknorx.conf --logfile=/tmp/svxlink.log \
	--runasuser=$run_as --pidfile=/var/run/svxlink.pid
	exit 1
elif [ "$1" = "0" ]; then
	logger -p user.alert "$etmsg switching to [NORMAL-OPERATION]."
	del_fw_rules
	rm -f /tmp/rolink.flg; rm -f /tmp/rlpt; printf '' | tee /tmp/svxlink.log
	/opt/rolink/scripts/rolink-start.sh
	exit 1
fi

# Disable RX
if [ $abuse ]; then
	logger -p user.alert "Abuse from RF detected ($abuse PTTs within 20 seconds). [TX-ONLY] for $((($(cat /tmp/rlpt) * 60) / 60)) minutes."
	touch /tmp/rolink.flg; printf '' | tee /tmp/svxlink.log
	[ "$(pidof svxlink)" != "" ] && killall -v svxlink && sleep 2
	export LD_LIBRARY_PATH="/opt/rolink/lib"
	/opt/rolink/bin/svxlink --daemon --config=/opt/rolink/conf/svxlinknorx.conf --logfile=/tmp/svxlink.log \
	--runasuser=$run_as --pidfile=/var/run/svxlink.pid
	unset abuse
fi

# Disable traffic
if [ ! -f /tmp/rolink.flg ] && [ $net_ptt -gt $max_net_ptt ]; then
	touch /tmp/rolink.flg; /sbin/iptables -I INPUT -s $reflector -j DROP
	/opt/rolink/rolink-start.sh
	logger -p user.alert "Abuse from NET detected ($net_ptt PTTs within 30 seconds), [TRAFFIC-BLOCK] for $((($(cat /tmp/rlpt) * 60) / 60)) minutes."
fi

# Reset timers & increment the penalty by $pf value
if [ -f /tmp/rolink.flg ] && [ "$(( $(date +"%s") - $(stat -c "%Y" /tmp/rolink.flg) ))" -gt $bantime ]; then
	rm -f /tmp/rolink.flg; printf '' | tee /tmp/svxlink.log
	del_fw_rules
	/opt/rolink/scripts/rolink-start.sh
	t=$(cat /tmp/rlpt)
	echo $([ $t = $init_btm ] && echo $(($t - $init_btm + $pf)) || echo $(($t + $pf))) > /tmp/rlpt
fi

# Reset the penalty multiplication factor
if [ -f /tmp/rlpt ] && [ "$(( $(date +"%s") - $(stat -c "%Y" /tmp/rlpt) ))" -gt $pf_reset ]; then
	echo $init_btm > /tmp/rlpt
fi

# Start debug if enabled
if $debug && [[ -z $dt || $dt -eq $debug_frq ]]; then
	dmsg="[RLABP Debug]: (PTT) Count: $rf_ptt_bc / Timed: $rf_ptt_bt / Net: $net_ptt"
	if [ $(cat /tmp/rlpt) -gt $init_btm ]; then
		pft=$(( $(date +"%s") - $(stat -c "%Y" /tmp/rlpt) ))
		dmsg+=", Ban time: $((($(cat /tmp/rlpt) * 60) / 60)) min"
		dmsg+=", Penalty factor: $(cat /tmp/rlpt)"
		dmsg+=" [$(( $pf_reset - $pft ))]"
	fi
	if [ -f /tmp/rolink.flg ]; then
		flt=$(( $(date +"%s") - $(stat -c "%Y" /tmp/rolink.flg) ))
		dmsg+=", Protection ends in $(( $bantime - $flt )) sec"
	fi
	logger "$dmsg"
	dt=0
fi

if $debug; then ((dt++)); fi

# End loop
sleep 1
done
