#!/bin/sh
# ZRAM dinamico por RAM total (dual Xeon 8GB / Ryzen tamano variable).
# Equivale a 6G zstd (pri=100) + 4G lz4 (pri=99) en 8 GB, y escala fuera de ahi:
# zram0 = 75% MemTotal, zram1 = 50% MemTotal.
# Runs as boot hook AFTER swapon -a.

mem_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null)
case $mem_kb in ''|*[!0-9]*) mem_kb=8388608 ;; esac # fallback 8 GiB
z0_mb=$(( mem_kb * 3 / 4 / 1024 ))
z1_mb=$(( mem_kb / 2 / 1024 ))
[ "$z0_mb" -ge 512 ] || z0_mb=512
[ "$z1_mb" -ge 256 ] || z1_mb=256

# zram0 - zstd, high priority
if [ -e /sys/block/zram0 ]; then
    echo zstd > /sys/block/zram0/comp_algorithm 2>/dev/null || true
    echo "${z0_mb}M" > /sys/block/zram0/disksize 2>/dev/null || true
    grep -q zram0 /proc/swaps || {
        mkswap /dev/zram0
        swapon -p 100 /dev/zram0
    }
fi

# zram1 - lz4, lower priority
zramctl -f -s "${z1_mb}M" -a lz4 2>/dev/null

if [ -e /sys/block/zram1 ]; then
    grep -q zram1 /proc/swaps || {
        mkswap /dev/zram1
        swapon -p 99 /dev/zram1
    }
fi
