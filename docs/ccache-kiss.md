# ccache y KISS: efectividad baja (~3.9%) y solución

## Problema

`ccache -s` en mitad de un `kiss build webkitgtk`:

```
Cacheable calls: 12477 / 12598 (99.04%)
  Hits:     486 / 12477 ( 3.90%)
  Misses: 11991 / 12477 (96.10%)
Local storage:  Cache size (GB): 1.0 / 10.0
```

Casi todos los objetos se recompilan en cada build pese a ser idénticos. El
cache crece (~1 GB) con entradas que nunca se reutilizan.

## Causa raíz

KISS construye cada paquete en un directorio único por ejecución:

```sh
# /usr/bin/kiss
proc=${KISS_TMPDIR:="$cac_dir/proc"}   # línea 2093
proc=${proc%"${proc##*[!/]}"}/$KISS_PID # línea 2094 -> ~/.cache/kiss/proc/<PID>
```

`$KISS_PID` cambia en cada ejecución (por defecto `$$`, línea 2129:
`: "${KISS_PID:=$$}"`). Las rutas absolutas de ese directorio aparecen en:

- los argumentos de compilación (`-I.../proc/<PID>/build/webkitgtk/...`), y
- los marcadores `#line` de la salida preprocesada (`__FILE__`, headers).

ccache hashea esas rutas; como el directorio cambia por build, cambia la clave
de cada objeto y todo es miss. No es un problema de flags ni de la fuente.

### Pruebas realizadas

| Escenario | Resultado |
| --- | --- |
| Mismo código compilado desde dos directorios distintos (rutas absolutas distintas en `#line`) | 2/2 miss |
| Igual, con cache limpio y `base_dir = /home/darktux` | 2/2 miss |
| Recompilar en el mismo directorio ya cacheado | hit (así se explica el 3.9% residual: tests de cmake y repeticiones puntuales) |

Conclusión: **`base_dir` no resuelve esto**. `base_dir` solo reescribe el
prefijo común; la parte `proc/<PID>/...` sigue siendo distinta en cada build.

## Solución recomendada: fijar `KISS_PID`

KISS permite sobreescribir `KISS_PID` desde el entorno (`${KISS_PID:=$$}`),
de modo que el directorio de build sea estable entre ejecuciones y las claves
de ccache no cambien. **No requiere modificar kiss ni ningún paquete.**

```sh
# Opción 1: por invocación
KISS_PID=stable kiss b webkitgtk

# Opción 2: en el perfil del shell (para todos los builds)
export KISS_PID=stable
```

Efecto: todos los builds usan `~/.cache/kiss/proc/stable/...` y los `#line`
son idénticos entre ejecuciones.

### Procedimiento de validación

```sh
KISS_PID=stable kiss b libspiel   # 1ª vez: miss, rellena el cache
ccache -z                          # pone a cero las estadísticas
KISS_PID=stable kiss b libspiel   # 2ª vez: debe ser ~100% de hits
ccache -s | head -4
```

### Consideraciones

- **Primer build**: sigue siendo todo miss (hay que rellenar el cache con las
  claves nuevas). La ganancia empieza en el segundo build.
- **Entradas existentes**: las almacenadas hasta ahora quedan obsoletas; se
  van eliminando solas por LRU (o `ccache -C` para liberar ~1 GB ahora).
- **Concurrencia**: dos `kiss build` simultáneos con el mismo `KISS_PID`
  compartirían directorio. KISS construye de uno en uno, así que en uso normal
  no hay conflicto; si se automatizan builds en paralelo, usar valores
  distintos por job.
- **Nombres de log**: los logs quedan como `pkg-fecha-stable` en lugar de
  `pkg-fecha-<PID>` (solo cosmético, se siguen sobrescribiendo por fecha).
- `KISS_TMPDIR` no sirve para esto: el PID se añade igualmente (línea 2094).

## Alternativa permanente (no aplicada)

Modificar `/usr/bin/kiss` para que el sufijo sea configurable o fijo:

```sh
# línea 2094, antes:
proc=${proc%"${proc##*[!/]}"}/$KISS_PID
# después (ejemplo):
proc=${proc%"${proc##*[!/]}"}/${KISS_PROC_SUFFIX:-$KISS_PID}
```

y exportar `KISS_PROC_SUFFIX=stable`. Es equivalente a fijar `KISS_PID`, pero
queda embebido en el gestor; requiere mantener el parche al actualizar kiss.

## Cómo hacer que ccache participe (sin romper CMake)

