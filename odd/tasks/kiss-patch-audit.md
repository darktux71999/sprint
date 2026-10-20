# kiss-patch-audit — auditoría determinista de la capa de parches

Objetivo: entregar la capa read-only que hoy falta en la distro: un inventario determinista de la capa de parches (`kiss-patch-audit`) y la captura estructurada del fallo de parche (`kiss-patch-fail`), para desbloquear el motor de corrección de parches (P3) y el de updates (P4).
Rama: `feature/kiss-patch-audit`
Entrega: 2 work-unit commits en la rama de feature. Push, PR y merge son decisiones del usuario.
Test runner: `sh test/kiss-patch-audit/run` y `sh test/kiss-patch-fail/run` (herméticos, sin red, sin tocar el sistema).

## Specs

S1. Objetivo declarado por el usuario: "necesito estructurar una forma automática con agentes o de optimizar mi uso para generar updates y correcciones de parches para mi sistema linux es de auditoría propia claro he tomado muchos componentes prestados pero creo que actualmente no hay nada similar"

S2. Sistema objetivo confirmado por el usuario: "y uso /usr/bin/kiss". El repo de recetas es `~/proyectos/sprint` y `KISS_PATH` apunta a sus directorios de categoría (`core`, `extra`, `xorg`, `test`, `python`).

S3. Alcance aceptado por el usuario al elegir la opción "Auditoría primero (Recomendado)": "P1 + P2: determinista y read-only. Te da el inventario real (los 15 parches muertos ya están identificados), la señal de fallo que hoy no existe, y desbloquea P3/P4. Riesgo cero para el sistema."

S4. "Riesgo cero para el sistema": las dos herramientas son de solo lectura sobre las recetas y no escriben en el sistema instalado, en la caché de KISS ni en el árbol de recipes.

S5. "Te da el inventario real (los 15 parches muertos ya están identificados)": la auditoría debe detectar, de forma determinista y sin modelo de lenguaje, los parches que nunca se aplican. Verificados a mano en la línea base: 15 parches muertos en 9 recetas — 5 recetas cuyo `build` nunca llama a `patch` (`core/zlib`, `extra/nng`, `extra/opencascade`, `xorg/xlibre-server`, `xorg/libpciaccess`) y 7 recetas con el parche sin listar en `sources` (`core/llvm` 0003 y 0026, `extra/go` arm64-no-gold, `extra/gtk+3` 03-no-atk-extra, `xorg/xf86-video-nouveau` fix-xorg-21.1.diff, `python/python` python3-pyc-hash, `xorg/libpciaccess` lfs64).

S6. "la señal de fallo que hoy no existe": un fallo de parche debe quedar registrado de forma estructurada y legible por un agente. Hoy KISS solo deja un log de texto libre, nunca recoge los `.rej` y borra el directorio de build tras el fallo.

S7. Semántica de KISS que la auditoría debe respetar (verificada en `/usr/bin/kiss`):
- `sources` es `src [dest]`; un `src` local se copia **plano** al directorio de build y `dest` es un subdirectorio dentro de él (`pkg_extract`, `kiss:562-593`).
- Un `src` local inexistente aborta la construcción con `No local file` (`kiss:425-427`). Un `src` remoto (URL o `git+`) lo descarga KISS: no es un fichero local ausente y no se informa como tal.
- El orden real de aplicación es el del **glob** del shell (alfabético), no el de `sources`; `core/unzip` es la única receta que usa `patches/series` como orden autoritativo.
- `run_hook build-fail` recibe `(hook, paquete, directorio de build)` y se ejecuta **antes** de `pkg_clean`, que borra el directorio de build (`kiss:1108-1127`, `kiss:1865-1873`).

S8. Formato de salida: texto legible por defecto y `--json` para consumo por agente, con los mismos códigos de verificación estables.

S9. Códigos de verificación de la auditoría: `DEAD-PATCH` (fichero en `patches/` que `sources` no lista), `DEAD-COPIED` (parche listado en `sources` que el `build` nunca aplica), `DEAD-STACK` (receta con parches cuyo `build` nunca aplica ninguno), `MISSING-PATCH` (parche listado en `sources` que no existe), `ORDER-DRIFT` (el orden de `sources` no es el de aplicación), `DOUBLE-APPLY` (parche aplicado explícitamente y también por glob), `SERIES-DRIFT` (`patches/series` y los parches copiados no coinciden), `STALE-PATCH` (el nombre del parche cita una versión que la receta no construye).

