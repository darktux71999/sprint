#!/bin/sh
# Static network configuration with address collision detection.
#
# The preferred address is used when nothing answers for it. If some other
# host already owns it, the hook walks a candidate range and takes the first
# free slot instead of fighting for the same address.
#
# Detection is ARP based: arping when it can open a raw socket (the hook runs
# as root at boot), and otherwise ping, which makes the kernel resolve ARP
# anyway. The neighbour table is the actual decision point, so it works even
# when the device drops ICMP.

IF=eth0
GW=192.168.1.1
PREFIX=24
PREF=192.168.1.45
FIRST=50
LAST=99
DNS1=1.1.1.1
DNS2=1.0.0.1

ip link set lo up
ip link set "$IF" up

# Returns 0 when the address is taken, 1 when it looks free.
ip_in_use() {
    arping -q -c 1 -w 1 -I "$IF" "$1" >/dev/null 2>&1

    ping -c 1 -W 1 "$1" >/dev/null 2>&1 && return 0

    ip neigh show "$1" 2>/dev/null | grep -q lladdr
}

base=${PREF%.*}
addr=

if ! ip_in_use "$PREF"; then
    addr=$PREF
else
    i=$FIRST
    while [ "$i" -le "$LAST" ]; do
        if ! ip_in_use "$base.$i"; then
            addr=$base.$i
            break
        fi
        i=$((i + 1))
    done
fi

# Never leave the machine without a network: a possible duplicate is better
# than no route at all.
[ -n "$addr" ] || addr=$PREF

ip addr add "$addr/$PREFIX" dev "$IF" 2>/dev/null || :
ip route add default via "$GW" 2>/dev/null || :

cat > /etc/resolv.conf << EOF
nameserver $DNS1
nameserver $DNS2
EOF
