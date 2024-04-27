#!/bin/bash
# Serviciu anti-abuz dinspre RF/retea, activare externa, penalizare progresiva, conectare dinamica
# https://github.com/yo6nam/rlabp

# Set your options below
proto=2                    # SVXLink protocol
max_rf_ptt=3               # Max PTTs from RF side
max_net_ptt=12             # Max PTTs from Network side
rf_ptt_tcl=0               # Startup value for TCL detection
reflector="rolink.network" # IP/DNS of the reflector
static=true                # false for dynamic connection to reflector (activates on PTT)
relax=false                # disable the Network side protection on special events
stime=60                   # How many minutes to remain connected to the reflector?
init_btm=1                 # Ban time value (minutes) for automatic triggered events (first warning)
ext_trig_btm=60            # Ban time value (minutes) for external triggered events
pf=15                      # Increase ban time after each recurring abuse with how many minutes?
pf_reset=104000            # Reset the penalty factor after how many seconds?
debug=false                 # Print debug information
debug_frq=3                # how often to print debug lines (seconds)

function del_fw_rules {
  while /sbin/iptables -C INPUT -s $reflector -j DROP >/dev/null 2>&1; do
    ((fr++))
    /sbin/iptables -D INPUT -s $reflector -j DROP
  done
  if $debug && [ ! -z $fr ]; then
    logger "[RLABP Debug]: $fr firewall rule(s) found and deleted."
  fi
}

function voter {
    case $1 in
        "0")
            sleep 2
            echo "DISABLE RxLocal" >/tmp/voter
            ;;
        "1")
            sleep 2
            echo "ENABLE RxLocal" >/tmp/voter
            ;;
    esac
}

function externalTrigger {
    local trigger=$1
    local etmsg="External trigger,"

    case $trigger in
        "0")
            rm -f /tmp/rolink.flg
            del_fw_rules
            printf '1' | tee /tmp/rldc >/dev/null
            printf $init_btm | tee /tmp/rlpt >/dev/null
            [ -f /dev/shm/svx ] && echo "0" >/dev/shm/svx
            [[ "$proto" == "2" ]] && echo "0" >/sys/class/gpio/gpio19/value
            echo "551226#" >/tmp/dtmf
            voter 1
            logger -p user.alert "$etmsg switching to [NORMAL-OPERATION]."
            ;;
        "1")
            touch /tmp/rolink.flg
            printf $ext_trig_btm | tee /tmp/rlpt >/dev/null
            [ -f /dev/shm/svx ] && echo 0 >/dev/shm/svx
            voter 0
            logger -p user.alert "$etmsg switching to [TX-ONLY] mode for $ext_trig_btm minutes."
            ;;
        "2")
            del_fw_rules
            rm -f /tmp/rolink.flg
            voter 1
            printf $init_btm | tee /tmp/rlpt >/dev/null
            printf '1' | tee /tmp/rldc >/dev/null
            echo "551226#" >/tmp/dtmf
            logger -p user.alert "$etmsg [TRAFFIC-UNBLOCK]."
            ;;
        "3")
            touch /tmp/rolink.flg
            echo $ext_trig_btm >/tmp/rlpt
            echo "1" >/sys/class/gpio/gpio19/value
            echo "55#" >/tmp/dtmf
            logger -p user.alert "$etmsg [TRAFFIC-BLOCK] for $ext_trig_btm minutes."
            ;;
        "4")
            [[ "$proto" == "1" ]] && logger -p user.alert "$etmsg [HARDWARE-BLOCK] not available on this system."
            touch /tmp/rolink.flg
            echo $ext_trig_btm >/tmp/rlpt
            echo "1" >/sys/class/gpio/gpio19/value
            logger -p user.alert "$etmsg [HARDWARE-BLOCK] for $ext_trig_btm minutes."
            ;;
        "5")
            [[ "$proto" == "1" ]] && logger -p user.alert "$etmsg [HARDWARE-UNBLOCK] not available on this system."
            rm -f /tmp/rolink.flg
            printf $init_btm | tee /tmp/rlpt >/dev/null
            printf '1' | tee /tmp/rldc >/dev/null
            [[ "$proto" == "2" ]] && echo "0" >/sys/class/gpio/gpio19/value
            voter 1
            logger -p user.alert "$etmsg [HARDWARE-UNBLOCK]."
            ;;
        "9")
            logger -p user.alert "$etmsg [REBOOT]."
            reboot
            ;;
        "s")
            if command -v poff &>/dev/null; then
              poff -a; sleep 2 && pon rlcfg
              logger -p user.alert "$etmsg [SERVICE-MODE]."
            else
              logger -p user.alert "PPTP not installed"
            fi
            ;;
        *)
            logger -p user.alert "Unknown trigger: $trigger"
            ;;
    esac
    exit 0
}

# External triggers
[ "$1" ] && externalTrigger "$1"

# Check for SvxLink logs
if [ ! -f /tmp/svxlink.log ]; then
  touch /tmp/svxlink.log
  logger -p user.warning "[RLABP v27.4.24]: Protection started, waiting for logs..."
  sleep 6
fi

