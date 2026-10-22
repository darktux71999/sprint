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
  **Hecho y REVERTIDO**: con la carga de 200 ficheros y 200 modificaciones el
  perfil de git queda bien (20.640 funciones), pero la medicion dio una
  **regresion consistente del 5-10%** (`log -p`: 148-150 ms de la referencia
  contra 157-167 ms; `status` con 3.000 ficheros: 40 ms contra 44 ms). Para
  aislar la causa se construyo una variante **solo con ThinLTO, sin PGO**
  (159-164 ms): la regresion viene del **ThinLTO**, no del PGO, que ademas no
  anade nada por encima. Se revierte la receta de git a la original y se
  reconstruye con ella. LECCION: no basta con que el perfil sea
  representativo, hay que medir; el criterio del doc ya lo decia ("sin carga
  representativa el perfil no vale, y puede ser peor que no hacerlo"), y aqui
  el caso fuerte es el inverso: con carga representativa y LTO, tambien.
  (Durante el camino se encontraron dos trampas: el `configure` de git con
  LTO tarda 9 minutos frente a 1, porque cada prueba compila y enlaza con
  ThinLTO; y el `make clean` de git borra el directorio `oss-fuzz/`, cuya
  regla de enlace no lo recrea, con lo que la segunda pasada del PGO se
  caia.)
- T3 (S2, S3, S5) `mksh`: PGO con carga de construcciones de shell. Ruta:
  inline. Riesgo: item 3 (el shell de login) -> copia de respaldo.
  **Hecho**: recipe con ThinLTO + PGO, perfil en `$HOME/.cache/pgo-base/mksh/`
  (1.560 funciones). Build.sh no tiene target `clean` (se quitan los objetos a
  mano, o si no la segunda pasada no recompila con el perfil). Compilado con
  `build_install=0` y probado contra el original antes de instalar. Version
  59c 2. Medido: el guion de shell baja de 209 ms a 185 ms (~11%).
- T4 (S2, S3, S5, S8) `busybox`: ThinLTO + PGO con carga de applets. Ruta:
  inline. Riesgo: item 3 (`/sbin/init` es busybox) -> copia de respaldo y
  prueba exhaustiva del staged.
  **Hecho**: recipe con ThinLTO + PGO para la variante normal; la variante
  `suid` va sin PGO (son los applets que necesitan suid, que se usan poco).
  Perfil de 6.687 funciones. Compilado con `build_install=0`, probado
  contra el original (297 applets, salida identica salvo la fecha del
  banner) y instalado despues. Version 1.38.0 3. Medido: `sed` sobre 20.000
  lineas baja de 1504 ms a 1270 ms (~15%) y `grep` de 1019 ms a 952 ms
  (~6%). Respaldo en `/var/cache/sprint-backup/` con `init` de rescate.
  Nota: el paquete nuevo trae un `mdev.conf` sin la regla local de USB
  Android/Unisoc (que si usa `/opt/mdev/usb-android.sh`): se restauro el
  fichero con la regla.
- T5 (S8) Test de diferencia para los cuatro binarios.
  **Hecho**: `test/base-bins/run` compara los cuatro binarios nuevos contra
  los originales (stdout, stderr y codigo de salida) y falla si cambia una
  sola linea. Las referencias (12 MB de binarios) no se versionan: viven en
  `/var/cache/sprint-backup/` junto con el `init` de rescate. Detalle: hay
  que normalizar el nombre del programa en los errores de make y la fecha
  del banner de busybox (que cambia en cualquier reconstruccion).
- T6 (S1, S2, S6) Actualizar `docs/build-optimization.md` con la tabla de
  candidatos y el estado.
  **Hecho**: filas de `busybox`, `mksh` y `make` con las mediciones, `git`
  con el resultado de la regresion, y una seccion con las cuatro cosas que
  hacen falta para aplicar esto a un paquete: `AR=llvm-ar`, el `configure`
  sin LTO/PGO, la carga representativa y la CORE del init y el shell.
- T7 Cierre: resumen y estado final.
  **Hecho**: ver L5.

## Log

L1. Petición del usuario (2026-10-21): "podemos optimizar parte de los binarios
base, segun sea conveniente".L2. Contexto heredado: `llvm 22.1.8-6` ya instalado con PGO (perfil de
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
L5. Cierre (2026-10-21). Resultado: **tres de cuatro Improved, uno
revertido**. `make 4.4.1 2` (ThinLTO+PGO, ~5%), `mksh 59c 2` (ThinLTO+PGO,
~11%), `busybox 1.38.0 3` (ThinLTO+PGO, ~15% en sed y ~6% en grep), y `git`
revertido a la receta original (`2.55.0 3`, reconstruido con el toolchain
actual) porque el ThinLTO resulto ser una regresion del 5-10%. Los cuatro
pasan el test de diferencia. En el camino: `build_install=0` (KISS construye
y crea el tarball sin instalar) permitio probar cada binario antes de
tocar el sistema; el respaldo con `init` de rescate esta en
`/var/cache/sprint-backup/`. La especificacion S1 (que excluia `musl`) se
mantiene: una libc con perfil incompleto puede salir mas lenta, y un fallo
de musl deja el sistema sin arranque.
L6. Ampliacion: el usuario pregunta por el resto de la pila (vis, luajit,
zutty, picom, freetype, harfbuzz, cairo) y pide probar vis con un fichero
muy grande. `kiss l` da 324 paquetes instalados; la pila grafica esta casi
toda en el repo (`core/vis`, `core/luajit`, `extra/picom`, `extra/cairo`,
`extra/fontconfig`, `extra/freetype-harfbuzz`, `xorg/zutty`,
`xorg/xlibre-server`).
  **vis: REVERTIDO** (la receta vuelve a la original y la version a 0.9 1; el
  binario optimizado nunca se instalo, asi que el editor del usuario esta
  intacto). Se construyo con ThinLTO+PGO, con la carga en un pty (python3
  con el modulo pty), y se midio el desplazamiento de 3.000 lineas sobre un
  fichero de 200.000 lineas: la referencia tarda 917-927 ms y las dos
  variantes (ThinLTO+PGO y solo ThinLTO) 1.295-1.315 ms, un **41% mas
  lento**. Se descarto que fuera el `-Wl,-O0` que vis pone en su propio
  enlace (quitarlo no mejora). La primera carga de PGO no includia el
  desplazamiento, que es lo que mas se hace en un editor: con el perfil mal
  orientado el resultado era un 39% mas lento, y anadiendolo seguia igual
  (el culpable es el LTO, pero la carga tampoco era la adecuada).
  Aprendido: (1) la carga de un programa interactivo se conduce en un pty y
  **siempre con timeout y kill**: si el editor se queda en un estado raro y
  no sale, la carga se cuelga y tumba el build; (2) vis es *perezoso* con
  ficheros enormes (mmap: 100 MB de fichero, 6 MB de RSS, primera pantalla en
  14 ms) asi que no se pega con un fichero grande; (3) el patron que se esta
  formando: ThinLTO gana en los paquetes PEQUEÑOS (make, mksh, busybox) y
  pierde en los que tienen cientos de TUs (git 7%, vis 41%).
