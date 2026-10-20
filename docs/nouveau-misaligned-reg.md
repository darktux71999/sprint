# Registro de investigación — nouveau Kepler MISALIGNED_REG

## Síntoma

Kernel nouveau 7.2.8 (monolítico, `CONFIG_DRM_NOUVEAU=y`) en GK208B
(GeForce GT 730, Kepler sm35) reporta:

```
nouveau 0000:03:00.0: gr: TRAP ch N [<proc>]
nouveau 0000:03:00.0: gr: GPC0/TPCx/MP trap: global 00000004
  [MULTIPLE_WARP_ERRORS] warp XXXX [MISALIGNED_REG]
```

- 9 traps con firefox (WebRender sobre GL nvc0)
- 3 traps con picom (backend glx sobre zink → NVK/NAK)
- Sin hang, sin reset: la GPU aborta el draw call ofensor y sigue.
- Sistema estable tras los traps.

## Config reproducida (2026-09-25)

- sprint/mesa 26.2.3 (`-Dgallium-drivers=nouveau,zink`,
  `-Dvulkan-drivers=nouveau`), llvm 22.1.8 toolchain.
- Kernel: custom 7.2.8, compilado con clang 22 (musl).
- X: xlibre + DDX modesetting + glamor (DRI3, TearFree).
- glmark2 sobre zink/NVK: OK (328 fps), sin traps.
- picom --backend glx sobre zink: visual OK pero 3 MISALIGNED_REG.
- firefox sobre nvc0: MISALIGNED_REG recurrentes sin zink.

## Hipótesis de trabajo

MISALIGNED_REG = shader compilado emite instrucciones que violan
restricciones de alineación de registros en Kepler (sub-registros
multi-palabra cruzando límites / deltas de stride no alineados).
Interacción sospechada kernel↔mesa:

1. Compilador de shaders (nvc0 C++ o NAK Rust) genera el código
   "legal" según IR, pero la codificación/encoding espera tamaños
   alineados que el firmware/GR del kernel no acepta.
2. El kernel nouveau valida la QMD/datos del shader y atrapa el warp
   inválido en vez de corregir (no hay fixup).
3. Posible relación con cambios recientes de mesa en la gestión de
   registros intermedios (spill/rename) y de kernel nouveau en la
   validación de contextos GR para Kepler.

## Siguientes pasos

- [ ] Capturar con `NV50_IR_DEBUG` / `NAK_DEBUG=print` el shader que
      trappea (picom es el caso más chico y reproducible).
- [x] Búsqueda aguas arriba: `MISALIGNED_REG` no tiene issues abiertos
      en mesa gitlab ni resultados en la web (2026-09-25). Bug no
      reportado aún → candidato a repro limpio para reportar.
- [ ] A/B kernel 7.2.2 vs 7.2.8 (7.2.2 está en /boot) para aislar el
      lado kernel.
- [ ] A/B mesa: volver a 25.3.6 (en ~/.cache/kiss/sources/mesa) y
      repetir picom-zink.
- [ ] Verificar si los traps de firefox (nvc0, sin zink) existían con
      el boot anterior (7.2.6).

## Hallazgos del análisis de código (mesa 26.2.3)

1. El trap lo reporta `gf100_gr_trap_mp()` del kernel
   (drivers/gpu/drm/nouveau/nvkm/engine/gr/gf100.c:1264): error de
   warp 0x08 `MISALIGNED_REG` del MP — instrucción de shader cuyo
   encoding accede registros con alineación inválida. El kernel solo
   reporta; el bug está en el shader binario (compilador).

2. Mapeo de chipset a shader model en mesa:
   - `sm_for_chipset()`: GK208B = chipset 0x106 → sm **35**
   - NAK: `ShaderModel32` cubre 32..49 → GK208B compila con el
     encoder **SM32Encoder** (GK110-family) vía `encode_kepler_shader`
   - nvc0 (GL): `chipset & ~0xf` → 0x100 → builtin code de **gk110**
     igualmente.
   - Ambos compiladores tratan GK208B como familia GK110. GK208 es un
     refresh de GK107; el driver NVIDIA anuncia CC 3.5 por marketing.
     El mismatch encoder/chipset es sospechoso pero NO probado (los
     builtin de nvc0=gk110 han funcionado siempre en GK208).