Fijar `KISS_PID` solo evita la invalidación por rutas. Falta que el compilador
pase por ccache. Hay dos vías y **una de ellas rompe CMake**:

### ❌ NO usar los wrappers en PATH con CMake

Poner `/usr/lib/ccache/bin` al frente de `PATH` hace que CMake, con
`-DCMAKE_C_COMPILER=clang`, resuelva `clang` al symlink y lo reduzca a
`/usr/bin/ccache`. Después invoca `ccache -O1 ... -c file.c` **sin el nombre
del compilador**, y ccache interpreta `-O1` como opción propia:

```
-- Check for working C compiler: /usr/bin/ccache - broken
/usr/bin/ccache: unrecognized option: O
CMake Error ... is not able to compile a simple test program.
```

Con `-DCMAKE_C_COMPILER=ccache` (lo que se probó en la receta) pasa lo mismo:
ccache necesita el compilador como primer argumento. **Revertido.**

### ✅ La forma correcta en CMake: `COMPILER_LAUNCHER`

En `extra/webkitgtk/build` (y cualquier paquete basado en CMake):

```sh
	-DCMAKE_C_COMPILER=clang \
	-DCMAKE_CXX_COMPILER=clang++ \
	-DCMAKE_C_COMPILER_LAUNCHER=ccache \
	-DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
```

CMake invoca entonces `ccache /usr/bin/clang ...`, que es lo que ccache espera.
Para paquetes con `make`/autotools sí sirve `CC="ccache clang"` o los wrappers
en `PATH`; el problema es específico de cómo CMake resuelve el compilador.

## Tamaño del cache

`CCACHE_MAXSIZE` subido de `10G` a `100G` (hay ~1.7 T libres en `/`). WebKit y
LLVM por sí solos generan bastante más de 10 G de objetos, así que 10 G
provocaba expulsión por LRU y hits solo parciales.

## Alternativa (mejor para paquetes enormes): árbol persistente

ccache no resuelve del todo WebKit: aunque esté activo, puede no retener todos
sus objetos. Para parches pequeños, lo más rápido es compilar con el árbol de
CMake/ninja **persistente** y dejar que ninja recompile solo lo afectado:

```sh
# primera vez (una sola)
mkdir -p ~/webkit-build && cd ~/webkit-build
# extraer fuente + aplicar los patches/ (los mismos que la receta)
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr \
      -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
      -DCMAKE_C_COMPILER_TARGET=x86_64-pc-linux-musl \
      -DCMAKE_CXX_COMPILER_TARGET=x86_64-pc-linux-musl \
      -DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
      -DPORT=GTK -DUSE_GTK4=OFF -DUSE_SOUP2=OFF -DENABLE_X11_TARGET=ON
ninja -C build -j16          # ~1 h la primera vez

# después de cambiar un parche
ninja -C build -j16          # solo lo afectado + enlace: minutos
```

Regla: parchear un `.cpp` recompila 1 fichero; parchear un **header** recompila
todos sus dependientes. Por eso `NonCompositedFrameRenderer.h` es barato y
`FrameRenderer.h` sería más caro.

## Estado: aplicado (2026-09-28, actualizado 2026-10-14)

- `~/.mkshrc`: `export KISS_PID="stable"` (bloque "Entorno de construcción de
  Sprint"). Todos los builds futuros usan `~/.cache/kiss/proc/stable/...` y
  ccache reutiliza objetos entre ellos.
- `~/.mkshrc` (2026-10-14): `CCACHE_MAXSIZE="100G"`.
- `extra/webkitgtk/build` (2026-10-14): `-DCMAKE_C_COMPILER=clang` +
  `-DCMAKE_C_COMPILER_LAUNCHER=ccache` (antes estaba `-DCMAKE_C_COMPILER=ccache`,
  que rompía la configuración de CMake). El `PATH` con los wrappers se probó y
  se **revirtió** (rompe CMake).
- `~/.cache/ccache/ccache.conf`: retirado `base_dir = /home/darktux`
  (no aportaba y invalidaba las claves del cache).

Nota: el rebuild de webkitgtk en curso se lanzó con `KISS_PID=13248` para
reutilizar el directorio del build interrumpido y retomar donde estaba; es un
valor puntual. El primer build futuro con `stable` rellenará el cache con las
claves nuevas y a partir del segundo ya habrá hits.

Otro aprendizaje del día: los builds largos lanzados como procesos hijo de un
asistente de IA mueren al cerrar la sesión. Lanzarlos desvinculados:

```sh
setsid sh -c 'kiss b webkitgtk >/dev/null 2>&1' </dev/null &
```
