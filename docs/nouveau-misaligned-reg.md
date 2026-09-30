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

Patch en `~/proyectos/sprint/xorg/mesa/patches/nak-sustga-channel-mask.patch`
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
- Próximo paso A/B: quitar el aumento manual de clock con `hang-watch`
  corriendo; si desaparecen los cuelgues, la causa es el clock manual.