3. El register allocator de NAK alinea vectores de 2 componentes a
   registros pares (`try_get_vec_reg`: `align = next_power_of_two(2)`),
   así que los pares de 64-bit GPR están alineados por diseño.
   `MISALIGNED_REG` debe venir de otra ruta: candidatos:
   - registros con más de 2 componentes (vec4 128-bit) cruzando
     límites
   - `OpAtom` con srcs packed (sm20.rs:2567 exige packed + pares)
   - predicates/flags o UGPR con stride raro
   - scheduling de instrucciones (sched cada 7 instrs) con deps mal
     calculados (calc_instr_deps para sm<70 es nuevo código en 2025)

4. glmark2 sobre zink/NVK corre LIMPIO (0 traps) pero picom trappea
   siempre que compone (incluso con --no-shadow). Diferencia: picom
   importa DMA-BUFs de X (DRI3) y hace blending por-píxel continuo;
   sospechoso un patrón concreto de instrucción que glmark2 no usa.

## Repro actual (picom sobre zink)

```sh
MESA_LOADER_DRIVER_OVERRIDE=zink picom --backend glx --diagnostics
# dmesg muestra TRAP ch9 picom[P] warp 10008/30008 [MISALIGNED_REG]
# (global 00000000, sin MULTIPLE_WARP_ERRORS)
```

Con `--no-shadow` sigue trappeando → no es el shader de sombras.

## Plan de reporte aguas arriba

1. Repro: picom (o shader GL mínimo con el mismo patrón) sobre
   zink/NVK en GK208B; dmesg con trap.
2. Incluir: mesa 26.2.3, kernel 7.2.8, NAK_DEBUG=print dump del shader
   ofensor (correlacionar con el trap mediante bisección de shaders).
3. Dirigir a mesa gitlab (component nouveau/NVK) con cc a nouveau IRC.

## Sesión 2026-09-26 — experimentos de aislamiento (dmesg: 16 traps, todos picom)

### Matriz repro (timeout 15-30 s, delta de `dmesg | grep -c MISALIGNED`)

| Caso | delta | nota |
| --- | --- | --- |
| picom glx + zink (cualquier config) | +1 en **14/14** corridas | incl. 3 s y 6 s → trampa en el primer frame |
| picom glx + zink, config mínima (`backend=glx`) | +1 | sombras/clip/fade/corner NO importan |
| picom **egl** + zink | +1 | pese a `egl_bind_pixmap ERROR` (fallback con copia) |
| picom glx + nvc0 | +1 en 1/7 | resto 0 |
| picom xrender | 0 | baseline |
| glxgears (zink y nvc0) | 0 | |
| glmark2 zink (previo) | 0 | |

Conclusión: el disparador está en el **core del compositor** (primer frame de
composición), y con zink/NAK trappa de forma determinista.

### Pruebas de ejecución aislada (todas limpias, sin traps) — `/tmp/inv/`

Repros mínimos que ejecutan CADA candidato sospechoso individualmente en el
GPU real:

- `glx64 u64`: shaders GLSL con `uint64_t` shl/shr/ashr dinámicos → NAK
  emite `shf.l.w.u64.hi` con **dst impar** (r1, r5, r7…) → **NO trappa**.
- `glx64 timer`: `glBeginQuery(GL_TIME_ELAPSED)` + lectura de resultados →
  compila **y ejecuta** `nvk-meta-copy-queries` → **NO trappa**.
- `vkcopy` (Vulkan crudo): 64× `vkCmdCopyBufferToImage` RGBA8 tiled →
  ejecuta `vk-meta-copy-buffer-to-image-compute` (imadsp.u16h0 + sustga) →
  **NO trappa**.
- `glx64 upload` (cliente, PBO, PBO grande): rutas de subida zink → limpio.
- `glx64 picomfs`: win shader real del fork (SDF, brightness, dither bayer)
  + blending → limpio en zink y nvc0.

### Auditoría estática del IR de NAK (dumpA/dumpB, 21 shaders de picom)

Extrae el IR final (`NAK IR after calc_instr_deps`) y verifica: bases de
dirección a64 pares, dst multi-registro alineados (par/quad), átomos 64,
shf64, ald/ast. **Única anomalía**: `shf.l.w.u64.hi` con dst impar en
`nvk-meta-copy-queries` — ejecutada aislada sin trampa ⇒ el modelo de reglas
actual no encuentra la violación. Causas restantes: (a) bug de *encoder*
(IR correcto, bits incorrectos), (b) regla de alineación de Kepler que no
conocemos, (c) una key/variante de shader de picom que no se compila en 20 s.

### Descartes de esta sesión

