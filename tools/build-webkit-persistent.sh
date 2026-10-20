#!/bin/sh -e
# Build persistente de webkitgtk: permite recompilar SOLO lo afectado por un
# parche (ninja incremental), en vez de una hora de build completo.
# Ver docs/ccache-kiss.md.
#
# Uso:
#   tools/build-webkit-persistent.sh setup    # extrae fuente, aplica parches, configura
#   tools/build-webkit-persistent.sh build    # compila (incremental)
#   tools/build-webkit-persistent.sh install  # instala en /usr (requiere root)
#   tools/build-webkit-persistent.sh patch    # re-aplica parches y reconstruye incremental

SPRINT="$(cd "$(dirname "$0")/.." && pwd)"
RECIPE="$SPRINT/extra/webkitgtk"
WORK="${WEBKIT_BUILD_DIR:-$HOME/webkit-build}"
VER="$(cut -d' ' -f1 "$RECIPE/version")"
TARBALL="$HOME/.cache/kiss/sources/webkitgtk/webkitgtk-$VER.tar.xz"
SRCDIR="$WORK/webkitgtk-$VER"
JOBS="${JOBS:-16}"

apply_patches() {
	cd "$SRCDIR"
	for p in "$RECIPE"/patches/*.patch; do
		name=$(basename "$p")
		# Parche ya aplicado: se omite. Cualquier otro fallo aborta el build.
		if patch -p1 -R --dry-run < "$p" >/dev/null 2>&1; then
			echo "-> $name (ya aplicado)"
			continue
		fi
		echo "-> $name"
		patch -p1 < "$p" || {
			echo "Fallo al aplicar el parche $name" >&2
			echo "Abortando para no instalar un árbol sin parchear" >&2
			exit 1
		}
	done
}

setup() {
	[ -f "$TARBALL" ] || { echo "Falta la fuente: $TARBALL"; exit 1; }
	mkdir -p "$WORK"
	[ -d "$SRCDIR" ] || tar -xJf "$TARBALL" -C "$WORK"
	apply_patches
	cd "$SRCDIR"
	cmake -B build -G Ninja \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_INSTALL_LIBDIR=lib \
		-DCMAKE_SKIP_RPATH=ON \
		-DCMAKE_C_COMPILER=clang \
		-DCMAKE_CXX_COMPILER=clang++ \
		-DCMAKE_C_COMPILER_TARGET=x86_64-pc-linux-musl \
		-DCMAKE_CXX_COMPILER_TARGET=x86_64-pc-linux-musl \
		-DCMAKE_C_COMPILER_LAUNCHER=ccache \
		-DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
		-DCMAKE_EXE_LINKER_FLAGS=-fuse-ld=lld \
		-DCMAKE_SHARED_LINKER_FLAGS=-fuse-ld=lld \
		-DPORT=GTK -DUSE_GTK4=OFF -DUSE_LD_LLD=ON \
		-DUSE_LIBBACKTRACE=OFF -DUSE_SOUP2=OFF -DUSE_WOFF2=ON \
		-DUSE_FLITE=OFF -DUSE_SPIEL=ON \
		-DENABLE_BUBBLEWRAP_SANDBOX=ON -DENABLE_DOCUMENTATION=OFF \
		-DENABLE_INTROSPECTION=ON -DENABLE_JOURNALD_LOG=OFF \
		-DENABLE_MINIBROWSER=ON -DENABLE_SAMPLING_PROFILER=OFF \
		-DENABLE_WAYLAND_TARGET=OFF -DENABLE_X11_TARGET=ON \
		-DENABLE_JIT=ON -DENABLE_C_LOOP=OFF -DENABLE_WEBASSEMBLY=ON
}

build() {
	cd "$SRCDIR"
	ninja -C build -j "$JOBS"
}

case "${1:-}" in
	setup)   setup ;;
	build)   build ;;
	patch)   apply_patches; build ;;
	install) cd "$SRCDIR"; DESTDIR="${DESTDIR:-}" ninja -C build install ;;
	*) echo "uso: $0 {setup|build|patch|install}"; exit 1 ;;
esac
