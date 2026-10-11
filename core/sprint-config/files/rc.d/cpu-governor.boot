#!/bin/sh
# CPU Governor - schedutil (balance rendimiento/consumo)
for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    echo schedutil > "$cpu" 2>/dev/null || true
done