- Kernel drm-nouveau como causante: la tabla `gf100_mp_warp_error` es
  idéntica desde kernel 4.1 (envytools); el kernel solo lee TPC 0x648/0x650
  y limpia. MISALIGNED_REG (rnndb: `MISALIGNED_GPR`) lo valida el hardware
  contra el encoding de la instrucción, que solo genera mesa.
- NAK no es el único culpable: nvc0 también trappó (1/7 con picom; firefox
  9 traps en la sesión previa), pero la sensibilidad con zink es 100% vs
  14% ⇒ NAK es el candidato principal.
- SHF64 impar, copy-queries, copy-buffer-to-image, subidas y win shader:
  ejecutados aislados sin trampa.

### Siguientes pasos concretos

1. Repro mínima "picom-like" sumando piezas hasta trappar (FBO offscreen +
   todas las keys del win shader con mask + present/interpolating).
2. Correr `nak` hw_tests (`test_shl64`, `test_op_shf`, …) en GK208B
   (mesa build con tests) — ejecuciones reales de esos patrones.
3. A/B mesa 25.3.6 (fuente en ~/.cache/kiss/sources/mesa) para ver si la
   trampa aparece igual.
4. Con el shader ofensor identificado: reportar a mesa gitlab con dump.

## Búsqueda en listas de correos y trackers (2026-09-26/27)

Fuentes: lore.kernel.org (nouveau@, dri-devel@, mesa-dev@), bugs.freedesktop.org,
gitlab.freedesktop.org, bugs.debian.org, lists.debian.org (DDG site:).

### Precedentes DIRECTOS del mismo error (0x08) — todos en nvc0, ya corregidos

1. **freedesktop bug #95403 (mayo 2016)** — "[GK110] misaligned_gpr spamming
   dmesg when playing victor vran". Mismo error, reportado con apitrace.
   **Fix**: Ilia Mirkin, commit `2ef3cdb07e42`
   "nvc0/ir: make sure to align the second arg of TXD to 4, as we do for TEX"
   — GK110 exige que el **segundo argumento de TXD** (derivadas) esté
   alineado a 4; el padding se perdía al añadir argumentos extra después de
   handleTEX. Reviewed-by Samuel Pitoiset; backport a mesa-stable.
2. **mesa-dev, feb 2019** — Mirkin, "[PATCH] nvc0/ir: fix second tex
   argument after levelZero optimization":
   > "Fixes **MISALIGNED_REG** errors in Hitman when run with bindless
   > textures enabled **on a GK208**."
   Regla documentada: en GK104+, **si TEX tiene >4 fuentes, el segundo tuple
   de registros debe alinearse a 4, aunque sea un solo registro de4 bytes**.
   La optimización levelZero quitó un source de relleno y el RA empaquetaba
   mal → fix en `nv50_ir_ra.cpp` (texConstraintNVE0/GM107).
   **Chip exacto: GK208 = el nuestro.**
3. **Semántica de warp errors**: hilo2015 "Documentation request for MP warp
   error0x10" — **Robert Morell (NVIDIA)** responde preguntas sobre el
   significado de los traps en **gpu-public-documentation@** (copiado a
   nouveau@). Precedente de que se puede preguntar a NVIDIA la semántica
   exacta de **0x08 MISALIGNED_REG, que nadie ha documentado nunca público**.

### Lo que NO existe (confirmado hoy)

- lore: "MISALIGNED_REG" → solo7 resultados, todos los renombres de enum del
  kernel en2016. Cero reportes de la era NVK/NAK/zink.
- bugs.freedesktop.org quicksearch MISALIGNED_REG → **0 bugs**.
- gitlab.freedesktop.org issues MISALIGNED_REG / MISALIGNED_GPR → **0**.
- Debian: bugs.debian.org y lists.debian.org → **0 resultados** para
  MISALIGNED_REG/GPR.
  - Existe **bug#1132224** (marzo 2026): "nouveau regression on
    **GK208B/GT 730** after kernel update: artifacts and X crashes" —
    MISMO chip y compo (xfwm4), pero error **ILLEGAL_INSTR_ENCODING (0x09)**,
    biseccionado al kernel 6.12.73→6.12.74, cerrado por Debian con "report
    to Devuan" sin solución real (tag upstream, no reenviado a lore).
- Web general (DDG): `"MISALIGNED_REG" nouveau` →0 resultados.

### Conclusión

