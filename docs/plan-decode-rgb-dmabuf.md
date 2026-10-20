# Plan de ataque — decode VA, RGB→YUV y dma_buf WebKit→nouveau

Sesión 2026-10-15/16. Continúa `nouveau-misaligned-reg.md` (sección final).
Cada problema se ataca por separado, con repro propio, tareas atómicas
ordenadas y verificación explícita.

## Hechos confirmados hoy (2026-10-16)

- `chipset_probe.c` (nuevo, `~/mesa-fix/`): GK208B → **chipset 0x106 (262)**,
  fb 2 GB, `vm_vram_base 0`.
- Repro decode: `gst-launch … vah264dec ! fakesink` →
  `nouveau: kernel rejected pushbuf: No such device` (**ENODEV**, ch6=BSP)
  y después `Assertion failed: kref (nouveau_pushbuf_data:1685)`.
- El krec del push rechazado está COMPLETO (pushbo 32 KB + bsp_bo 1 MB +
  inter_bo 4 MB) → las refs del BSP no son el problema.
- dmesg: faults FIFO `[PTE]` READ en 0x1256000 (HOST1, ch7) y 0x128a000
  (HOST2, ch8); `MSVLD … PRIV_VIOLATION` en 0x12aa000 (ch6) → canales
  muertos ("errored - disabling channel") → kicks siguientes = ENODEV.
- El assert `kref` es **consecuente**: tras un submit fallido,
  `pushbuf_flush` limpia los kref pero `nvpb->bo` sigue activo; la
  siguiente recursión de `nouveau_pushbuf_data` encuentra kref NULL.
  (El mismo assert aparece flaky en CI upstream: nouveau-gk20a-skips.txt.)
- **Hallazgo clave**: `nvc0_video.c:241` sólo carga el vuc si
  `chipset < 0xd0`. Con chipset=0x106 la condición es FALSA →
  `fw_bo = NULL`, `ucode_addr = 0`, `fw_sizes = 0` empujados al VP.
  `firmware_present()` trata a GK208 como "vp5" (soportado sin vuc).
  El blob NVIDIA 340 sí carga `vuc-*` en este chip ⇒ hipótesis A fuerte:
  los engines corren sin microcódigo de códec → accesos a direcciones
  basura (PTE/PRIV_VIOLATION) → canales muertos → ENODEV/assert.

## Problema 1 — decodificación VA (ENODEV, assert kref, faults FIFO)

Repro:
```sh
cd ~/mesa-fix && gst-launch-1.0 filesrc location=test720.mp4 ! qtdemux \
  ! h264parse ! vah264dec ! fakesink
ffmpeg -hwaccel vaapi -hwaccel_device /dev/dri/renderD128 \
  -i test720.mp4 -f null -
```

| # | Tarea atómica | Resultado esperado |
| --- | --- | --- |
| B1 | Parche de traza del winsys (`nouveau-pushbuf-trace.patch`, env `NOUVEAU_LIBDRM_TRACE=1`): log de kicks por canal con ret, y caller del assert vía `__builtin_return_address`. | Identifica si el primer fallo es ENODEV→assert o un push sin kref propio. |
| B2 | Correr el repro con el build instrumentado (`LIBVA_DRIVERS_PATH=build-full/.../dri`), capturar traza + dmesg delta. | Cadena causal completa por canal (6/7/8) y primer error. |
| B3 | Fix del gating de firmware: cargar vuc para GK208 (chipset 0x106 con engine VP4 real), alineando `nvc0_video.c` con `vp4_getpath`; dejar `firmware_present()` coherente. Parche `0004-nvc0-video-fw-gk208.patch`. | fw_bo!=NULL, ucode_addr/fw_sizes correctos. |
| B4 | Verificación decode: gst N frames sin assert ni faults; `ffmpeg -hwaccel vaapi -hwaccel_output_format vaapi` completa; mpv hwdec init OK. | dmesg sin faults nuevos; salida VAAPI usable. |
| B5 | Verificación de contenido: frame VA vs software (checksum/PSNR con ffmpeg `psnr`). | Imagen decodificada correcta, no solo "no crashea". |
| B6 | Si persiste: revisar engine de los canales VP/PPP (ch7/ch8 caen en HOST1/HOST2 según dmesg; comparar `nve0_fifo.engine` con lo que el kernel asigna) y addresses `bo->offset` frente a mappings. | Hipótesis descartada o confirmada con dato. |

