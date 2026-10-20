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
# cap: tope de trabajos simultáneos de esa clase.
#
# Los valores salen de mediciones reales del pico de RSS (VmHWM) por trabajo
# en esta máquina, con un factor de seguridad:
#   light  = 68-74 MB medidos (C pequeño)  -> 256 MiB por trabajo, tope nproc
#   medium = sin medicion directa          -> 512 MiB por trabajo, tope 8
#   heavy  = 230-384 MB medidos (C++ de LLVM con -O2) -> 768 MiB, tope 4
# El tope de heavy son 4 porque el enlace de un binario grande (libLLVM.so,
# libxul con ThinLTO) pide del orden de 3 GB y debe caber junto a los
# trabajos que sigan compilando.
case $class in
    light)  ram_job_kb=262144  cap=$nproc ;;
    medium) ram_job_kb=524288  cap=8 ;;
    heavy)  ram_job_kb=786432  cap=4 ;;
esac

if [ "$class" = link ]; then
    # El enlace grande es el que tumba la máquina: un solo trabajo.
    jobs=1
else
    jobs=$((usable_kb / ram_job_kb))
    [ "$jobs" -ge 1 ] || jobs=1
    [ "$jobs" -le "$cap" ] || jobs=$cap
fi

# Hilos de lld para el enlace: nunca más de 4 ni más que los trabajos.
# jobs >= 1 siempre, así que lld_threads >= 1.
lld_threads=$((jobs < 4 ? jobs : 4))

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
    *)
        # La validación de arriba ya lo impide; este caso evita que un
        # campo nuevo que se añadiera solo a la lista se quede mudo.
        die "campo desconocido: $field"
        ;;
esac