Nuestro caso (NAK/NVK + picom + GK208B) **está sin reportar**. El patrón
histórico es claro: cada pocos años aparece un bug de **alineación de
operandos de instrucciones de textura** en un backend de mesa que trappa
MISALIGNED_GPR/REG exactamente en GK110/GK208 (2016 TXD,2019 TEX bindless),
y se corrige con constraints en el RA. NAK es un backend nuevo sin esos
constraints verificados.

Acciones propuestas:
1. Preguntar la semántica exacta de0x08 en gpu-public-documentation@
   (precedente Morell2015) — confiaría o descartaría la hipótesis del
   "second tuple %4" de una vez.
2. Reportar en gitlab.freedesktop mesa/nouveau con dumps NAK_DEBUG=print,
   citando bugs95403 y el patch de2019 como precedentes de clase.
3. Bug#1132224 como referencia paralela (mismo chip, error vecino).

## CAUSA RAÍZ ENCONTRADA (2026-09-26 noche)

### Repro mínimo puro Vulkan (sin GL, sin picom, sin X)

`/tmp/inv/vkcopy.c` — vkCmdCopyBufferToImage con **VK_FORMAT_R8_UNORM**:

| formato | traps (32 loops) |
|---|---|
| R8 | **+65** (~2 por copia, ¡siempre!) |
| RG8 | 0 |
| R16 | 0 |
| RGBA8 | 0 |

Misma ruta meta que usa picom: `vk-meta-copy-buffer-to-image-compute`
(NVK) → shader NAK `sustga` (store de superficie).

### El bug (NAK, mesa 26.2.3)

`src/nouveau/compiler/nak/from_nir.rs:2938`, intrínseco `nir_intrinsic_sustga_nv`:

```rust
let image_access = ImageAccess::Formatted(ChannelMask::new(0xf)); // ¡siempre .rgba!
```

- NAK **hardcodea channel mask =0xf** (cuádruple) para el store de
  superficie, pero para R8 el `data` de NIR tiene **1 componente** → el RA
  lo alinea como escalar (%1) y puede caer en r2 (≡2 mod4).
- El hardware (GK208B) lee el operando como **cuádruple (sz=128 → base
  %4)** por el mask=0xf → base r2 ≡2 mod4 → **MISALIGNED_REG (0x08)**.
- Los intrínsecos hermanos (`bindless_image_load/store`, `sust`,
  `sustb`) usan correctamente `ChannelMask::for_comps(comps)`; solo
  `sustga_nv` está en hardcoded.
- Evidencia IR (R8 vs R16, mismo shader, /tmp/inv/t_r8b_nak.log):
  - R8 (trappa): `sustga.p.rgba.cg [r0..2] r9 **r2** p0` (escalar, ≡2)
  - R16 (limpio): `sustga.p.rgba.cg [r0..2] r9 **r4..8** p0` (cuádruple %4)
- Determinista: misma forma de shader → mismo RA → picom trappa 100%
  porque sube `default_mask_texture` GL_R8 1×1 en cada arranque.

### Fix

Patch en `~/proyectos/sprint/xorg/mesa/patches/0001-nak-sustga-channel-mask.patch`
(`ChannelMask::new(0xf)` → `ChannelMask::for_comps(intrin.num_components)`
+ asserts de consistencia con los intrínsecos hermanos).

Receta kiss actualizada: `version 26.2.3 3`, `sources` incluye el patch,
`build` lo aplica.

### Verificación en curso

- mesa parcheado compilando en /tmp/inv/mesa-out (NVK+zink).
- vkcopy R8 con ICD parcheado → esperado 0 traps.
- picom zink con GL parcheado → esperado 0 traps.

### VERIFICACIÓN (post-reboot,19:47-19:5x)

Harness recreado en `~/mesa-fix/` (perdido todo lo de /tmp por el tmpfs):

- **Baseline (mesa 26.2.3 SIN parchear)**: `vkcopy 4 r8` → **+8 traps**
  (2 por cada copia R8, determinista); `rgba8` →0. (Antes del freeze:
  r8×32 → +65.)
- **Parcheado** (build en `~/mesa-fix/build`, ICD propio en
  `~/mesa-fix/icd_patched.json`): `vkcopy` r8/rg8/r16/rgba8 ×2 →
  **delta=0 en todos**, y **readback byte-a-byte =0 mismatches**
  (la corrección del store R8 se mantiene).
- Receta kiss lista: `version 26.2.3 3`, sources+checksums con el patch,
  build lo aplica.
- Pendiente: verificación GL/picom (X no estaba arrancado tras el reboot)
  e instalación (necesita root).

