#!/bin/sh
# sda (HDD): bfq para mejor respuesta interactiva durante builds.
echo bfq > /sys/block/sda/queue/scheduler 2>/dev/null || true