## Problema 2 — RGB→YUV interlaced (libgstva, traps RT_*_OVERRUN)

Repro:
```sh
~/mesa-fix/gst-bisect.sh /usr/lib/gstreamer-1.0/libgstva.so   # +15 traps
```

| # | Tarea atómica | Resultado esperado |
| --- | --- | --- |
| C1 | `va_rgb_test.c` (patrón de `va_probe.c`): RGB→NV12 interlaced vía `vl_compositor_convert_rgb_to_yuv` (vaPutImage), verificación de contenido por campos. | Repro mínima localizada + baseline corrupta. |
| C2 | Parche `0006-vl-compositor-rgb-to-yuv-interlaced.patch`: en `vl_compositor_convert_rgb_to_yuv`, si `dst->interlaced` renderizar por plano×campo (`dst_surfaces[plane*2+field]`), rect de destino a media altura por campo y corrección de paridad ±media línea sobre `layer->src` (misma técnica que `0005-vl-compositor-interlaced-dst.patch`). El shader `fs_rgb_yuv` NO necesita cambios: sólo muestrea `tc`. | Sin traps; campos correctos. |
| C3 | Verificación: `va_rgb_test` byte-perfecto por campos; `va_probe` y `va_clear_test` sin regresión; `gst-bisect.sh libgstva.so` → delta 0. | Probing de GStreamer limpio. |

## Problema 3 — dma_buf WebKit → nouveau (crash/ negro)

Situación: workaround activo `WEBKIT_DISABLE_DMABUF_RENDERER=1` en
`~/.config/sx/sxrc`. Objetivo: encontrar la capa rota y eliminar el
workaround (o documentar el fix necesario).

| # | Tarea atómica | Resultado esperado |
| --- | --- | --- |
| D1 | `dmabuf_probe.c`: camino exacto WebKit (gbm_bo con modifier de nouveau → dma-buf fd → `EGL_EXT_image_dma_buf_import_modifiers` → render/sample GL → readback), matriz fourcc×modifier (LINEAR vs BLOCK_LINEAR_GM208), con y sin fence/implicit sync. | Informe de qué paso falla (alloc, import, sample, present, sync). |
| D2 | Correr luakit sin el workaround sobre `test-page.html`/youtube con `WEBKIT_DEBUG` y capturas; comparar contra el camino GL (funciona). | Síntoma reproducido y capa culpable acotada. |
| D3 | Según D1/D2: fix (mesa EGL import/export modifiers, glamor/xlibre DRI3) o workaround documentado alternativo; actualizar `docs/progress.md` y registry. | Decisión con evidencia. |

## Orden de ejecución

A (observabilidad) → B (decode) → C (RGB→YUV) → D (dma_buf).
A = herramientas ya creadas hoy (`chipset_probe.c`) + traza del winsys (B1).
C es independiente de B (se puede intercalar si B queda bloqueado en
datos de kernel).

## Reglas de las corridas

- Corridas cortas (≤25 s, ~10 frames) y `dmesg` delta por corrida; el
  histórico muestra que las tormentas de traps congelan X.
- No tocar partidas/firmware del sistema salvo por la receta kiss.
- Todo fix va como parche en `~/proyectos/sprint/xorg/mesa/patches/`
  + copia en `~/mesa-fix/`, con repro y verificación registradas aquí.

## Resultados 2026-10-19 — B1 artefacto, B3 fix, B4 parcial

- **B1**: artefacto materializado `~/mesa-fix/nouveau-pushbuf-trace.patch`
  (traza winsys `nouveau.c` + print `NOUVEAU_VP3_TRACE` de `nvc0_video.c`;
  8 hunks, solo instrumentación, fuera de la receta).
- **B3**: fix aplicado + parche `0004-nvc0-video-fw-gk208.patch` (receta +
  `~/mesa-fix/`). Dos puntos: `nvc0_video.c` carga vuc también en GK208
  (`chipset == 0x106`); `firmware_present()` excluye 0x106 de `vp5` → exige
  el vuc vía `vp4_getpath` en vez del atajo "sin firmware". Receta al día:
  5 fuentes, checksums en BLAKE3-33 (`b3sum -l 33`, formato de este kiss),
  release `26.2.4 2`.
