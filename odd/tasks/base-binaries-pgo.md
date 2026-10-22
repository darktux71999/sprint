# Optimización de los binarios base con ThinLTO y PGO

Objetivo: aplicar el mismo método que en LLVM (ThinLTO donde el código cruza
unidades de traducción, PGO con carga representativa) a los binarios base del
sistema, empezando por los de mayor tráfico y acabando por los más críticos.
Rama: la actual del repo. Entrega: commits de work unit, sin push (decisión del
usuario). Test runner: pruebas de diferencia propias (`test/base-bins/`).

## Specs

S1. Paquetes objetivo: `make`, `git`, `mksh` y `busybox`. Se excluyen, con
motivo: `musl` (la libc: un fallo deja el sistema sin arranque, y un perfil
incompleto en una libc puede salir más lenta que sin PGO), `bash` (el shell
del usuario es mksh; impacto menor), `openssl`/`libcrypto` (su propio PGO
exige la suite de tests completa, desproporcionado aquí) y `curl` (impacto
menor que los anteriores).

S2. ThinLTO en los que cruzan código entre unidades de traducción: `busybox`
(un binario enorme de muchos .c), `make` y `git`. PGO en los cuatro: todos
ejercitan rutas calientes con una carga representativa y barata de montar.

S3. El PGO es opt-in por variable de entorno (`BASE_PGO=1`), como ya se hace
con `LLVM_PGO`, `FIREFOX_PGO` y `FFMPEG_PGO`. Sin la variable, la receta
compila como hasta ahora.

S4. El perfil de PGO vive FUERA del árbol de build (lección de la fase 2 de
LLVM: KISS borra el árbol al empezar y al terminar, y un reinicio lo perdía).

S5. Antes de instalar, el binario recién construido se prueba en el árbol de
staging de KISS. Para `busybox` (que es `/sbin/init`) y `mksh` (el shell de
login) se conserva además una copia del binario actual con una vía de rescate
documentada.

S6. Sin BOLT en estos paquetes: son procesos de vida corta (shell, coreutils,
git) y no calientan el código durante minutos, que es la condición para que
reordenar el código compense.

S7. El presupuesto de RAM es el de `tools/build-class.sh`; la clase de cada
paquete sale de su tamaño medido, no del tamaño del paquete.

S8. Prueba de diferencia: la salida (stdout, stderr y código de salida) de
los binarios nuevos debe coincidir con la de los actuales para la misma
entrada. Un cambio de comportamiento no pedido es un fallo.

## Tasks

- T1 (S2, S3, S4, S7) `make`: ThinLTO + PGO con carga de un Makefile real.
  Ruta: inline. Riesgo: ninguno (no es critico para arrancar ni para entrar).
  **Hecho**: recipe con `AR/RANLIB/NM=llvm-*`, `-flto=thin`, PGO opt-in con
  `BASE_PGO=1`, perfil en `$HOME/.cache/pgo-base/make/`, carga con un
  proyecto sintetico de 12 fuentes. Version 4.4.1 2. Verificado: la salida
  (stdout, stderr y codigo de salida) es IDENTICA a la de la referencia
  compilada con la receta original, y el parse de 50.000 reglas baja de
  775 ms a 725 ms (~5-6%). El perfil cubre las rutas calientes del parser y
  del grafo (`update_file` con 160 contadores, `find_directory` con 1.764).
- T2 (S2, S3, S4) `git`: ThinLTO + PGO con carga de operaciones reales de git.
  Ruta: inline. Riesgo: ninguno.
- T3 (S2, S3, S5) `mksh`: PGO con carga de construcciones de shell. Ruta:
  inline. Riesgo: item 3 (el shell de login) -> copia de respaldo.
- T4 (S2, S3, S5, S8) `busybox`: ThinLTO + PGO con carga de applets. Ruta:
  inline. Riesgo: item 3 (`/sbin/init` es busybox) -> copia de respaldo y
  prueba exhaustiva del staged.
- T5 (S8) Test de diferencia para los cuatro binarios.
- T6 (S1, S2, S6) Actualizar `docs/build-optimization.md` con la tabla de
  candidatos y el estado.
- T7 Cierre: resumen y estado final.

## Log

L1. Petición del usuario (2026-10-21): "podemos optimizar parte de los binarios
base, segun sea conveniente".
L2. Contexto heredado: `llvm 22.1.8-6` ya instalado con PGO (perfil de
76,8 MB y 701.043 funciones, con el backend X86 cubierto). `firefox` y `ffmpeg`
tienen recetas de PGO/LTO listas pero sin construir.
L3. Sonda de viabilidad (2026-10-21): `llvm-ar`, `llvm-ranlib`, `ld.lld`,
`llvm-profdata` y `libclang_rt.profile.a` presentes; enlace estatico con
`-flto=thin` correcto (223 KB); PGO de una pasada correcto (el `.profraw` se
llama `default_<hash>_0.profraw`, no el nombre del binario).
L4. Riesgos de sistema detectados: `/sbin/init` y `/bin/init` apuntan a
`busybox` (o sea, busybox ES el init) y el shell de login del usuario es
`/bin/mksh`. Por eso el orden es de menor a mayor riesgo y los dos criticos
llevan copia de respaldo y prueba previa.
