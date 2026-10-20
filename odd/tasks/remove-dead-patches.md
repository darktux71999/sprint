# Retirada de los parches muertos

Objetivo: retirar de las recetas los parches que nunca se aplican, sin tocar nada más.
Rama: `feature/remove-dead-patches` (desde `feature/kiss-patch-audit`).
Entrega: un commit por receta, 15 en total. Push, PR y merge son decisiones del usuario.
Test runner: `sh test/kiss-patch-audit/run` (la auditoría es la prueba de aceptación) y `sh test/kiss-patch-fail/run`.

## Specs

S1. Petición del usuario: "solo retira los parches muertos y haz los commits correspondientes". "Solo" acota el alcance: ninguna otra corrección, ningún aviso, ningún cambio de orden.

S2. Un parche está muerto si nunca llega a aplicarse, y eso tiene dos causas distintas en KISS:
- no está listado en `sources`, de modo que KISS no lo copia al directorio de build (`pkg_extract` copia solo lo que la lista menciona);
- está listado en `sources` y se copia, pero el `build` de la receta nunca aplica ningún parche.

S3. La retirada de un parche copiado exige quitar también su línea de `sources`: si la línea se queda, `kiss build` aborta con `No local file` (`kiss:425-427`).

S4. Cada parche retirado va en su propio commit, para que cada receta se pueda revertir por separado sin arrastrar a las demás.

S5. Los `checksums` guardan un hash por entrada hasheable de `sources`, en el mismo orden (`pkg_checksum_gen`). Las entradas `git+` no se hashean y las que son directorios tampoco. Retirar una entrada de `sources` obliga a retirar su línea de `checksums`.

S6. Criterio de aceptación: la auditoría del repo no informa de ningún parche muerto ni de ningún `MISSING-PATCH`, y toda receta conserva el mismo número de fuentes hasheables que de líneas de `checksums`.

## Tasks

- T1 · 15 recetas · S2-S6 · inline · un commit por receta: `core/vis`, `core/llvm`, `core/zlib`, `extra/go`, `extra/gtk+3`, `extra/nng`, `extra/opencascade`, `extra/ninja`, `xorg/libpciaccess`, `xorg/xf86-video-nouveau`, `xorg/xlibre-server`, `python/python`, `extra/ffmpeg`, `extra/ffmpeg/ffmpeg`, `core/kiss`

## Log

L1. Entrada: la auditoría de `kiss-patch-audit` informa de 25 errores, que son 24 ficheros de parche muertos repartidos en 15 directorios de receta (13 recetas más la copia anidada de ffmpeg).

L2. `extra/ffmpeg/ffmpeg` es la copia vieja de la receta de ffmpeg (8.1.2) que dejó una reestructuración; KISS solo ve la receta un nivel arriba (`extra/ffmpeg`, 8.1.3). Sus tres parches también están muertos y se retiran también.

L3. `core/kiss` tiene el parche en `files/` en lugar de `patches/`, y su `build` solo instala ficheros: nunca aplica un parche. Se retiran el fichero, su línea de `sources` y su línea de `checksums`.

L4. Verificación: la auditoría del repo pasa de 25 errores a 0, con 5 avisos que son los de orden y doble aplicación, fuera del alcance de S1. Las 15 recetas tocadas conservan la correspondencia entre fuentes hasheables y líneas de `checksums`, comprobada sobre las 351 recetas del repo.

L5. Preexistente, no tocado: la primera línea de `checksums` de `core/kiss` no corresponde al tarball que codeberg sirve hoy (`87c25adc…` frente a `52921639…` con dos descargas fresh, que dan el mismo valor, así que el archivo es reproducible). El valor obsoleto ya estaba en la línea base y `kiss build kiss` fallaba la verificación de checksums antes de este trabajo. Se deja como está porque S1 limita el alcance a la retirada de parches.

L6. Preexistente, no tocado: `extra/chawan` y `extra/rsync` son recetas solo-`git+` que conservan una línea de `checksums` sin entrada que la justifique.
