#!/bin/sh
# Configure the I/O scheduler and readahead from each device's own rotational
# flag, so the same hook is correct on HDD, SATA SSD and NVMe machines.
#
# No device name is hardcoded: the loop walks every real block device, which
# covers the root disk whatever it is called (sda, vda, nvme0n1, mmcblk0).

set_queue() {
    q=$1
    [ -d "$q" ] || return 0

    case "$(cat "$q/scheduler" 2>/dev/null)" in
        '') return 0 ;;
    esac

    if [ "$(cat "$q/rotational" 2>/dev/null)" = 1 ]; then
        # Rotational: bfq gives better interactive latency under mixed load.
        # mq-deadline is the portable fallback when the kernel lacks bfq.
        case "$(cat "$q/scheduler" 2>/dev/null)" in
            *bfq*) echo bfq         > "$q/scheduler" 2>/dev/null ;;
            *)     echo mq-deadline > "$q/scheduler" 2>/dev/null ;;
        esac
        echo 2048 > "$q/read_ahead_kb" 2>/dev/null
    else
        # Flash: no scheduler reordering worth doing, and a small readahead.
        echo none > "$q/scheduler" 2>/dev/null
        echo 128  > "$q/read_ahead_kb" 2>/dev/null
    fi

    return 0
}

for q in /sys/block/*/queue; do
    dev=${q#/sys/block/}
    dev=${dev%/queue}

    # Virtual, loop-backed and optical devices keep their defaults.
    case "$dev" in
        loop*|zram*|ram*|dm-*|md*|sr*|fd*) continue ;;
    esac

    set_queue "$q"
done
