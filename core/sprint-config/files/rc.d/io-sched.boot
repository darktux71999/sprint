#!/bin/sh
# sda (HDD): bfq para mejor respuesta interactiva durante builds.
sched=/sys/block/sda/queue/scheduler
echo bfq > "$sched" 2>/dev/null || true
if type log >/dev/null 2>&1; then
    log "io-sched: sda -> $(cat "$sched" 2>/dev/null)"
fi
