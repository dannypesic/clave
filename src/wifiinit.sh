#!/bin/sh
echo "Setting up WiFi..."
ip link set wlan0 up
wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant.conf

echo "Waiting for association..."
n=0
while [ "$n" -lt 30 ]; do
    carrier=$(cat /sys/class/net/wlan0/carrier 2>/dev/null)
    [ "$carrier" = "1" ] && break
    sleep 1
    n=$((n + 1))
done
if [ "$carrier" != "1" ]; then
    echo "wifiinit: timed out waiting for association"
    exit 1
fi

udhcpc -i wlan0 -b -p /var/run/udhcpc.pid
sleep 2
ping -c 2 8.8.8.8
echo "Connected"
