#!/bin/sh
# io-scheduler dinamico por tipo de disco (dual Xeon / Ryzen).
# - HDD rotacional (rotational=1, p. ej. sda): bfq, mejor respuesta
#   interactiva durante builds.
# - NVMe/SSD (rotational=0): none si existe, si no kyber, si no mq-deadline.
# Sin cambios si el scheduler pedido no esta disponible en el kernel.
for q in /sys/block/*/queue/scheduler; do
    blk=${q#/sys/block/}; blk=${blk%/queue/scheduler}
    case "$blk" in loop*|ram*|zram*|dm-*|sr*) continue ;; esac
    [ -r "$q" ] || continue
    avail=$(cat "$q" 2>/dev/null) || continue
    rot=$(cat "/sys/block/$blk/queue/rotational" 2>/dev/null) || rot=""
    if [ "$rot" = "1" ]; then
        want="bfq"
    else
        want=""
        for s in none kyber mq-deadline; do
            case "$avail" in
                *"[$s]"*) want=""; break ;; # ya activo
                *"$s"*) want="$s"; break ;;
            esac
        done
        [ -z "$want" ] && continue
    fi
    echo "$want" > "$q" 2>/dev/null || true
done