S10. Severidad: `DEAD-PATCH`, `DEAD-COPIED`, `DEAD-STACK` y `MISSING-PATCH` son errores (rompen o anulan la corrección que el parche debía aplicar). `ORDER-DRIFT`, `DOUBLE-APPLY`, `SERIES-DRIFT` y `STALE-PATCH` son avisos (requieren juicio). El estado de salida es 1 si hay errores, o también con avisos si se pasa `--strict`.

S11. Convenciones del repo a replicar: receta en `extra/<nombre>/` con `version` (dos campos), `sources`, `depends`, `build` ejecutable y `files/<comando>`; script POSIX sh; test hermético en `test/<nombre>/run`; documentación en `docs/<nombre>.md`. Precedente: `extra/kiss-integrity` + `test/kiss-integrity/run` + `docs/kiss-integrity.md`.

## Tasks

- T1 · P1 `kiss-patch-audit` · S3-S5, S7-S10, S11 · inline · commit `a49120f` · receta `extra/kiss-patch-audit`, script `files/kiss-patch-audit`, doc `docs/kiss-patch-audit.md`, test `test/kiss-patch-audit/run` · revisión nativa `review-83f0d309b49a1217` aprobada y reconocida
- T2 · P2 `kiss-patch-fail` · S3, S4, S6, S7, S11 · inline · commit `d6a23e0` · receta `extra/kiss-patch-fail`, hook `files/kiss-patch-fail`, doc `docs/kiss-patch-fail.md`, test `test/kiss-patch-fail/run`
- T3 · Cierre · S5 · inline · la auditoría sobre `~/proyectos/sprint` encuentra 25 errores y 5 avisos: 21 parches muertos en 14 recetas, más avisos de orden y de doble aplicación

## Log

L1. Petición original del usuario: "necesito estructurar una forma automática con agentes o de optimizar mi uso para generar updates y correcciones de parches para mi sistema linux es de auditoría propia claro he tomado muchos componentes prestados pero creo que actualmente no hay nada similar"

L2. El usuario confirmó el sistema: "y uso /usr/bin/kiss"

L3. Auditoría manual previa (línea base) sobre `~/proyectos/sprint`: 350 recetas, 52 con `patches/`, 193 parches, 1 sola receta con `patches/series` (`core/unzip`). 15 parches muertos en 9 recetas. Falso positivo descartado: `python/python-installer/sources` usa `patches/default-bytecode-levels.patch build`, donde `build` es el destino y no un parche roto.

L4. Corrección de un análisis previo: el log de un build fallido **sí** se conserva (la línea `rm -f "$log_dir/..."` solo se alcanza en builds exitosos). Lo que falta es la estructura y los `.rej`.

L5. Decisión del usuario sobre el alcance: "Auditoría primero (Recomendado)".

L6. Engram: el proyecto `sprint` quedó resoluble (`.engram/config.json`), lo que desbloquea la memoria del proyecto. Hallazgos guardados en `sprint/patch-audit-findings` y `sprint/agent-patch-pipeline`.

L7. Corrección acotada de la revisión nativa (hallazgo R3-1, lente reliability, severidad CRITICAL, disposición `introduced`): la auditoría trataba como parche local toda entrada de `sources` terminada en `.patch` o `.diff`, incluidas las URL remotas. Para una URL remota KISS descarga el fichero, de modo que el aviso `MISSING-PATCH` y su afirmación de que la construcción aborta con `No local file` eran falsos. Corrección: `parse_sources` distingue las fuentes remotas (`://`, rutas absolutas y `git+`) y el bucle `MISSING-PATCH` solo comprueba las rutas locales relativas. Se actualiza S7, la documentación y se añade un caso de regresión al test (`core/remote` con un parche remoto no produce hallazgos).

L8. Revisión nativa de T1 (lineage `review-83f0d309b49a1217`, lentes `review-readability` y `review-reliability`): aprobada y reconocida (`gentle-ai.review-acknowledged/v1`, autoridad quemada). Quedan 17 avisos no bloqueantes de mantenibilidad, entre ellos que el test no fija `DEAD-COPIED`, `DOUBLE-APPLY` ni `UNKNOWN-MECHANISM`, que el JSON no se valida como documento, y que la documentación no declara el código de salida 2 para los errores de uso. Quedan como trabajo posterior, no como defectos de este cambio.

L9. T2: `kiss-patch-fail` captura el fallo de parche en JSON y copia los `.rej`. El directorio de caché se deriva del directorio de build (`$cache/proc/$KISS_PID/build/$paquete`), que es el único punto donde el fallo es legible: `run_hook build-fail` se ejecuta antes de `pkg_clean`.