Causa probable del freeze: la tormenta de ~65-100 traps seguidos de GPU
(wedge de nouveau sin recuperación). Próximas corridas: ≤10 traps.

### INSTALADO Y VERIFICADO EN EL SISTEMA (20:0x)

- `kiss build mesa` con la receta `26.2.3 3` → construyó, empaquetó
  (`mesa@26.2.3-3.tar.lz4`) e **instaló** (vía doas).
- `/var/db/kiss/installed/mesa/version` = `26.2.3 3` ✓
- Verificación con el NVK YA instalado (ICD del sistema):
  - `vkcopy 4 r8` → **delta=0** (antes de instalar: +8; tormenta previa: +65)
  - readback R8 → `mismatches=0` (corrección intacta)
  - rgba8 →0 traps
- Pendiente cuando arranque X: glmark2/picom con `--backend glx` sobre
  zink → se espera 0 traps (antes: +1 en14/14).
- Siguiente paso recomendable: reportar upstream (gitlab mesa, issue + MR
  con este patch) — no existe ningún reporte de MISALIGNED_REG en la era
  NVK.

- Confirmación GL con X arrancado (26.2.3-3 instalado):
  - glxgears zink:0 · glmark2 zink:0 · **picom zink: delta=0**
    (antes de instalar: +1 en 14/14 corridas)
  - dmesg estable en18 traps totales (todos de las pruebas previas a la
    instalación); cero traps nuevos desde el install.

## Sesión 2026-09-27 — cuelgue total de X y monitorización persistente

Síntoma nuevo (post-fix): en la sesión previa el servidor X colapsó por
completo y secuestró todo el input; hubo que forzar el apagado y dmesg
(RAM) se perdió — por eso "no da tiempo de identificar la falla".

- Cambio relevante hecho a mano: aumento manual del clock de la GPU vía
  debugfs pstate (`/sys/kernel/debug/…`). Ruta y valor exactos no están en
  el historial de shell; `hang-watch.sh` los capturará si corre con doas.
- Hipótesis: clock alzado sin subir voltaje → wedge de GPU → X congelado.
  Coherente con el freeze previo ya atribuido a una tormenta de traps.
- Herramienta nueva: `~/mesa-fix/hang-watch.sh` (instrucciones en la
  cabecera):
  - dmesg en vivo → `nvc0-catch/hang-<stamp>.log` (diff cada 1 s) con
    sync inmediato al detectar TRAP/fault/timeout/lockup/SysRq/BUG/Oops.
  - muestreo cada 5 s → `state-<stamp>.log`: temp GPU (hwmon nouveau),
    pids de X/picom, pstate/clocks si hay permiso de root.
  - un apagado forzado sólo pierde ~5 s de estado.
- Bug corregido en `watch-traps.sh`: el volcado de "MP trap" usaba un
  contador ya actualizado (`n - seen + 1` → siempre 1 línea); contador
  propio ahora.
- En un cuelgue, antes de cortar (kernel.sysrq=1 ya activo; SysRq va al
  kernel, no pasa por X): Alt+SysRq+t (lista de tareas), +w (pilas en D),
  +s (sync). Si después del corte el log no tiene eventos nuevos, el
  kernel estaba colgado y no solo X — también es un dato.

## Sesión 2026-10-14 — verificación del fix NAK y bug nuevo del compositor VPP

### MISALIGNED_REG: fix verificado en el sistema

- Parche `0001-nak-sustga-channel-mask.patch` presente en la receta kiss
  (`mesa 26.2.4 1`, sources incluye ambos parches).
- `vkcopy` r8/rg8/r16/rgba8 → delta=0 de traps, readback mismatches=0.
- Boot completo: 0 MISALIGNED_REG (los traps del boot son de otra clase).

### Bug nuevo: RT_WIDTH/HEIGHT_OVERRUN (PROP/ROP) en el VPP de VA

- Sintoma: `GPC0/PROP trap [RT_WIDTH/HEIGHT_OVERRUN]` en el escaneo de
  plugins de GStreamer (`libgstva.so`) y en cualquier VPP de VA sobre
  nouveau. Sin hang, pero vídeo VA corrupto.
- Repro mínima pura libva: `~/mesa-fix/va_probe.c` (sin X/GL/GStreamer):
  copia VPP NV12 1:1 + verificación de contenido por filas.
  Baseline (mesa 26.2.4-1 sin parchar): 235/240 filas luma corruptas,
  60/120 croma, ~2 traps por pasada.
