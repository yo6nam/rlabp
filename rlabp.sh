#!/bin/bash
# Serviciu anti-abuz dinspre RF/retea, activare externa, penalizare progresiva, conectare dinamica
# https://github.com/yo6nam/rlabp

# Set your options below
max_rf_ptt=2		# Max PTTs from RF side
max_net_ptt=8		# Max PTTs from Network side
reflector=reflector.439100.ro,rolink.rolink-net.ro,svx.dstar-yo.ro
rname=RxLocal		# Name of the receiver linked to the Voter section
static=true		# false for dynamic connection to reflector (activates on PTT)
relax=false		# disable the Network side protection on special events
stime=60		# How many minutes to remain connected to the reflector?
init_btm=1		# Ban time value (minutes) for automatic triggered events (first warning)
ext_trig_btm=30	# Ban time value (minutes) for external triggered events
pf=15			# Increase ban time after each recurring abuse with how many minutes?
pf_reset=10800	# Reset the penalty factor after how many seconds?
run_as=svxlink	# Change to root where needed (svxlink v1.7+)
debug=false		# Print debug information
debug_frq=10	# how often to print debug lines (seconds)

# Check for SvxLink logs
if [ ! -f /tmp/svxlink.log ]; then
	printf '' | tee /tmp/svxlink.log
	logger -p user.warning "[RLABP v21.1.21]: Protection started, waiting for logs..."
	sleep 15
fi

# Starting the loop
while true; do

# Process the svxlink.log
rf_ptt=$(awk -v d1="$(date --date="-12 sec" "+%Y-%m-%d %H:%M:%S:")" \
-v d2="$(date "+%Y-%m-%d %H:%M:%S:")" '$0 > d1 && $0 < d2 || $0 ~ d2' \
/tmp/svxlink.log | grep -c "OPEN")
net_ptt=$(awk -v d1="$(date --date="-30 sec" "+%Y-%m-%d %H:%M:%S:")" \
-v d2="$(date "+%Y-%m-%d %H:%M:%S:")" '$0 > d1 && $0 < d2 || $0 ~ d2' \
/tmp/svxlink.log | grep -c "Talker stop")

# Progressive penalty timer
if [ ! -f /tmp/rlpt ]; then printf $init_btm | tee /tmp/rlpt; fi
bantime=$(($(cat /tmp/rlpt) * 60))

# Abuse check / status
if [ $rf_ptt -gt $max_rf_ptt ]; then abuse=$(($rf_ptt)); fi

# Check for voter file corruption
if pgrep -x "svxlink" >/dev/null && [ ! -L /tmp/voter ]; then
	rm -f /tmp/voter
	sleep 1
	/opt/rolink/scripts/rolink-start.sh
fi

# Delete blocking rules
function del_fw_rules {
	while (/sbin/iptables -C INPUT -s $reflector -j DROP; echo $? | grep -q "0"); do
		((fr++))
		/sbin/iptables -D INPUT -s $reflector -j DROP
	done
	if $debug && [ ! -z $fr ];then logger "[RLABP Debug]: $fr firewall rule(s) found and deleted."; fi
}

# Relax on special events (QTC)
if [ "$relax" = true ] && [ "$(date +%a)" = "Sun" ]; then
	if [[ "$(date +%H:%M)" > "17:00" ]] || [[ "$(date +%H:%M)" < "20:00" ]]; then
		net_ptt=0
	fi
fi

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
	rm -f /tmp/rolink.flg; printf $init_btm | tee /tmp/rlpt; del_fw_rules
	printf '' | tee /tmp/svxlink.log; printf '1' | tee /tmp/rldc;
	/opt/rolink/scripts/rolink-start.sh
	exit 1
elif [ "$1" = "1" ]; then
	logger -p user.alert "$etmsg switching to [TX-ONLY] mode for $ext_trig_btm minutes."
	touch /tmp/rolink.flg; printf $ext_trig_btm | tee /tmp/rlpt; printf '' | tee /tmp/svxlink.log
	echo "DISABLE $rname" > /tmp/voter
	exit 1
elif [ "$1" = "0" ]; then
	logger -p user.alert "$etmsg switching to [NORMAL-OPERATION]."
	del_fw_rules; printf '1' | tee /tmp/rldc;
	rm -f /tmp/rolink.flg; printf $init_btm | tee /tmp/rlpt; printf '' | tee /tmp/svxlink.log
	echo "ENABLE $rname" > /tmp/voter
	exit 1
fi

# Disable RX
if [ $abuse ]; then
	logger -p user.alert "Abuse from RF detected ($abuse PTTs within 20 seconds). [TX-ONLY] for $((($(cat /tmp/rlpt) * 60) / 60)) minutes."
	touch /tmp/rolink.flg; printf '' | tee /tmp/svxlink.log
	echo "DISABLE $rname" > /tmp/voter
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
	del_fw_rules; echo "ENABLE $rname" > /tmp/voter
	t=$(cat /tmp/rlpt)
	echo $([ $t = $init_btm ] && echo $(($t - $init_btm + $pf)) || echo $(($t + $pf))) > /tmp/rlpt
fi

# Reset the penalty multiplication factor
if [ -f /tmp/rlpt ] && [ "$(( $(date +"%s") - $(stat -c "%Y" /tmp/rlpt) ))" -gt $pf_reset ]; then
	printf $init_btm | tee /tmp/rlpt
fi

# Dynamic connection to reflector
if [ "$static" = false ] ; then
	if [ ! -f /tmp/rldc ]; then
		printf '0' | tee /tmp/rldc;	/sbin/iptables -I INPUT -s $reflector -j DROP
	fi
	if [ $rf_ptt -gt 0 ] && [ $(cat /tmp/rldc) -eq 0 ] && [ ! -f /tmp/rolink.flg ]; then
		printf '1' | tee /tmp/rldc
		del_fw_rules; /opt/rolink/scripts/rolink-start.sh
	fi
	# Reset timer if RF activity
	if [ $rf_ptt -gt 0 ] && [ $(cat /tmp/rldc) -eq 1 ] && [ ! -f /tmp/rolink.flg ]; then
		printf '1' | tee /tmp/rldc
	fi
	if [ $(cat /tmp/rldc) -gt 0 ] && [ "$(( $(date +"%s") - $(stat -c "%Y" /tmp/rldc) ))" -gt $(($stime * 60)) ]; then
		printf '0' | tee /tmp/rldc; /sbin/iptables -I INPUT -s $reflector -j DROP
		logger "[RLABP Debug]: Dynamic timer expired. Disconnecting..."
	fi
fi

# Start debug if enabled
if $debug && [[ -z $dt || $dt -eq $debug_frq ]]; then
	dmsg="[RLABP Debug]: RF: $rf_ptt / Net: $net_ptt"
	if [ "$static" = false ] && [ $(cat /tmp/rldc) -gt 0 ] ; then
		dtr=$(( $(date +"%s") - $(stat -c "%Y" /tmp/rldc) ))
		dmsg+=", DynCTL: $(((($stime * 60) - $dtr) / 60)) min"
	fi
	if [ $(cat /tmp/rlpt) -gt $init_btm ]; then
		pft=$(( $(date +"%s") - $(stat -c "%Y" /tmp/rlpt) ))
		dmsg+=", Ban time: $((($(cat /tmp/rlpt) * 60) / 60)) min"
		dmsg+=", Penalty reset: $((($pf_reset - $pft) / 60)) min"
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
sleep 2
done
