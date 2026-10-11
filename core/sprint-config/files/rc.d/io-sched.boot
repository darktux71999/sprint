#!/bin/sh
# sda (HDD): bfq para mejor respuesta interactiva durante builds.
# Sondas temporales para diagnosticar por que la escritura no queda en el arranque.
sched=/sys/block/sda/queue/scheduler
n=0
while [ "$n" -lt 5 ]; do
    echo bfq > "$sched" 2>/dev/null || true
    grep -q '\[bfq\]' "$sched" 2>/dev/null && break
    n=$((n + 1))
    sleep 1
done
if type log >/dev/null 2>&1; then
    log "io-sched: sda -> $(cat "$sched" 2>/dev/null)"
    (
        sleep 15
        log "io-sched: +15s -> $(cat "$sched" 2>/dev/null)"
        sleep 30
        grep -q '\[bfq\]' "$sched" 2>/dev/null || echo bfq > "$sched" 2>/dev/null
        log "io-sched: +45s -> $(cat "$sched" 2>/dev/null)"
    ) >/dev/null 2>&1 &
fi
