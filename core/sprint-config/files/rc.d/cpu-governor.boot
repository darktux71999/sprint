#!/bin/sh
# CPU Governor dinamico por fabricante.
# - GenuineIntel (Xeon E5-2640 v3 actual): performance.
#   Con schedutil la CPU se quedaba entre 1,8 y 2,2 GHz durante los builds y
#   no llegaba al maximo (3,4 GHz un nucleo, 2,9 GHz todos). Medido:
#   1,2-2,2 GHz con schedutil frente a 2,8-3,0 GHz con performance,
#   es decir un 30-40% mas de reloj en los nucleos que compilan.
# - AuthenticAMD (Ryzen 5 PRO 2400GE 35W): schedutil si existe (amd_pstate),
#   si no ondemand, si no conservative. Evita dejar los 4c/8t fijos al maximo.
#
# El precio de performance: nucleos ociosos a la maxima, mas consumo y calor.
# Para volver al equilibrio en Intel:
#
#   for g in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
#       echo schedutil > "$g"
#   done
#
VENDOR=""
[ -r /proc/cpuinfo ] && VENDOR=$(awk -F': ' '/^vendor_id/ {print $2; exit}' /proc/cpuinfo)

GOV="performance"
if [ "$VENDOR" = "AuthenticAMD" ]; then
    if [ -r /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors ]; then
        AVAIL=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors)
        case " $AVAIL " in
            *" schedutil "*) GOV="schedutil" ;;
            *" ondemand "*) GOV="ondemand" ;;
            *" conservative "*) GOV="conservative" ;;
            *" powersave "*) GOV="powersave" ;;
        esac
    else
        GOV="schedutil"
    fi
fi

for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    echo "$GOV" > "$cpu" 2>/dev/null || true
done