- Causa raíz (mesa, `vl_compositor_yuv_deint_full`): nouveau_vp3 crea
  buffers interlaced (campos como capas de array; superficies por campo
  de h/2) pero el compositor indexaba los planos como progresivos
  ([Y,U,V]) y usaba viewports de cuadro completo sobre targets de campo
  → renders a planos equivocados + basura por los bordes.
- Fix: render por campo (planos × campos), selección de campo del origen
  vía BOB_TOP/BOTTOM (layer = zw.x), rect de destino reducido a la mitad
  vertical por campo, y compensación del half-line shift de BOB (que
  mezclaba filas con fields-as-layers).
- Parche: `~/proyectos/sprint/xorg/mesa/patches/0005-vl-compositor-interlaced-dst.patch`
  (y copia en `~/mesa-fix/`). Validado con build 26.2.4 propio
  (`/tmp/mesa2624/build`, driver VA cargado vía LIBVA_DRIVERS_PATH):
  **contenido PASS byte-perfecto** (0/240 filas, 0/120 croma).

### Bug nuevo #2 (parcialmente corregido): clear de superficies video-tiled

- Aislado: la asignación diferida + `clear_render_target` de superficies
  NV12 (layout video `tile_mode 0x10`, `nvc0_miptree_init_layout_video`)
  trae la ROP por sí sola, sin draws. Repro: `~/mesa-fix/va_clear_test.c`
  (crear superficie NV12 + vaGetImage): +1 trap por asignación.
- Y800 (plano único, layout genérico sin video tiling) → 0 traps.
- Umbral (antes del fix): trapa si el campo ≥32 filas o el ancho ≥256.

**Fix parcial aplicado** (`nvc0-clear-video-tile-pitch.patch`, en la
receta): en `nvc0_clear_render_target`, para `tile_mode 0x10` programar
RT_HORIZ con el pitch en bytes (como el camino lineal) en vez de
`sf->width`. Resultado:
- Clase por ancho RESUELTA: 256x16 y 320x16 → 0 traps (antes +1).
- Contenido VPP sigue byte-perfecto (los draws no se afectan).
- Clase por altura queda: 64x64 y 320x240 siguen +1 trap por asignación
  (`RT_HEIGHT_OVERRUN x = bytes_fila-16, y = 16`; la coordenada y=16 es
  constante = altura de tile probable). `align(height,16)` no lo arregla.

Sospechosos restantes para la clase altura: CLEAR_BUFFERS del ROP con
tile_mode 0x10 en superficies de ≥2 filas de tile, o el manejo de capa
(`z` de CLEAR_BUFFERS sin `first_layer`) en superficies de campo.
Siguiente experimento: comparar con mmiotrace del blob (método sección 5
del informe deep_research) o probar la corrección de capa en
CLEAR_BUFFERS.

**Datos de rnndb y descartes (2026-10-14, tarde):**
- rnndb `gf100_3d.xml`: el campo 0x14 del RT es `BLOCK_DIMENSIONS`
  (HEIGHT en log2) y `CLEAR_BUFFERS` (0x19d0) tiene campos RT y LAYER.
  Macros mesa: NVC0_TILE_SIZE_X = 64<<x (bytes), NVC0_TILE_SIZE_Y =
  8<<y (filas) → tile_mode 0x10 = tile de 64 bytes × 16 filas.
- Descartados por experimento: `align(height,16)` ✗ · VERT en tiles ✗ ·
  VERT ×16 ✗ (VERT se ignoraba) · clear por rebanadas de 16 filas con
  scissor ✗ · capa en el campo LAYER ✗ · VIEWPORT previo ✗.

**BUG #2 CORREGIDO (2026-10-14, noche) — `0002-nvc0-clear-video-tiles.patch`**

Tres problemas encadenados en `nvc0_clear_render_target` para superficies
video (`tile_mode 0x10`) y plantillas de superficie:

1. RT_HORIZ se programaba en texels; para tile 0x10 hace falta el pitch
   en bytes (clase ancho).
2. El clear fijo del ROP tiene un límite de **16 filas relativas a la
   dirección del RT** (VERT se ignora): se limpia por rebanadas de una
   fila de tile moviendo la dirección base del RT (`addr += y0×pitch`).
