#!/bin/bash
airport_path="/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport"

# Check if airport is available
if [[ ! -x $airport_path ]]; then
    echo "$airport_path: not found" 1>&2
    exit 1
fi

signals=(▁ ▂ ▃ ▅ ▇)

# Get the wifi information and then set it to an info array
info=( $(eval "$airport_path" --getinfo | grep -E "^ *(agrCtlRSSI|state|lastTxRate|SSID):" | awk '{print $2}') )
if [[ ${#info[@]} -eq 0 ]]; then
    echo "offline"
    exit 1
fi

# cut out a needed information from the info
# reference: http://osxdaily.com/2007/01/18/airport-the-little-known-command-line-wireless-utility/
rssi="${info[0]}"   # strength of wifi wave
stat="${info[1]}"   # whether wifi is available
rate="${info[2]}"   # bandwidth of wifi wave
ssid="${info[3]}"   # wifi ssid name

# Determine the signal from rssi of wifi
signal=""
for ((j = 0; j < "${#signals[@]}"; j++))
do
    if ((  $j == 0 && $rssi > -100 )) ||
        (( $j == 1 && $rssi > -80  )) ||
        (( $j == 2 && $rssi > -60  )) ||
        (( $j == 3 && $rssi > -40  )) ||
        (( $j == 4 && $rssi > -20  )); then
        # make signal
        signal="${signal}${signals[$j]}"
    else
        signal="${signal}"
    fi
done

# If the wifi rate (wifi bandwidth) is unavailable,
if [ "$rate" = 0 ]; then
    echo "no_wifi"
    exit 1
fi

# Outputs wifi
echo -e "#[bg=yellow,fg=black][${ssid} ${rate}Mbs ${signal}]#[default]"
