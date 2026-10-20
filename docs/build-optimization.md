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
| `light` | librerías C pequeñas, herramientas | ~256 MiB | hasta `nproc` | `-O3 -pipe -march=native -mtune=native` |
| `medium` | chawan, python | ~512 MiB | hasta 8 | `-O2 -pipe -march=native -mtune=native` |
| `heavy` | firefox, webkitgtk, llvm, mesa, kicad, go | ~768 MiB | hasta 4 | `-O2 -pipe -march=native -mtune=native` |
| `link` | enlaces grandes (libLLVM.so, libxul) | — | 1 | — |

Los valores de RAM por trabajo **están medidos**, no estimados: se compilaron
ficheros reales de esta máquina midiendo su pico de RSS (`VmHWM`):

| TU | pico |
| --- | --- |
| `llvm/lib/Transforms/InstCombine/InstructionCombining.cpp` | 384 MB |
| `llvm/lib/CodeGen/MachineScheduler.cpp` | 382 MB |
| `llvm/lib/Transforms/Vectorize/VectorCombine.cpp` | 360 MB |
| `llvm/lib/CodeGen/MachineCombiner.cpp` | 273 MB |
| `llvm/lib/Analysis/AliasAnalysis.cpp` | 230 MB |
| `go/src/runtime/cgo/gcc_fatalf.c` | 74 MB |
| `go/src/runtime/cgo/gcc_traceback.c` | 68 MB |

De ahí salen los números con factor de seguridad (×2 para `heavy`, ×3 para
`light`). El tope de 4 en `heavy` no es arbitrario: el enlace de un binario
grande pide del orden de 3 GB y tiene que caber junto a los trabajos que
sigan compilando; por eso la clase pesada nunca baja de 4 trabajos en esta
máquina aunque la RAM disponible fluctúe.

Los jobs reales salen de la RAM disponible del momento: se toma `MemAvailable`
de `/proc/meminfo`, se le resta la reserva de 768 MiB que el propio script
define como `reserve_kb`, y el resultado se divide entre la RAM estimada por
trabajo de la clase, con topes por clase y un mínimo de 1.

Uso desde el shell o desde un script de build:

```sh
JOBS=$(tools/build-class.sh heavy jobs)      # 3 con la máquina al 6,7 GB libres
eval "$(tools/build-class.sh heavy env)"     # exporta CFLAGS/CXXFLAGS/LDFLAGS/MAKEFLAGS
```

Cada receta que se reconstruya fija sus flags y sus trabajos siguiendo esta
tabla (el precedente del repo es `core/luajit/build`, que extiende `CFLAGS`).

## Uso con kiss

KISS ejecuta el `build` de la receta heredando el entorno del shell (solo
fija `CC`, `CXX`, `AR`, `NM` y `RANLIB` por defecto), de modo que los flags
y los trabajos exportados llegan tal cual al compilador. El flujo es:

```sh
cd ~/proyectos/sprint

# 1. Elegir clase y exportar su perfil
eval "$(tools/build-class.sh heavy env)"     # CFLAGS CXXFLAGS LDFLAGS MAKEFLAGS
kiss b firefox
```

Campos sueltos, por si solo se quiere uno:

```sh
tools/build-class.sh heavy jobs        # -> 3
tools/build-class.sh heavy makeflags   # -> -j3
tools/build-class.sh heavy cflags      # -> -O2 -pipe -march=native -mtune=native
tools/build-class.sh light env         # -> export ... (clase ligera)
```

Clases usadas en este repo: `light` (certs, python-gpep517), `medium`
(chawan), `heavy` (go, firefox, llvm, mesa, webkitgtk, kicad).

### Con root (doas)

`doas` reinicia `HOME`, así que root no hereda ni el `CCACHE_DIR` ni el
`KISS_PID` del usuario: el build iría a `/root/.cache/ccache` y a un
directorio de proceso nuevo, y **ccache no acertaría nunca** (la ruta de los
ficheros forma parte de la clave). Para que el build use la caché:

```sh
eval "$(tools/build-class.sh heavy env)"
doas env KISS_PATH="$KISS_PATH" KISS_PID=stable \
    MAKEFLAGS="$MAKEFLAGS" CFLAGS="$CFLAGS" CXXFLAGS="$CXXFLAGS" LDFLAGS="$LDFLAGS" \
    CCACHE_DIR="$HOME/.cache/ccache" CCACHE_TEMPDIR="$HOME/.cache/ccache/tmp" \
    TMPDIR=/var/tmp/kiss-scratch \
    kiss b firefox
```

`KISS_PID=stable` reutiliza siempre el mismo directorio de build (es lo que
permite que ccache reutilice objetos). A cambio, **no puede haber dos builds
a la vez**: comparten directorio. `TMPDIR` va fuera del tmpfs de 1 GB de
`/tmp` porque rust y firefox escriben ahí temporales de varios GiB.

### Lo que no puede venir del entorno

Lo que el paquete solo puede configurar en su receta (opciones de cmake o de
mozconfig, proyectos extra, PGO) va dentro del `build`:

