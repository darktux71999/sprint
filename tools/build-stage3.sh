#!/bin/sh -e
# build-stage3.sh — construye el stage3 Base en ~/stage3 solo con recetas sprint.
#
# Garantias:
#   * Todo install va a KISS_ROOT=$STAGE (DB separada en $STAGE/var/db/kiss).
#   * Fase 1 (linux-headers, musl) con toolchain host; fase 2 con
#     --sysroot=$STAGE + PKG_CONFIG_LIBDIR solo-stage: nada enlaza al host.
#   * Env hermetico por paquete (env -i), flags fijos x86-64-v2 (no native:
#     Xeon E5-2640 v3 y Ryzen 2400GE comparten baseline, el binario corre igual).
#   * Idempotente: salta paquetes ya instalados en stage con misma version.
#   * Sin tocar recetas existentes; solo lee el repo y escribe $STAGE + log.
#
# Uso:
#   tools/build-stage3.sh [--check-order] [--phase 1|2|3|4|all] [--only "p1 p2"]
#                         [--verify] [--tar [archivo]]
#   Por defecto: --phase all (sin --verify ni --tar). --only construye los
#   paquetes listados con sysroot=1 (para iterar miembros de fase 3).
#   REBUILD="p1 p2" fuerza reconstruccion aunque la version ya este en stage
#   (ej. REBUILD=python tras agregar xz al cierre para que detecte liblzma).
#
# Requiere: repo sprint, kiss funcional, cc/c++ (clang), $STAGE existente.

REPO="$(cd "$(dirname "$0")/.." && pwd)"
STAGE="${STAGE:-$HOME/stage3}"
LOG="${LOG:-$HOME/stage3-build.log}"
EPOCH="${SOURCE_DATE_EPOCH:-0}"

# Orden topologico del cierre Base (44). Regenerar y comparar con --check-order.
PKGS="b3sum baseinit baselayout bzip2 certs expat kiss-sprint libffi
linux-headers busybox m4 bison flex libtool make gawk musl ncurses libedit
pkgconf readline samurai xz zlib perl autoconf automake openssl curl cmake git
pigz sqlite python ninja python-gpep517 python-installer python-flit-core
python-packaging python-setuptools python-wheel meson zstd llvm"
# Fases (orden causal, no alfabetico):
#   1: headers+musl sin sysroot (cimentan el stage).
#   2: libatomic + llvm sin sysroot. llvm se auto-contiene (runtimes propios)
#      y provee libunwind.a/libc++ que los enlaces -static necesitan.
#      Sin CMAKE_PREFIX_PATH: ese flag mete -I$STAGE/usr/include en los
#      compiles C++ host y rompe los headers de libc++ (errno.h); llvm
#      encuentra zlib/zstd/editline del host en rutas identicas a stage.
#   3: todo lo demas con sysroot, salvo herramientas C++ (usan musl,
#      unwind y atomic ya instalados en el stage).
#   4: cmake ninja samurai sin sysroot (herramientas C++ de build; enlazan
#      libc++ host en rutas identicas a stage, verificado al final).
PHASE1="linux-headers musl"
PHASE2="libatomic llvm"
PHASE4="cmake ninja samurai"

CFLAGS_BASE="-O2 -pipe -march=x86-64-v2 -mtune=generic"
LDFLAGS_BASE="-Wl,-O2 -Wl,--threads=4 -Wl,-s"

die() { printf 'stage3: %s\n' "$*" >&2; exit 2; }
log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG"; }

[ -d "$STAGE" ] || die "$STAGE no existe (crealo en el otro fs primero)"
[ "$STAGE" != "/" ] && [ "$STAGE" != "$HOME" ] || die "STAGE inseguro: $STAGE"
command -v kiss >/dev/null || die "kiss no esta en PATH"
KISS_BIN="$(command -v kiss)"
command -v rg >/dev/null && command -v fd >/dev/null || die "rg y fd requeridos en el host"
command -v cc >/dev/null && command -v c++ >/dev/null || die "cc/c++ (clang) requeridos"
CC_BIN="$(command -v cc)"; CXX_BIN="$(command -v c++)"

