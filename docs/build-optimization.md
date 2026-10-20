# Optimización de compilación y control de RAM

Perfil por clase de paquete, estimación de hilos por build y estrategias para
compilar sin agotar la RAM en esta máquina (8 núcleos/16 hilos, 7,7 GB de RAM
+ 10 GB de zram). La herramienta que implementa el modelo es
`tools/build-class.sh`, con su prueba hermética en `test/build-class/run`.

## Presupuesto de RAM

| Recurso | Valor |
| --- | --- |
| RAM física | 7,7 GB |
| zram (swap comprimido) | 6 GB zstd + 4 GB lz4 |
| Reserva para el sistema | 768 MiB |
| Presupuesto de build | ~6,2 GB efectivos (los picos los absorbe zram) |

Un trabajo de compilación C++ de paquete pesado (clang/g++ sobre firefox,
webkitgtk, llvm, mesa) puede llegar a 1,5-2,5 GB. Con 6,2 GB efectivos, la
cota segura son 3-4 trabajos pesados simultáneos; de ahí `MAKEFLAGS=-j14`
global rompe el sistema en cuanto toca un paquete de esta clase.

## Clases y flags

| Clase | Paquetes tipo | RAM/trabajo | Jobs | CFLAGS |
| --- | --- | --- | --- | --- |
| `light` | librerías C pequeñas, herramientas | ~400 MB | hasta `nproc` | `-O3 -pipe -march=native -mtune=native` |
| `medium` | chawan, go, python | ~900 MB | hasta 8 | `-O2 -pipe -march=native -mtune=native` |
| `heavy` | firefox, webkitgtk, llvm, mesa, kicad | ~1,8 GB | hasta 6 | `-O2 -pipe -march=native -mtune=native` |
| `link` | enlaces grandes (libLLVM.so, libxul) | — | 1 | — |

Los jobs reales salen de la RAM disponible del momento:

```sh
jobs=$(( (MemAvailable - 768MiB) / RAM_por_trabajo ))   # acotado a [1, tope]
```

Uso desde el shell o desde un script de build:

```sh
JOBS=$(tools/build-class.sh heavy jobs)      # 3 con la máquina al 6,7 GB libres
eval "$(tools/build-class.sh heavy env)"     # exporta CFLAGS/CXXFLAGS/LDFLAGS/MAKEFLAGS
```

Cada receta que se reconstruya fija sus flags y sus trabajos siguiendo esta
tabla (el precedente del repo es `core/luajit/build`, que extiende `CFLAGS`).

## Enlaces y LTO

- Enlazador: `lld` con `--threads=N` limitado (máximo 4) y `-Wl,-O2`.
  Un solo enlace grande a la vez (`link`); el pico de RAM del enlace es el
  que tumba la máquina, no la compilación.
- ThinLTO (`-flto=thin` + `-Wl,--thinlto-jobs=N`) solo donde compensa:
  binarios grandes con mucho cruce de módulos (firefox vía
  `--enable-lto=thin`). No compensa en paquetes pequeños ni en los que ya
  tienen su propia cadena (go, python).
- PGO y BOLT se reservan para LLVM (rebuild instrumentado + entrenamiento +
  rebuild + optimización post-link); ver la tarea T7 del documento de feature.

## Estrategias anti-cuelgue

1. **Nunca dos paquetes `heavy` a la vez.** Las tandas se serializan; dentro
   de una tanda, los ligeros sí pueden solaparse.
2. **`TMPDIR` en disco, no en `/tmp`.** `/tmp` es un tmpfs de solo 1 GB:
   firefox y rust escriben más de eso en temporales y fallan con ENOSPC (o
   llenan la RAM vía tmpfs). Para builds pesados:
   `TMPDIR=/var/tmp/kiss-scratch` (NVMe).
3. **ccache: `CCACHE_TEMPDIR` en el NVMe**, nunca en `/tmp` por la misma
   razón. Un fallo de ccache por ENOSPC interrumpe la compilación a mitad.
4. **earlyoom bajo runit** (`/etc/sv/earlyoom/run`): su `--prefer` ya apunta a
   compiladores (`cc1plus|clang|rustc|make|ninja`) y su `--avoid` protege
   `init|Xorg|firefox|mksh`. Debe estar enlazado en `/var/service/earlyoom`
   para que `runsvdir` lo supervise; sin ese enlace, la máquina se cuelga en
   vez de matar el proceso hambriento.
5. **zram y swappiness=100** ya configurados: los picos se comprimen en RAM
   antes de morir. No desactivarlos.

## Caché NVMe: la corrupción es un fallo seguro

La caché de fuentes de KISS (`~/.cache/kiss`) y la de ccache viven en el
NVMe. Si el disco falla o devuelve datos corruptos:

- Las fuentes de KISS están verificadas por checksum (`kiss c`/`kiss v`):
  la corrupción se detecta antes de compilar, nunca instala basura.
- ccache degrada a *miss* o falla la operación puntual: el build sigue o se
  reintenta limpio, sin corromper el resultado (el compilador vuelve a
  generar el objeto).
- Si se observan errores de E/S del NVMe, vaciar `~/.cache/ccache` y
  redescargar fuentes es barato; no lo es depurar un toolchain corrompido.

Comprobaciones útiles: `ccache -s` (tasa de aciertos, tamaño), `df -h
~/.cache` (espacio), y los logs del kernel en busca de errores `nvme`.