- **Verificación B3** (repro canónico, `timeout 25`, dmesg delta):
  `VP3 decoder: chipset=0x106 codec=3 fw_bo=yes fw_sizes=0x3701500`
  → 0x370+0x1500 = 0x1870 = tamaño del vuc-h264 validado. **Criterio
  cumplido** (antes: `fw_bo=NO fw_sizes=0x0`).
- **B4 parcial**: el primer round de submits del decoder (BSP/VP/PPP =
  ch11/12/13) ahora pasa `ret=0` (antes fallaba antes). El fallo se mueve a
  la 2ª ronda: `MSVLD PRIV_VIOLATION READ @0x12aa000 ch11 (BSP)` → canal
  muerto → 2º push ch11 → ENODEV → assert `kref` (consecuente). Además
  `HOST2 PTE READ @0x128a000 ch13 (PPP)`. Desaparece el fault de 0x1256000
  (HOST1). Los 15× `RT_HEIGHT_OVERRUN` + 39× `VIEWPORT_ID_NEEDS_GP` del
  delta son del plugin-scan de GStreamer = Problema 2 (RGB→YUV), no decode.
- **Siguiente (B6)**: VP/PPP cayendo en HOST2 y el `PRIV_VIOLATION` de MSVLD
  @0x12aa000 — comparar `nve0_fifo.engine` con la asignación del kernel y
  `bo->offset` frente a mappings.
- **Verificación independiente (2026-10-19, `gentle-ai-verify`)**: sin
  bloqueantes. Aplicación limpia en scratch (patch -p1, sin fuzz), tabla de
  colateral confirma que SOLO cambia comportamiento de 0x106, y `fw_sizes`
  recalculado desde el firmware instalado (6400 B → recorte 0x1870 →
  `(0x370<<16)|0x1500 = 0x3701500`) ✓. Advisories previos: `get_video_param`
  aún anuncia caps VP5 (4032×4080) en GK208; el hermano 0x108 (GK208) y otros
  Kepler >= 0xd0 conservan el gating antiguo (fuera del alcance de B3).
  Tests de regresión: `~/mesa-fix/b3-gk208-fw-gating.sh` (estático; FAIL en
  baseline, PASS parchado) y `~/mesa-fix/b3-gk208-hw-probe.sh` (hardware).

## Resultados 2026-10-19 (sesión C) — RGB→YUV interlaced

- **C1** — `~/mesa-fix/va_rgb_test.c`: repro mínima. Nota de camino: en mesa
  26.2.4 `convert_rgb_to_yuv` solo se invoca desde el VPP con recurso RGB
  (`vl_compositor_proc.c`), así que el test sube el RGB con `vaPutImage` y
  dispara la conversión con VPP RGB→NV12 interlaced. Patrón de paridad plana
  (gris 32 filas pares / 224 impares, croma neutro) → verificación
  independiente de la matriz de color. **Baseline**: luma_malas=240/240
  (campo 0 = basura 0/255, campo 1 = rango 0..130), sin traps.
- **C2** — `0006-vl-compositor-rgb-to-yuv-interlaced.patch` (receta + mesa-fix),
  2 fixes del mismo camino:
  1. `vl_compositor.c:convert_rgb_to_yuv`: rama `dst->interlaced` por
     plano×campo (`dst_surfaces[plane*2+field]`), rect a media altura por
     campo y corrección de paridad ±media línea sobre `layer->src` (misma
     técnica que `0005-vl-compositor-interlaced-dst.patch`; el shader no cambia).
  2. **Hallazgo nuevo**: la rama "RGB to YUV" de `vl_compositor_proc.c` solo
     rellenaba `cstate.rgb2yuv` (camino *compute*); el camino GFX (nouveau)
     alimenta `fs_rgb_yuv` desde `cstate.csc_matrix`, que quedaba sin setear
     → el shader recibía la matriz de DECODE YUV→RGB (observado:
     f(32)=0, f(224)=255 = `1.164v+1.596v-0.874` saturado). Ahora se rellena
     `csc_matrix` igual que en las ramas hermanas RGB→RGB y YUV→RGB.
