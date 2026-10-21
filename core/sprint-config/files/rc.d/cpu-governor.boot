#!/bin/sh
# CPU Governor - performance (frecuencia maxima)
#
# Con schedutil la CPU se quedaba entre 1,8 y 2,2 GHz durante los builds y
# no llegaba al maximo de la E5-2640 v3 (3,4 GHz con un nucleo, 2,9 GHz con
# todos). Medido: 1,2-2,2 GHz con schedutil frente a 2,8-3,0 GHz con
# performance, es decir un 30-40% mas de reloj en los nucleos que compilan.
#
# El precio: con el gobernador performance los nucleos ociosos tambien se
# quedan a la maxima, asi que hay mas consumo en reposo y mas calor. Para
# volver al equilibrio:
#
#   for g in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
#       echo schedutil > "$g"
#   done
#
for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    echo performance > "$cpu" 2>/dev/null || true
done