- `extra/firefox/build`: `ac_add_options --enable-lto=thin`.
- `core/llvm/build`: `bolt` en `LLVM_ENABLE_PROJECTS`, y los jobs se calculan
  ahí mismo desde `/proc/meminfo` (una receta no puede llamar a
  `tools/build-class.sh`: durante el build el directorio actual es el de
  compilación y no se conoce la ruta del repo).
- `extra/ffmpeg/build`: PGO con `FFMPEG_PGO=1`.

## Niveles de optimización: una sola fuente de verdad

CMake concatena los flags en este orden: `CMAKE_C_FLAGS` (del usuario) primero
y después los del build type. **Gana el último `-O`**, así que con
`CMAKE_BUILD_TYPE=Release` la línea real es:

```
C_FLAGS = -O2 -pipe -march=native -mtune=native -O3 -DNDEBUG
```

Es decir: `-O3 -DNDEBUG` (lo que usa upstream para sus releases) y el `-O2`
del entorno es un no-op. La receta de llvm **quita el nivel `-O` de `CFLAGS`**
antes de pasarlo a cmake, para que no haya dos niveles en la línea y la fuente
única sea el build type. El resto (`-pipe -march=native -mtune=native`) sí se
pasa: el compilador tiene que generar código para **esta** CPU, no para la
baseline genérica de x86-64.

### La instrumentación no degrada el software que se compila

- El compilador instrumentado aplica **las mismas optimizaciones** que el
  normal. Lo que se instrumenta es el **programa que se compila**: se le añade
  un runtime que registra qué caminos de código se ejecutan. Eso es lo que
  recoge el perfil.
- La pasada final aplica las mismas optimizaciones **más** las decisiones
  guiadas por el perfil (layout de bloques hot/cold, inlining mejor
  elegido). El software final no queda "desoptimizado" por el hecho de haber
  pasado por un compilador instrumentado.
- El compilador instrumentado sí es más lento en runtime (escribe contadores),
  pero es desechable: solo sirve para entrenar.

### La trampa: las dos pasadas del PGO deben llevar los mismos flags

Si la pasada instrumentada usa un nivel de optimización distinto del de la
pasada final, el perfil **no encaja con el binario**: clang compara por hash de
función, así que avisa de que el perfil está obsoleto y descarta lo que no
casa. Por eso en la receta las dos pasadas comparten exactamente los mismos
flags y solo cambia el flag de perfil.

Lo que **sí** puede ir con flags rápidos es el *build de entrenamiento* (el
que recompila CodeGen con el clang instrumentado): ahí los flags no afectan a
la validez del perfil, solo a cuánto tarda en ejercitar el compilador.

### Los flags de desarrollo en el toolchain son mala operación

Un LLVM compilado a `-O0`/`-O1` es **2-4x más lento como compilador**, y todo
lo que compiles después con él paga ese coste. El ahorro en tiempo de
compilación (1,5-2x) no compensa un toolchain permanentemente peor. Los flags
"devel" tienen sentido para una variante de depuración, nunca para el
compilador que se instala.

## PGO: cómo y en qué orden

El PGO se hace con la interfaz de clang, no con la de gcc:

```
-fprofile-generate=<dir>   → escribe <dir>/*.profraw al ejecutar el binario
llvm-profdata merge        → <dir>/merged.profdata
-fprofile-instr-use=<archivo.profdata>  → aplica el perfil al recompilar
```

Dos requisitos que no son evidentes:

1. **El toolchain necesita el runtime de perfil.** Sin
   `libclang_rt.profile.a` la pasada instrumentada no enlaza (se queda con
   `__llvm_profile_*` sin resolver). Por eso la receta de llvm construye
   compiler-rt con `COMPILER_RT_BUILD_PROFILE=ON`.
2. **Son dos builds, no uno.** El build instrumentado usa el clang ya
   instalado, así que ese clang tiene que traer ya el runtime de perfil. El
   orden correcto es:
   1. `LLVM_PGO=0` (build normal, con el runtime) → instala el toolchain.
   2. `LLVM_PGO=1` (build instrumentado → entrenamiento → recompilación con
      el perfil) → instala el llvm con PGO.
   3. `LLVM_BOLT=1` (instrumentación de BOLT → perfil → reordenado).

El entrenamiento de la fase 2 **reconstruye la parte caliente del
compilador** (IR, optimizador y backend X86) con el clang ya instrumentado:
es el mismo flujo que usa upstream, y el perfil que sale cubre de verdad el
frontend y el optimizador. Compilar un corpus pequeño daría un perfil mucho
más débil.

Lo mismo aplica al PGO de ffmpeg (`FFMPEG_PGO=1`): necesita el runtime en el
toolchain, así que va después del paso 1.

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

1. **Nunca dos paquetes `heavy` a la vez.** Las tandas se serializan: dentro
   de una tanda, los trabajos de compilación de una clase pueden solaparse,
   pero dos paquetes pesados distintos no se compilan a la vez.
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