3. `nouveau_vp3_video_buffer_create` (y `vl_video_buffer`) rellenan
   plantillas `pipe_surface` a mano, sin pasar por `create_surface` →
   los campos extra de `nv50_surface` (`sf->depth`, `sf->offset`) son
   basura. `sf->depth` gigante hacía fallar el `PUSH_SPACE` y los clears
   de los campos 1 (capa 1) **se salteaban en silencio** → contenido
   viejo en los campos. Ahora `depth` se toma de
   `last_layer-first_layer+1` y el offset del nivel real del miptree;
   el desplazamiento de capa va en la propia dirección del RT.

Verificación (`~/mesa-fix/va_clear_test`, ahora con validación de
contenido): 256x16, 320x240, 64x64, 48x16 → **delta=0 y ambos campos
limpios (PASS)**. `va_probe` contenido byte-perfecto; `vkcopy` OK.

Receta kiss: 4 fuentes (tarball + 3 parches) con checksums al día.

### Pendientes (actualizado 2026-10-14)

1. ~~Bug #2: RT_HORIZ=pitch~~ → bug #2 CORREGIDO (ver sección anterior).
2. Instalar mesa parcheada en el sistema (`kiss build mesa` + doas) —
   la receta ya incluye los tres parches validados.
3. Reporte upstream: dos bugs independientes
   (`~/mesa-fix/upstream-report-vpp.md` + el del NAK ya existente).

### Estado de los relojes/pstate (2026-10-14)

- La GPU corre actualmente con el **pstate 0f** (perfil máximo de
   Kepler) de forma **estable** según el uso diario → el aumento manual
   de clock NO es el causante de los cuelgues por sí solo.
- Los freezes de X anteriores correlacionan con las **tormentas de
   traps** (65-100 seguidos; wedge de nouveau sin recuperación), ya
   corregidas por los tres parches → la hipótesis del cuelgue queda
   apuntada a los traps, no al reclocking.
- Con 0f activo, el techo de rendimiento ya está desbloqueado (el
   informe deep_research estima ~80% del propietario con reclocking vs
   ~10% sin él).
- Vigilancia residual recomendable: temperatura bajo carga sostenida a
   0f (TDP 38 W, variantes pasivas; riesgo de throttling) —
   `hang-watch.sh` ya muestrea hwmon cada 5 s.

## Sesión 2026-10-14 (noche) — luakit/webkitgtk en negro + hallazgos

### Problema del usuario y solución

Luakit + webkitgtk 2.54 con aceleración GPU: pantalla negra / proceso
web cruashea (youtube). Con la aceleración desactivada funcionaba lento.

**Diagnóstico** (con capturas de pantalla verificadas):
- Config externa encontrada: `~/.config/luakit/userconf.lua` tenía
  `hardware_acceleration_policy = "never"` (workaround previo).
- Con aceleración activa: HTML simple renderiza ✓, pero el
  **renderizador DMABUF de WebKit falla sobre nouveau** (youtube →
  "Web process crashed"; pantallas complejas → negro).
- WebGL aparecía "deshabilitado" pero era un **default del propio
  luakit** (`webview.enable_webgl = false`), no del driver.

**Solución aplicada** (verificada con screenshots):
1. `export WEBKIT_DISABLE_DMABUF_RENDERER=1` en `~/.config/sx/sxrc`
   (fuerza el camino GL del compositor en lugar del DMABUF).
2. `~/.config/luakit/userconf.lua`:
   `hardware_acceleration_policy = "always"` + `enable_webgl = true`.
- Resultado: youtube renderiza completo ✓, get.webgl.org muestra el
  cubo WebGL ✓, HTML local ✓ (capturas en `~/mesa-fix/shot-*.jpg`).

### Restos: traps del probing VA (RGB→YUV)

- `libgstva.so` (probing de GStreamer) todavía traea: +15 por escaneo
  (repro: `~/mesa-fix/gst-bisect.sh /usr/lib/gstreamer-1.0/libgstva.so`).
  `libgstopengl` → 0.
- Causa: `vl_compositor_convert_rgb_to_yuv` tiene el MISMO bug de
  destino interlaced que ya se corrigió en `vl_compositor_yuv_deint_full`
  (indexa superficies como progresivas y usa rects de cuadro completo).
  El probing de gst-va convierte RGB→YUV hacia superficies NV12
  interlaced → traps `RT_HEIGHT/WIDTH_OVERRUN` (x=0,y=0, formats 32/37).
- El fix requiere paridad por campo en el shader `fs_rgb_to_yuv` (la
  técnica está en el weave de `vl_compositor_gfx.c`: paridad vía
  `round(tc.y-0.5)` y selector de campo en `tc.w`) o pasar por un buffer
  temporal progresivo + copia por campos (camino ya corregido).
  Pendiente para la próxima sesión.

