#!/bin/sh
# build-class: perfil de compilación por clase de paquete para el repo sprint.
#
# Uso: tools/build-class.sh <clase> [campo]
#
# Clases:
#   light   C pequeño (librerías y herramientas ligeras)
#   medium  C/C++ mediano (chawan, go, python)
#   heavy   C++/Rust pesado (firefox, webkitgtk, llvm, mesa, kicad)
#   link    una sola tarea de enlace, hilos de lld limitados
#
# Campos: jobs | cflags | cxxflags | ldflags | makeflags | env
# (por defecto: jobs).
#
# Los trabajos se calculan con la RAM disponible real, menos una reserva
# para el sistema. BUILD_CLASS_MEM_KB fija la RAM disponible (KB) de forma
# determinista y BUILD_CLASS_NPROC fija los hilos visibles; ambas existen
# para pruebas herméticas.

set -e

die() { printf '%s\n' "$*" >&2; exit 2; }

class=${1:-}
field=${2:-jobs}

case $class in
    light|medium|heavy|link) ;;
    *) die "clase desconocida: ${class:-<vacía>} (esperado light|medium|heavy|link)" ;;
esac

case $field in
    jobs|cflags|cxxflags|ldflags|makeflags|env) ;;
    *) die "campo desconocido: $field" ;;
esac

# --- presupuesto de RAM ----------------------------------------------------
# Reserva para el sistema (shells, X, servicios) más un margen de seguridad
# para picos de enlace antes de que el zram absorba.
reserve_kb=786432   # 768 MiB

mem_kb=${BUILD_CLASS_MEM_KB:-}
if [ -z "$mem_kb" ]; then
    mem_kb=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
fi
[ -n "$mem_kb" ] || die 'no se pudo leer MemAvailable'

usable_kb=$((mem_kb - reserve_kb))
[ "$usable_kb" -gt 0 ] || usable_kb=0

nproc=${BUILD_CLASS_NPROC:-$(nproc 2>/dev/null || echo 4)}

# --- modelo por clase ------------------------------------------------------
# ram_job_kb: RAM estimada por trabajo de compilación en paquetes de la clase.
case $class in
    light)  ram_job_kb=409600  cap=$nproc ;;
    medium) ram_job_kb=921600  cap=8 ;;
    heavy)  ram_job_kb=1843200 cap=6 ;;
    link)   ram_job_kb=0       cap=1 ;;
esac

if [ "$class" = link ]; then
    jobs=1
else
    jobs=$((usable_kb / ram_job_kb))
    [ "$jobs" -ge 1 ] || jobs=1
    [ "$jobs" -le "$cap" ] || jobs=$cap
fi

# Hilos de lld para el enlace: nunca más de 4 ni más que los trabajos.
lld_threads=$((jobs < 4 ? jobs : 4))
[ "$lld_threads" -ge 1 ] || lld_threads=1

# --- flags por clase -------------------------------------------------------
base_cflags='-pipe -march=native -mtune=native'

case $class in
    light)  cflags="-O3 $base_cflags" ;;
    medium) cflags="-O2 $base_cflags" ;;
    heavy)  cflags="-O2 $base_cflags" ;;
    link)   cflags="-O2 $base_cflags" ;;
esac
cxxflags=$cflags
ldflags="-fuse-ld=lld -Wl,--threads=$lld_threads -Wl,-O2 -Wl,-s"
makeflags="-j$jobs"

case $field in
    jobs)      printf '%s\n' "$jobs" ;;
    cflags)    printf '%s\n' "$cflags" ;;
    cxxflags)  printf '%s\n' "$cxxflags" ;;
    ldflags)   printf '%s\n' "$ldflags" ;;
    makeflags) printf '%s\n' "$makeflags" ;;
    env)
        printf 'export CFLAGS="%s"\n' "$cflags"
        printf 'export CXXFLAGS="%s"\n' "$cxxflags"
        printf 'export LDFLAGS="%s"\n' "$ldflags"
        printf 'export MAKEFLAGS="%s"\n' "$makeflags"
        ;;
esac