- **C3** — `va_rgb_test` **PASS** (luma_malas=0/240, croma_malas=0/120,
  mezcla_campos=0, traps delta=0) en 320x240, 640x480, 720x480, 1280x720,
  1920x1080, 176x144 y 352x288; contenido exacto BT.601 limitado
  (Y=43/208, croma=128). `va_probe` y `va_clear_test` PASS (sin regresión).
- **C3 parcial — el resto está identificado**: `gst-bisect.sh libgstva.so`
  sigue en +15, pero YA NO es la conversión RGB→YUV. El trace de
  `nvc0_clear_render_target` (env `VA_TRACE_OPS=1`, instrumentación temporal
  del árbol) muestra que el probe de GStreamer hace 99 clears de **sondeo de
  formatos RT** (64×64/32×16: R8×48, R8G8×18, R16×6, R16G16×6, y ×3 cada
  uno RGBA/BGRA/BGRX/RGBX/B10G10R10A2/422) y 15 de esos clears trapean
  `RT_HEIGHT_OVERRUN` (HW format 32/37). Bug nuevo y separado: el clear
  genérico de esos planos/formatos. Siguiente: identificar el fourcc exacto
  (loop estilo `va_clear_test` por fourcc) y arreglar
  `nvc0_clear_render_target` para esos formatos.

## Resultados 2026-10-19 (sesión clear) — clear de superficies multi-plano

- **Atribución**: `~/mesa-fix/va_fmt_test.c` (loop fourcc×tamaño) reproduce
  el bug fuera del probe: **YV12/I420 +1 trap en todos los tamaños y P010
  +1 salvo 32×16**; NV12/Y800/YUY2/UYVY/RGB limpios. Los trapeadores son los
  planos R8/R16 **genéricos** (no los video-tiled).
- **Causa raíz**: `nvc0_clear_render_target` programa `RT_HORIZ/VERT` con
  `sf->width`/`sf->height` (extras de `nv50_surface`), pero las superficies
  de `vl_video_buffer` se rellenan a mano sin pasar por `create_surface` →
  los extras son basura (el trace los muestra como `sf=81x0`, ¡el enum del
  formato del vecino del array!). Igual clase de bug que el fix #3 de
  `nvc0-clear-video-tiles` (depth/offset), que no cubrió width/height.
  Y800 "limpio" = basura a ceros por suerte; P010 32x16 igual.
- **Fix**: `0003-nvc0-clear-rt-level-dims.patch` (receta + mesa-fix) — las
  dimensiones se derivan del nivel real (`u_minify(width0, level)` con el
  shift MS como hace `create_surface`) en los dos caminos (tiled y lineal).
  Orden de serie: justo tras `0002-nvc0-clear-video-tiles.patch` (su contexto
  solo existe tras ese parche). Release `26.2.4 3`, checksums 7/7 en BLAKE3.
- **Verificación**: `va_fmt_test` 12/12 casos limpios (los 3 fourcc que
  trapeaban); **`gst-bisect.sh libgstva.so` → 0** (¡Probing de GStreamer
  limpio!); regresiones PASS: `va_rgb_test` 7 resoluciones, `va_probe`,
  `va_clear_test`. Serie de parches 7/7 aplican con 0 rechazos en scratch.

## Resultados 2026-10-19 (sesión B6) — causa raíz del fallo de decode

- **Hipótesis del plan descartada**: el mapeo canal→engine de los tres
  canales VP3 (BSP/VP/PPP) es correcto. Cadena verificada: mesa
  `nvc0_video.c:145-150` pasa `NVE0_FIFO_ENGINE_BSP/VP/PPP`
  (0x08/0x02/0x04) → libdrm `nouveau/abi16.c:87-89` pone
  `fb_ctxdma_handle=~0` + `tt_ctxdma_handle=engine` → kernel
  `nouveau_abi16.c:395-410` mapea BSP→MSVLD, VP→MSPDEC, PPP→MSPPP.
  Los valores UAPI coinciden byte a byte entre libdrm y el uapi del kernel,
  y el kernel solo honra el engine si `fb_ctxdma_handle == ~0` (libdrm lo
  pone porque mesa pasa `sizeof(struct nve0_fifo)`).