## Sesión 2026-10-15 — decodificación de vídeo por hardware (en curso)

### Estado del stack de firmware (COMPLETO y verificado)

Dos capas de firmware necesarias para la decodificación VA en GK208:

1. **Firmware FALCON de los motores** (kernel): `nv106_fuc084/085/086`
   (= msvld/mspdec/msppp). Extraídos de NVIDIA 340.108 con
   `extract_firmware.py` (repo `envytools/firmware`) — estaban en
   `~/configuracion/kiss-dotfiles/firmware/nouveau/` con nombres
   antiguos (`nvc0_fuc084…`, md5 idénticos entre familias). Instalados
   en `/lib/firmware/nouveau/` con los nombres nuevos y **embebidos en
   el kernel** con `CONFIG_EXTRA_FIRMWARE` (los initcalls piden el
   firmware ANTES de montar la raíz; el sistema no usa initramfs).
   → el motor msvld ya arranca (antes: "init failed, -19").
2. **Microcódigo por códec** (userspace, lo abre mesa en tiempo de
   ejecución): `vuc-h264-0`, `vuc-mpeg12-0`, `vuc-vc1-0` (symlinks a
   `vuc-vp4-*`). Extraídos de NVIDIA-Linux-x86_64-340.108 con el mismo
   script. Validados contra las comprobaciones del cargador de mesa
   (tamaño tras recorte: h264 0x1870≡0x70, mpeg12 0xbe0≡0xe0,
   vc1 0x1cac≡0xac). Copiados a `/lib/firmware/nouveau/` (sin
   recompilar ni reiniciar).

### Estado de la decodificación (ROTO — bug nuevo)

Con el firmware completo, el decode avanza pero falla en el driver:

- `gst-launch … vah264dec …`: assert `kref` en
  `nouveau_pushbuf_data` (mesa `winsys/nouveau/drm/nouveau.c:1685`) —
  un BO referenciado en el push del decoder no está en la krec del
  canal. (Antes del vuc fallaba antes: assert en `bsp_begin`.)
- `mpv --hwdec=vaapi`: init VA falla → cae a software en silencio.
- `ffmpeg -hwaccel vaapi`: "Failed to transfer data to output frame: -5"
  y el mismo assert kref con `-hwaccel_output_format vaapi`.
- Faults FIFO asociados: `HOST1/HOST2 … reason 02 [PTE]` en 0x1256000
  (direcciones sin mapear) y, en la corrida sin vuc, `MSVLD …
  PRIV_VIOLATION` en 0x12aa000.

### Trabajo a medias (reanudar aquí)

1. El assert `kref` está en `nouveau_pushbuf_data` del winsys de mesa:
   alguien hace push con un BO que no pasó por `PUSH_REFN`. Revisados
   `bo_refs` de `nvc0_video_bsp.c:148` y `nvc0_video_vp.c:81` y la
   asignación de `ref_bo` (`nvc0_video.c:260`) — todo presente. Siguiente:
   identificar qué llamada real dispara el assert (busca los call sites
   de `nouveau_pushbuf_data`/`PUSH_DATAp` en el camino bsp/vp/ppp y el
   `dec->fw_bo`/`bitplane_bo` condicionales) y comparar con el camino
   que sí funciona (los metacomandos).
2. Por qué el init de VA falla en mpv/ffmpeg (síntoma distinto al de
   gst): reproducible con `ffmpeg -hwaccel vaapi -hwaccel_device
   /dev/dri/renderD128 -i ~/mesa-fix/test720.mp4 -f null -`.
3. Luego: el fix RGB→YUV del compositor (sección anterior).

### Comandos útiles

```sh
# repro del pushbuf roto (assert kref):
cd ~/mesa-fix && gst-launch-1.0 filesrc location=test720.mp4 ! qtdemux \
  ! h264parse ! vah264dec ! fakesink
# repro del init fallido de ffmpeg:
ffmpeg -hwaccel vaapi -hwaccel_device /dev/dri/renderD128 -i test720.mp4 -f null -
# extracción de firmware (ya hecho):
cd ~/mesa-fix/nvidia-340 && python3 ~/mesa-fix/extract_firmware.py
# traps por escaneo gst (bug RGB→YUV):
~/mesa-fix/gst-bisect.sh /usr/lib/gstreamer-1.0/libgstva.so
```
