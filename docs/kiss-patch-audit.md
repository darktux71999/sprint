# Auditoría de la capa de parches para KISS

KISS distribuye utilidades útiles, pero ninguna audita la capa de parches de las recetas. `kiss-integrity` comprueba el árbol instalado; `kiss-outdated` consulta versiones externas. Ninguna de las dos sabe si los parches de una receta se aplican de verdad.

Eso importa porque en KISS la existencia de un parche y su aplicación son dos cosas distintas. `sources` es una lista de `src [dest]`; KISS copia al directorio de build solo lo que la lista menciona, en plano, y un `src` local inexistente aborta la construcción con `No local file`. Un parche presente en `patches/` que nadie lista en `sources` no llega nunca al árbol de build: no es un parche, es un fichero. Y un parche listado que el `build` no llega a aplicar se copia, ocupa espacio y no hace nada.

`kiss-patch-audit` inventaría esa capa de forma determinista, sin modelo de lenguaje y sin tocar nada:

```sh
kiss-patch-audit
kiss-patch-audit --json
kiss-patch-audit --strict
kiss-patch-audit --quiet
kiss-patch-audit ~/proyectos/sprint/core
```

Sin argumentos audita los directorios de `KISS_PATH`; cada argumento puede ser un repositorio (un directorio con `core/`, `extra/`, ...) o un directorio de categoría. La auditoría es de solo lectura: no escribe en las recetas, ni en la caché de KISS, ni en el sistema instalado. Devuelve código 1 si encuentra errores, y con `--strict` también si solo hay avisos.

## Comprobaciones

- `DEAD-PATCH`: hay un fichero en `patches/` que `sources` no lista. Nunca se copia y nunca se aplica.
- `DEAD-COPIED`: el parche está listado en `sources` pero el `build` nunca lo aplica.
- `DEAD-STACK`: la receta tiene parches y su `build` no menciona `patch` en absoluto. Todos sus parches están muertos.
- `MISSING-PATCH`: `sources` lista un parche local que no existe en disco. `kiss build` aborta con `No local file`. Un parche listado como URL remota no se informa: KISS lo descarga, así que no es un fichero local ausente.
- `UNKNOWN-MECHANISM`: el `build` aplica parches de una forma que la auditoría no modela. El conjunto aplicado queda desconocido, así que no se afirma que ningún parche esté muerto.
- `ORDER-DRIFT`: el orden de `sources` no es el orden real de aplicación. KISS no aplica los parches en el orden en que aparecen en `sources`, sino en el orden del glob del shell, que es alfabético. Cuando dos parches tocan el mismo fichero, el orden de `sources` es una pista falsa.
- `DOUBLE-APPLY`: un parche se aplica de forma explícita y además por un glob. Suele ser una rama `if/else` excluyente, así que es un aviso que pide criterio, no un error.
- `SERIES-DRIFT`: `patches/series` y los parches copiados no coinciden. `core/unzip` es hoy la única receta con serie, y su serie es la que manda sobre el glob.
- `STALE-PATCH`: el nombre del parche cita una versión que la receta no construye.

Los cuatro primeros son errores: anulan la corrección que el parche debía aplicar. Los demás son avisos y requieren criterio humano.

## De qué depende

La auditoría modela el comportamiento real de KISS, no una suposición. En `pkg_extract` (`/usr/bin/kiss`) un fichero local se copia plano al directorio de build y `dest` es un subdirectorio dentro de él; el orden de aplicación es el del glob, salvo que la receta use `patches/series`. Cuando el `build` aplica los parches con una forma que el análisis no reconoce, la auditoría lo dice con `UNKNOWN-MECHANISM` en vez de acusar a un parche que no está muerto.

## Estado actual del repositorio

Sobre las 350 recetas de `~/proyectos/sprint` (54 con parches) la auditoría encuentra 25 errores y 6 avisos. Los errores son 21 parches muertos en 14 recetas:

- Diez recetas con el parche sin listar en `sources`: `core/llvm` (`0003` y `0026-32-bit-musl-sanitizer-fixes`), `core/zlib`, `extra/go` (`arm64-no-gold`), `extra/gtk+3` (`03-no-atk-extra`), `extra/nng`, `extra/opencascade` (tres parches), `python/python` (`python3-pyc-hash`), `xorg/libpciaccess` (`lfs64`), `xorg/xf86-video-nouveau` (`fix-xorg-21.1.diff`) y `xorg/xlibre-server` (tres parches, incluido `rootless_modesetting`).
- Cuatro recetas cuyo `build` nunca aplica lo que `sources` copia: `core/kiss` (`files/no-perl.patch`), `core/vis` (`wl-clipboard.patch`), `extra/ninja` (`bootstrap.patch`) y `extra/ffmpeg` (tres parches).

Los avisos señalan que el orden de `sources` no es el de aplicación en `extra/firefox`, `extra/go`, `extra/webkitgtk`, `xorg/mesa` y `xorg/xf86-video-nouveau`, y que `extra/gtk+3` aplica `01-no-fribidi.patch` de forma explícita y también por glob.

Estos son hallazgos de la auditoría, no un plan de corrección: repararlos exige tocar `sources`, `build` y `checksums` de recetas viva, y cada parche corregido obliga a regenerar el checksum antes de reconstruir.

Las pruebas reproducibles del script son `sh test/kiss-patch-audit/run`.