# Starting the loop
while true; do

  # Check for voter file corruption
  if pgrep -x "svxlink" >/dev/null && [ ! -L /tmp/voter ]; then
    rm -f /tmp/voter >/dev/null
    [[ "$proto" == "1" ]] && /opt/rolink/scripts/rolink-start.sh || systemctl restart rolink
  fi

  # Process the svxlink.log
  rf_ptt=$(awk -v d1="$(date --date="-18 sec" "+%Y-%m-%d %H:%M:%S:")" \
  -v d2="$(date "+%Y-%m-%d %H:%M:%S:")" '$0 > d1 && $0 < d2 || $0 ~ d2' \
  /tmp/svxlink.log | grep -c "OPEN")

  net_ptt=$(awk -v d1="$(date --date="-30 sec" "+%Y-%m-%d %H:%M:%S:")" \
  -v d2="$(date "+%Y-%m-%d %H:%M:%S:")" '$0 > d1 && $0 < d2 || $0 ~ d2' \
  /tmp/svxlink.log | grep -c "Talker stop")

  # If TCL detection is used
  [ -f /dev/shm/svx ] && rf_ptt_tcl=$(cat /dev/shm/svx)

  # Progressive penalty timer
  [ ! -f /tmp/rlpt ] && printf $init_btm | tee /tmp/rlpt >/dev/null
  bantime=$(($(cat /tmp/rlpt) * 60))

  # Abuse check / status
  if [ ! -f /tmp/rolink.flg ] && [ $rf_ptt -gt $max_rf_ptt ]; then
    abuse=$(($rf_ptt))
  fi

  if [ ! $abuse ] && [ ! -f /tmp/rolink.flg ] && [ $rf_ptt_tcl -gt $max_rf_ptt ]; then
    abuse=$(($rf_ptt_tcl))
  fi


  # Relax on special events (QTC)
  if [ "$relax" = true ] && [ "$(date +%a)" = "Sun" ]; then
    if [[ "$(date +%H:%M)" > "17:00" ]] || [[ "$(date +%H:%M)" < "20:00" ]]; then
      net_ptt=0
    fi
  fi

  # Disable RX
  if [ $abuse ]; then
    touch /tmp/rolink.flg
    [[ "$proto" == "2" ]] && echo "1" >/sys/class/gpio/gpio19/value
    [ -f /dev/shm/svx ] && echo 0 >/dev/shm/svx
    logger -p user.alert "Abuse from RF detected ($abuse PTTs within 18 seconds). [TX-ONLY] for $((($(cat /tmp/rlpt) * 60) / 60)) minutes."
    voter 0
    unset abuse
  fi

  # Disable traffic
  if [ ! -f /tmp/rolink.flg ] && [ $net_ptt -gt $max_net_ptt ]; then
    touch /tmp/rolink.flg
    /sbin/iptables -I INPUT -s $reflector -j DROP
    [[ "$proto" == "1" ]] && /opt/rolink/scripts/rolink-start.sh || systemctl restart rolink
    logger -p user.alert "Abuse from NET detected ($net_ptt PTTs within 30 seconds), [TRAFFIC-BLOCK] for $((($(cat /tmp/rlpt) * 60) / 60)) minutes."
  fi

  # Reset timers & increment the penalty by $pf value
  if [ -f /tmp/rolink.flg ] && [ "$(( $(date +"%s") - $(stat -c "%Y" /tmp/rolink.flg) ))" -gt $bantime ]; then
    del_fw_rules
    rm -f /tmp/rolink.flg
    printf '1' | tee /tmp/rldc >/dev/null
    [ -f /dev/shm/svx ] && echo "0" >/dev/shm/svx
    [[ "$proto" == "2" ]] && echo "0" >/sys/class/gpio/gpio19/value
    t=$(cat /tmp/rlpt)
    [ "$t" = "$init_btm" ] && nv=$(($t - $init_btm + $pf)) || nv=$(($t + $pf))
    echo "$nv" >/tmp/rlpt
    voter 1
    unset abuse
  fi

  # Reset the penalty multiplication factor
  if [ -f /tmp/rlpt ] && [ "$(( $(date +"%s") - $(stat -c "%Y" /tmp/rlpt) ))" -gt $pf_reset ]; then
    printf $init_btm | tee /tmp/rlpt >/dev/null
  fi

  # Reset TCL counter
  if [ -f /dev/shm/svx ] && [ -f /tmp/rlpt ] && [ "$(( $(date +"%s") - $(stat -c "%Y" /dev/shm/svx) ))" -gt 3600 ]; then
    echo 0 >/dev/shm/svx
  fi

  # Dynamic connection to reflector
  if [ "$static" = false ] ; then
    if [ ! -f /tmp/rldc ]; then
      printf '0' | tee /tmp/rldc >/dev/null
      /sbin/iptables -I INPUT -s $reflector -j DROP
    fi
    if [ $rf_ptt -gt 0 ] && [ $(cat /tmp/rldc) -eq 0 ] && [ ! -f /tmp/rolink.flg ]; then
      printf '1' | tee /tmp/rldc >/dev/null
      del_fw_rules
      [[ "$proto" == "1" ]] && /opt/rolink/scripts/rolink-start.sh || systemctl restart rolink
    fi
    # Reset timer if RF activity
    if [ $rf_ptt -gt 0 ] && [ $(cat /tmp/rldc) -eq 1 ] && [ ! -f /tmp/rolink.flg ]; then
      printf '1' | tee /tmp/rldc >/dev/null
    fi
    if [ $(cat /tmp/rldc) -gt 0 ] && [ "$(( $(date +"%s") - $(stat -c "%Y" /tmp/rldc) ))" -gt $(($stime * 60)) ]; then
      printf '0' | tee /tmp/rldc >/dev/null
      /sbin/iptables -I INPUT -s $reflector -j DROP
      logger "[RLABP Debug]: Dynamic timer expired. Disconnecting..."
    fi
  fi

  # Start debug if enabled
  if $debug && [[ -z $dt || $dt -eq $debug_frq ]]; then
    dmsg="[RLABP Debug]: RF: $rf_ptt / TCL: $rf_ptt_tcl / Net: $net_ptt"
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