KISS_PATH="$REPO/core:$REPO/extra:$REPO/xorg:$REPO/test:$REPO/python"
export KISS_PATH

check_order() {
    got=$(python3 - "$REPO" <<'EOF'
import os, sys, collections
repos = ['core', 'extra', 'xorg', 'python', 'test']
depmap = {}
for r in repos:
    d = os.path.join(sys.argv[1], r)
    for p in os.listdir(d):
        f = os.path.join(d, p, 'depends')
        if os.path.isfile(f):
            ds = []
            for line in open(f):
                line = line.strip()
                if not line or line.startswith('#'):
                    continue
                ds.append(line.split()[0])
            depmap[p] = ds
seeds = ("baselayout baseinit busybox musl linux-headers certs b3sum git "
         "kiss-sprint llvm make samurai meson ninja cmake autoconf automake "
         "libtool pkgconf m4 bison flex gawk perl python curl openssl xz pigz").split()
seen = set()
stack = list(seeds)
while stack:
    p = stack.pop()
    if p in seen:
        continue
    seen.add(p)
    stack.extend(depmap.get(p, []))
indeg = {p: 0 for p in seen}
rev = collections.defaultdict(list)
for p in seen:
    for q in depmap.get(p, []):
        if q in seen:
            indeg[p] += 1
            rev[q].append(p)
ready = sorted(p for p in seen if indeg[p] == 0)
out = []
while ready:
    p = ready.pop(0)
    out.append(p)
    for r in sorted(rev[p]):
        indeg[r] -= 1
        if indeg[r] == 0:
            ready.append(r)
            ready.sort()
cyc = sorted(p for p in seen if indeg[p] > 0)
if cyc:
    sys.exit('ciclos: ' + ' '.join(cyc))
print(' '.join(out))
EOF
)
    want=$(printf '%s' "$PKGS" | tr '\n' ' ' | tr -s ' ')
    [ "$got" = "$want" ] || {
        printf 'orden embebido != repo:\nrepo: %s\n' "$got" >&2
        return 1
    }
    log "orden OK (44 pkgs, sin ciclos, 0 faltantes)"
}

