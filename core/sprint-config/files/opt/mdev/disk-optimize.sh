#!/bin/sh
# Optimizar discos cuando se detectan (regla mdev sd[a-z]).
Q="/sys/block/${MDEV}/queue"
[ -d "$Q" ] || exit 0
if [ "$(cat "/sys/block/${MDEV}/queue/rotational" 2>/dev/null)" = 1 ]; then
    echo bfq > "$Q/scheduler" 2>/dev/null
else
    echo mq-deadline > "$Q/scheduler" 2>/dev/null
fi
echo 256 > "$Q/nr_requests" 2>/dev/null
echo 2048 > "$Q/read_ahead_kb" 2>/dev/null
[ -f "$Q/iosched/writes_starved" ] && echo 2 > "$Q/iosched/writes_starved"
[ -f "$Q/iosched/read_expire" ] && echo 150 > "$Q/iosched/read_expire"
[ -f "$Q/iosched/write_expire" ] && echo 1500 > "$Q/iosched/write_expire"