- **Los faults HOST1/HOST2 son consecuencias, no la causa**: cada canal de
  vídeo tiene su unidad HOST (GPFIFO) y el fault ocurre al traer su
  pushbuf de 32 KB: ch11→0x1222000, ch12→0x1256000, ch13→0x128a000 (stride
  0x34000, determinista). El BO del assert `kref` (0x1256000) es el pushbuf
  del canal VP. El único fault raíz es `MSVLD PRIV_VIOLATION READ
  @0x12aa000` en el canal BSP; ninguna dirección empujada por mesa
  (bsp_bo/inter_bo/ref_bo/fw_bo) coincide con 0x12aa000.
- **Causa raíz: bug del KERNEL, no de mesa**. El commit upstream
  `8ab849d6dd4c` ("drm/nouveau/fifo: add new engine context handling") hace
  que `gk104_ectx_ctor()` mapee el contexto de engine con `.priv = 1` para
  todos los engines. Los motores legacy MSVLD/MSPDEC/MSPPP acceden a su
  contexto con peticiones MMU **no privilegiadas** → `PRIV_VIOLATION` →
  canal muerto. El `0x12aa000` fijo = bloque de contexto (inst) del engine.
  Fix upstream: serie "drm/nouveau: fix GK107 VDPAU regressions"
  (Risto Pajula, 2026-09-13), parche 1/2 = limpiar `priv` para
  MSPDEC/MSPPP/MSVLD.
- **Parche 2/2 aplicado también**: "use global nonstall event on legacy
  FIFO" — el fence de DRM (`nouveau_fence.c:198`) registra el evento
  nonstall con `runl->id`, pero en FIFO legacy el handler señaliza el
  índice 0 → el fence nunca se completa (colateral del mismo bug).
- **Dónde vive el parche**: el kernel no tiene receta en el sprint (solo
  `linux-headers`); se compila en `/usr/src/linux-7.2.8` (árbol que generó
  el kernel en ejecución: su `bzImage` coincide en tamaño con
  `vmlinuz-7.2.8-bfq` de la ESP) y se instala copiando `bzImage` +
  `System.map` a la ESP (`sda1`) que arranca Limine (entrada por defecto
  `Kernel-7.2.8-bfq` → `vmlinuz-7.2.8-bfq`). Parches en
  `~/configuracion/kiss-dotfiles/kernel/patches/` (repo dotfiles, junto al
  `kernel/config`) + copia en `~/mesa-fix/`.
- **Estado**: ambos parches aplicados limpios al árbol (blob ids idénticos
  a upstream `5655eda..bbeb33c`), kernel recompilado e instalado en la ESP
  con backup. **Pendiente**: reiniciar (nouveau es built-in,
  `CONFIG_DRM_NOUVEAU=y`) y re-verificar el repro; el fix de mesa B3 (vuc
  en 0x106) sigue siendo necesario para el microcódec de códec.

## Corrección 2026-10-19 — orden de aplicación de parches en la receta

- **Síntoma**: `kiss build mesa` abortaba en `0003-nvc0-clear-rt-level-dims.patch`
  (“Hunk 1 FAILED 314/314”) → el build nunca llegó a compilar mesa.
- **Causa**: `kiss` **aplana** a la raíz del build dir los ficheros de parche
  listados en `sources` (los copia, no preserva el subdirectorio) y la receta
  los aplica con un glob `*.patch` → **orden alfabético**, no el orden de
  `sources`. `0003-nvc0-clear-rt-level-dims.patch` depende del contexto que
  crea `0002-nvc0-clear-video-tiles.patch` → aplicado antes, falla.
- **Fix**: prefijos numéricos en los nombres (convención de `core/llvm`,
  `core/musl`, `core/unzip`) para que orden alfabético == orden funcional, y
  `sources` listando la serie en ese mismo orden. Verificado simulando el
  `build` completo sobre el tarball prístino: **6/6 parches aplican con 0
  rechazos y 0 residuos (.rej/.orig)**.
- **Checksums**: `kiss checksum mesa` regenera un fichero **idéntico** al
  anterior (los hashes son posicionales, siguen el orden de `sources`; el
  renombrado no cambia el contenido) ✓.