build_one() {
    pkg=$1
    sysroot=$2  # 0|1
    ver=$(fd -d 2 -t d --glob "$pkg" "$REPO" --exec cat '{}/version' \; 2>/dev/null | head -n 1)
    if [ -f "$STAGE/var/db/kiss/installed/$pkg/version" ] && \
       [ "$(cat "$STAGE/var/db/kiss/installed/$pkg/version")" = "$ver" ]; then
        case " ${REBUILD:-} " in
            *" $pkg "*) log "rebuild $pkg ($ver, forzado por REBUILD)" ;;
            *) log "skip $pkg ($ver ya en stage)"; return 0 ;;
        esac
    fi
    if [ "$sysroot" = 1 ]; then
        cflags="$CFLAGS_BASE --sysroot=$STAGE"
        ldflags="$LDFLAGS_BASE --sysroot=$STAGE"
        cppflags="--sysroot=$STAGE"
        pc_lib="$STAGE/usr/lib/pkgconfig:$STAGE/usr/share/pkgconfig"
        pc_sys="$STAGE"
        # Solo curl-config del stage via shim: el del host lista -lnghttp2,
        # inexistente en el sysroot, y rompe el enlace de git (unico usuario).
        # Un PATH stage-first global rompe recetas que derivan rutas de la
        # herramienta en ejecucion (`python3 -c ...getsitepackages()` devuelve
        # rutas con prefijo stage y caen fuera del destdir): el resto sigue host.
        shim="$HOME/.cache/stage3-shims"
        mkdir -p "$shim"
        if [ -x "$STAGE/usr/bin/curl-config" ]; then
            ln -sf "$STAGE/usr/bin/curl-config" "$shim/curl-config"
        fi
        path_prefix="$shim:"
    else
        # Sin sysroot NO se fija SYSROOT_DIR: pkg-config reescribiria los -I
        # del host hacia el stage y esos headers sombrean a libc++ (errno.h).
        cflags="$CFLAGS_BASE"
        ldflags="$LDFLAGS_BASE"
        cppflags=""
        pc_lib=
        pc_sys=
        path_prefix=
    fi
    log "build $pkg (sysroot=$sysroot)"
    # setsid: kiss ejecuta `kill 0` cuando un build falla (limpia su grupo).
    # Sin nueva sesion, esa senal mataria tambien este script.
    # KISS_BIN pineado al host: con sysroot el PATH lleva el stage delante y
    # su kiss-sprint sombrearia al kiss que ya probo este flujo.
    env -i PATH=${path_prefix}/usr/local/sbin:/usr/local/bin:/usr/bin:/usr/sbin:/sbin:/bin \
        HOME="$HOME" TMPDIR="${TMPDIR:-/tmp}" \
        LOGNAME="${LOGNAME:-$(id -un 2>/dev/null || echo root)}" \
        USER="${USER:-${LOGNAME:-$(id -un 2>/dev/null || echo root)}}" \
        CC="$CC_BIN" CXX="$CXX_BIN" CFLAGS="$cflags" CXXFLAGS="$cflags" CPPFLAGS="$cppflags" \
        LDFLAGS="$ldflags" MAKEFLAGS="-j$(nproc)" \
        ${pc_lib:+PKG_CONFIG_LIBDIR="$pc_lib"} \
        ${pc_sys:+PKG_CONFIG_SYSROOT_DIR="$pc_sys"} \
        SOURCE_DATE_EPOCH="$EPOCH" \
        KISS_PATH="$KISS_PATH" KISS_ROOT="$STAGE" \
        setsid "$KISS_BIN" build "$pkg" >>"$LOG" 2>&1 || {
        log "FALLO $pkg (ver $LOG)"
        return 1
    }
    log "ok $pkg"
}

do_phase() {
    case $1 in
        1) for p in $PHASE1; do build_one "$p" 0 || return 1; done ;;
        2) for p in $PHASE2; do
               # La receta llvm compila en BUILD_ROOT persistente
               # ($HOME/.cache/llvm-build) para conservar el corpus PGO.
               # Un resto de otro build (host o intento previo) deja un
               # CMakeCache con rutas viejas y cmake aborta: limpiar.
               case $p in llvm)
                   if [ -d "${LLVM_BUILD_DIR:-$HOME/.cache/llvm-build}" ]; then
                       log "limpiando BUILD_ROOT llvm persistente"
                       rm -rf "${LLVM_BUILD_DIR:-$HOME/.cache/llvm-build}"
                   fi ;;
               esac
               build_one "$p" 0 || return 1
           done ;;
        3) for p in $PKGS; do
               case " $PHASE1 $PHASE2 $PHASE4 " in *" $p "*) continue ;; esac
               build_one "$p" 1 || return 1
           done ;;
        4) for p in $PHASE4; do build_one "$p" 0 || return 1; done ;;
        *) die "fase invalida: $1 (1|2|3|4|all)" ;;
    esac
}

