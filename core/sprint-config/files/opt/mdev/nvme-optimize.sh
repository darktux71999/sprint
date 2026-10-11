#!/bin/sh
# Optimizar NVMe cuando se detecta
Q="/sys/block/${MDEV}/queue"
[ -d "$Q" ] || exit 0
echo none > "$Q/scheduler" 2>/dev/null
echo 1024 > "$Q/nr_requests" 2>/dev/null
echo 128 > "$Q/read_ahead_kb" 2>/dev/null
echo 1024 > "$Q/max_sectors_kb" 2>/dev/null
