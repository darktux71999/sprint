#!/bin/sh
# ZRAM setup: 6G zstd (pri=100) + 4G lz4 (pri=99)
# Runs as boot hook AFTER swapon -a.

# zram0 - zstd, high priority
if [ -e /sys/block/zram0 ]; then
    echo zstd > /sys/block/zram0/comp_algorithm 2>/dev/null || true
    echo 6G  > /sys/block/zram0/disksize       2>/dev/null || true
    grep -q zram0 /proc/swaps || {
        mkswap /dev/zram0
        swapon -p 100 /dev/zram0
    }
fi

# zram1 - lz4, lower priority
zramctl -f -s 4G -a lz4 2>/dev/null

if [ -e /sys/block/zram1 ]; then
    grep -q zram1 /proc/swaps || {
        mkswap /dev/zram1
        swapon -p 99 /dev/zram1
    }
fi