do_verify() {
    log "verificando ELF (NEEDED dentro de stage, sin RPATH externo)"
    fail=0
    for f in $(fd -H --no-ignore -t x --absolute-path . "$STAGE"); do
        case $(head -c 4 "$f" | od -An -t x1 | tr -d ' \n') in
            7f454c46) : ;; # ELF
            *) continue ;;
        esac
        interp=$(readelf -l "$f" 2>/dev/null | awk '/INTERP/{getline; print}' | \
            sed 's/.*Requesting program interpreter: \([^]]*\)]/\1/')
        if [ -n "$interp" ] && [ ! -e "$STAGE$interp" ]; then
            log "INTERP fuera de stage: $f -> $interp"; fail=1
        fi
        for lib in $(readelf -d "$f" 2>/dev/null | sed -n 's/.*NEEDED.*\[\(.*\)\]/\1/p'); do
            if [ ! -e "$STAGE/lib/$lib" ] && [ ! -e "$STAGE/usr/lib/$lib" ]; then
                log "NEEDED fuera de stage: $f -> $lib"; fail=1
            fi
        done
        rpath=$(readelf -d "$f" 2>/dev/null | sed -n 's/.*\(RPATH\|RUNPATH\).*\[\(.*\)\]/\2/p')
        case $rpath in ''|/usr*|/lib*) : ;; *)
            log "RPATH externo: $f -> $rpath"; fail=1 ;;
        esac
    done
    [ "$fail" = 0 ] && log "ELF OK" || return 1
}

do_tar() {
    out="${1:-$HOME/stage3-base.tar}"
    log "tarball $out (mtimes a @$EPOCH, orden determinista)"
    fd -H --no-ignore --absolute-path . "$STAGE" --exec-batch touch -h -d "@$EPOCH" 2>/dev/null || \
        die "touch -d no soportado"
    if tar --help 2>&1 | rg -q -- '-T'; then
        # --no-recursion: la lista ya trae cada fichero y dir explicito;
        # sin el, tar redesciende en cada dir listado y duplica el arbol.
        # --exclude de docs: el stage es build-rootfs, man/info/doc no compilan
        # (tambien se borran del dir para que stage y tarball coincidan).
        (cd "$STAGE" && fd --strip-cwd-prefix=never --min-depth 1 -H --no-ignore . | LC_ALL=C sort | \
            tar -cf "$out" -T - --numeric-owner --no-recursion \
                --exclude='./usr/share/man' --exclude='./usr/share/info' --exclude='./usr/share/doc')
    else
        log "tar sin -T: orden no garantizado"
        tar -cf "$out" -C "$STAGE" . --numeric-owner
    fi
    log "tarball OK: $(du -h "$out" | cut -f1)"
}

PH=; VER=0; TAR=0; CHK=0; ONLY=
prev=
for a in "$@"; do
    if [ -n "$prev" ]; then
        case $prev in
            phase) PH=$a ;; only) ONLY=$a ;;
        esac
        prev=; continue
    fi
    case $a in
        --phase) prev=phase ;;
        --only) prev=only ;;
        --verify) VER=1 ;; --tar) TAR=1 ;; --check-order) CHK=1 ;;
        *) die "uso: $0 [--check-order] [--phase 1|2|3|4|all] [--only \"..\"] [--verify] [--tar]" ;;
    esac
done
[ -n "$prev" ] && die "--phase/--only necesitan argumento"
# Sin args: fase completa (documentado). Con flags: solo lo pedido.
[ $# = 0 ] && PH=all

[ "$CHK" = 1 ] && check_order
if [ -n "$ONLY" ]; then
    for p in $ONLY; do build_one "$p" 1 || exit 1; done
fi
FAIL=0
case $PH in
    "") : ;;
    1) do_phase 1 || FAIL=1 ;;
    2) do_phase 2 || FAIL=1 ;;
    3) do_phase 3 || FAIL=1 ;;
    4) do_phase 4 || FAIL=1 ;;
    all) do_phase 1 && do_phase 2 && do_phase 3 && do_phase 4 || FAIL=1 ;;
    *) die "fase invalida: $PH" ;;
esac
[ "$VER" = 1 ] && { do_verify || FAIL=1; }
[ "$TAR" = 1 ] && { do_tar "$OUT" || FAIL=1; }
if [ "$FAIL" = 1 ]; then log "FALLOS registrados (ver arriba y $LOG)"; exit 1; fi
log "hecho"
