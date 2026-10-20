# Reconstruir el árbol de recetas con el compilador nuevo

Plan para volver a construir el árbol de `~/proyectos/sprint` contra el
toolchain reconstruido (clang con `bolt`, PGO y `-march=native`), sin que la
máquina se quede sin compilador a mitad.

## Premisas

- El toolchain se reconstruye primero y se instala **antes** de tocar nada
  más. Con `cc`/`gcc` apuntando a `clang` (ver `core/llvm/build`), un fallo
  de medio build dejaría el sistema sin compilador. Por eso existe el backup
  del llvm instalado antes de la primera reconstrucción.
- Reconstruir con un compilador distinto **cambia los parches**: algunos no
  aplican contra el código nuevo. El filtro es `kiss-patch-audit`, que ya
  vive en el repo.

## Orden

El orden lo marca la dependencia entre recetas, no el tamaño:

| tanda | qué | nota |
| --- | --- | --- |
| 0 | `core/llvm` | el toolchain. Con `bolt`, PGO y codigo nativo |
| 1 | `core/*` (base) | `musl`, `bash`, `coreutils`, `sed`, `grep`, `tar`, `gzip`… sin esto no se puede casi nada |
| 2 | toolchain de apoyo | `gcc`/`cproc`, `binutils`, `pkgconf`, `cmake`, `ninja`, `meson`, `python` |
| 3 | bibliotecas de sistema | `zlib`, `openssl`, `libxml2`, `libffi`, `readline`, `ncurses`… |
| 4 | X y drivers | `libdrm`, `mesa`, `xorg-server`, `xorg-*`, `fontconfig`, `freetype` |
| 5 | stack gráfico | `gtk+3`, `cairo`, `pango`, `gdk-pixbuf`, `libdrm` |
| 6 | navegador y escritorio | `firefox`, `webkitgtk`, `dwm`, `picom` |
| 7 | resto | `extra/*`, `python/*`, `test/*` |

Las tandas 1-3 son las baratas y las que desbloquean todo lo demás. La 4 es la
del kernel/driver: si `mesa` o `xorg-server` cambian de versión, el nouveau
puede necesitar los parches de `docs/nouveau-misaligned-reg.md` rehechos.

## Procedimiento por receta

1. **Auditar los parches antes de compilar**:
   ```sh
   kiss-patch-audit core/<paquete>
   ```
   Los códigos `MISSING-PATCH`, `DEAD-PATCH` y `ORDER-DRIFT` avisan de lo que
   va a fallar. Un parche que no aplica se corrige o se retira (con su
   `checksum` regenerado por `kiss c`).
2. **Elegir la clase** del paquete (ver `docs/build-optimization.md`) y exportar
   su perfil antes de compilar:
   ```sh
   eval "$(tools/build-class.sh <clase> env)"
   doas env KISS_PATH="$KISS_PATH" KISS_PID=stable \
       MAKEFLAGS="$MAKEFLAGS" CFLAGS="$CFLAGS" CXXFLAGS="$CXXFLAGS" LDFLAGS="$LDFLAGS" \
       CCACHE_DIR="$HOME/.cache/ccache" TMPDIR=/var/tmp/kiss-scratch \
       kiss b <paquete>
   ```
3. **Verificar**: `kiss l | grep <paquete>` con la versión nueva, y una prueba
   de humo del binario (`<paquete> --version`).
4. **Un paquete por vez** en las tandas pesadas. El `KISS_PID=stable` implica
   un único directorio de build: dos builds simultáneos se pisan.

## Cuando algo falla

- **Falla un parche**: `kiss-patch-audit` lo marca; se rebasea contra el
  código nuevo o se retira el parche.
- **Falla la compilación por RAM**: bajar la clase del paquete, o
  `LLVM_JOBS`/jobs del enlace. El `zram` (10 GB) y `earlyoom` evitan que la
  máquina se cuelgue, pero no que el build acabe.
- **Falla el enlazado de un binario grande**: es el pico de RAM. Bajar los
  hilos del enlazador (`-Wl,--threads=`) y dejar el enlace como un solo
  trabajo.

## Qué mejora de verdad

- Codigo nativo para la CPU (`-march=native`): AVX2 en este Haswell, en
  lugar de la baseline genérica de x86-64.
- `lld` con el perfil y el reordenado de BOLT: mejor layout de código en el
  propio toolchain.
- PGO por paquete donde aporte (ffmpeg, y lo que se quiera medir con un
  perfil real): el resto de paquetes se benefician del toolchain, no del
  perfil.
