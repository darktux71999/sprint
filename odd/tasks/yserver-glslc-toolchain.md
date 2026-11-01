# yserver-glslc-toolchain — shaderc (glslc) para desbloquear xorg/yserver

Objetivo: proveer `glslc` (paquete `shaderc`) para que `xorg/yserver` compile; recipe nueva `extra/shaderc` con sus dependencias fijadas in-tree, luego intento de `kiss build yserver`.
Rama: `main` (historial lineal, convención del repo).
Entrega: commits granulares en `main` (uno por recipe); sin push/PR (decisión del usuario).
Test runner: `sh -n` pre-vuelo + `kiss build <paquete>`; yserver en hardware real (GPU/KMS) queda fuera de alcance, solo build.

## Specs

S1. Petición original del usuario: "puedes empaquetar yserver para mi distro mi repo en ~/proyectos/sprint y mi gestor de paquetes es /usr/bin/kiss un script posix"

S2. Decisión de alcance del usuario: "Empaquetar shaderc primero" — crear las recetas necesarias y luego intentar compilar yserver.

S3. Bloqueador verificado: `crates/yserver-render/build.rs` exige `glslc` en PATH ("Requires `glslc` (from `vulkan-tools` / shaderc) on PATH. If it's missing, the build fails with a clear error"). Sprint tiene spirv-headers/spirv-tools/vulkan-loader/vulkan-tools pero ni shaderc ni glslang (`kiss search shaderc` → not found; sin glslang en `extra/`).

S4. Diseño shaderc: UN solo recipe `extra/shaderc`, sin recipe glslang separada. shaderc v2026.2 compila sus dependencias desde `third_party/` (gated por `IS_DIRECTORY`, con FATAL_ERROR si faltan); con `SHADERC_SKIP_TESTS=ON` solo necesita glslang + spirv-headers + spirv-tools (effcee/re2/googletest/abseil/tint quedan fuera). Las 3 se fijan a los commits EXACTOS del DEPS de v2026.2 como tarballs de commit (codeload) con checksums b3, colocados vía la columna destino de `sources` en `third_party/<dep>` (patrón existente: `core/git` usa `.../git-manpages-2.55.0.tar.xz man`). Pins: glslang `5ed4003a…` (2026-04-24), spirv-headers `ad9184e7…`, spirv-tools `c1cb30bb…`. `utils/update_build_version.py` es tarball-safe (fallback a `unknown hash, <date>` sin git).

S5. Convenciones del repo a replicar: checksums b3sum `-l 33`, una línea por fuente en orden de `sources`; build POSIX `#!/bin/sh -e` con `export DESTDIR="$1"`; `install` sin `-D`/`-C`/`-T` (BusyBox); sufijo `make` en `depends` = build-only; CC=cc → clang, sin gcc; cmake vía `cmake -B build` + `cmake --build` + `cmake --install` (precedente spirv-tools/headers, vulkan-tools usa además `-G Ninja`); `CMAKE_BUILD_TYPE=Release` (el default upstream es Debug); se desactiva `WERROR` (toolchain distrital) y el copyright-check (lint de desarrollo).

S6. Alcance cerrado: solo el toolchain glslc para yserver. Features tcp-transport/xdmcp de yserver quedan OFF (policy upstream); `/tmp/.X11-unix` (root 1777 en boot) y grupos video/input son runtime, no parte de estas recipes. Sin fuentes bitmap X core en el repo (yserver cae a built-ins).

## Tasks

- T0 · recipe xorg/yserver ya creada (1.8.0, b3 verificado contra tarball real, 14 depends resueltas, `sh -n` OK) · S1 · inline · commit b0edfc5
- T1 · recipe extra/shaderc (4 fuentes fijadas según S4 + build cmake) · S4, S5 · inline · `sh -n` + `kiss build shaderc` OK + instalado + `glslc --version` y smoke `.frag→.spv` OK + manifest CLEAN · commit a56e898
- T2 · intento `kiss build yserver` con glslc ya en PATH · S1, S6 · inline · evidencia observada (éxito o log del fallo) · commit solo si el build pasa; si falla, un resultado Needs your decision

## Log

L1. Petición original del usuario: "puedes empaquetar yserver para mi distro mi repo en ~/proyectos/sprint y mi gestor de paquetes es /usr/bin/kiss un script posix"

L2. Pregunta de alcance y respuesta: "¿Cómo sigo?" → "Empaquetar shaderc primero" (crear lo necesario, luego intentar compilar yserver).

L3. Evidencia de versiones (2026-11-01): shaderc tags v2026.1–v2026.4 (último v2026.4); se fija v2026.2 por tren común con spirv-tools v2026.2 del repo. glslang tags solo esquema vulkan-sdk-1.4.x. spirv-headers en repo = snapshot git (`9999 1`, sin checksums).

L4. Gotcha heredado (searxgo-code-engines L6): KISS_PATH debe apuntar a los directorios de categoría (`core:extra:xorg:python:test`), no a la raíz del repo; `kiss build` funciona sin root. KISS_PATH del sistema ya correcto; rama `main`.

L5. Pivote de diseño (2026-11-01): se elimina la recipe glslang separada. Motivos: kiss `git+` no fija commits (seguiría HEAD, posible deriva vs shaderc v2026.2); en cambio los tarballs de commit codeload sí fijan bytes + checksums. `third_party/CMakeLists.txt` confirma que con SKIP_TESTS solo entran glslang/spirv-headers/spirv-tools. Lanzado build empírico en scratch (`/tmp/opencode/shaderc-scratch`, clang del sistema, Ninja, 16 cores) con los flags candidatos para validar configure+build+lista instalada antes de escribir la recipe.

L6. Resultado scratch (2026-11-01, SCRATCH_OK): configure+build+install pasan con clang. Hallazgos para la recipe: (a) instala en `lib64` → forzar `-DCMAKE_INSTALL_LIBDIR=lib`; (b) arrastra artefactos internos (bins glslang/spirv-*, headers glslang/spirv-tools, libs estáticas + shared de SPIRV-Tools, cmake/ y pc de ambos) → limpiar en `build` quedándose solo con `bin/glslc`, `include/shaderc/`, `lib/libshaderc{,_combined}.a`, `lib/libshaderc_shared.so.1`, `lib/pkgconfig/shaderc*.pc`; (c) top-dirs: `shaderc-2026.2` (sin `v`), `SPIRV-Headers-…`/`SPIRV-Tools-…` (mayúsculas). Checksums b3 (`-l 33`) observados del download real:
- shaderc-v2026.2: `d399b02a0fa2f3bb7d438781a3135ef45fceba6cae449f4a22603a2ec3a5f81396`
- glslang-5ed4003: `3ea91a2ab83e0404da3c404d14e45e41f6d35a4990e6e174bd30450ba9342a2f0a`
- spirv-headers-ad9184e: `b4d975b613f67af0a8fa2c9a14b6679d292bae38a3dcc88683086a671daadef2ba`
- spirv-tools-c1cb30b: `65b349be8aa81ce6bd63f3917e637b4520ae9335d53fb515cf408129b422ccac3a`

L7. T1 verificado (2026-11-01): `kiss build shaderc` OK (473 targets, clang, Ninja) e instalado vía doas (`shaderc@v2026.2-1`). `glslc --version` responde (v2026.2) y compila un `.frag` trivial a `.spv` (smoke OK, 400 bytes). Manifest con 2 restos: `/usr/bin/glslangValidator` (binario real de glslang; el rm solo cubría el symlink `glslang`) y `/usr/lib/cmake/` vacío → fix en `build` (rm + `rmdir` guardado) y rebuild pendiente.

L8. T0+T1 commiteados (2026-11-01): b0edfc5 (xorg/yserver), a56e898 (extra/shaderc). Rebuild shaderc con el fix: manifest CLEAN (solo artefactos shaderc). Siguiente: T2 `kiss build yserver` en segundo plano.

L9. T2 verificado (2026-11-01): `kiss build yserver` OK (cargo release en 2m08s, musl+clang sin parches) e instalado vía doas (`yserver@1.8.0-1`). Manifest = contrato upstream exacto (bin/yserver+starty, 2 man, setup.md/LICENSE/lightdm-example; sin tmpfiles). `yserver --version` → `1.8.0 (v1.8.0) features=[]` (stamping YSERVER_GIT_COMMIT OK). Prueba viva en hardware (KMS/GPU, grupos video/input, `starty` desde consola) queda en manos del usuario.

L10. Diagnóstico display + plan atómico (2026-11-01): `starty` no levanta — `yserver.log` muestra `DRM_CLIENT_CAP_ATOMIC rejected (os error 95)` y fatal `property "FB_ID" not exposed`; sin session.log. GPU real: NVIDIA GK208B (GT 730, 10de:1287, Kepler/NVE0) con nouveau legacy; NVK/Vulkan OK pero KMS atómico es la pieza faltante (kernel-side, no mesa). Upstream: serie de Lyude Paul v6 (2026-08-13) activa atómico por defecto en NV50+ (cubre Kepler), rumbo al 7.3; parámetro `nouveau.atomic` ya existe (hoy en 0; nouveau built-in, `CONFIG_DRM_VKMS=n`). Acciones: `/tmp/.X11-unix` recompuesto a root:root 1777; `~/.xinitrc` mínimo (`exec dwm`, sxrc intacto); grupos video/input ya OK; entrada limine `Kernel-7.2.8-bfq-atomic` (= 7.2.8-bfq + `nouveau.atomic=1`, primera del menú, resto intacto; backup `limine.conf.bak-20261101`). Descartados con motivo: VKMS (virtual, sin salida física), implementar atómico a mano, NVIDIA 470 propietario en musl. Pendiente (usuario): reboot con la entrada nueva, verificar `atomic=1`, `starty`, reportar tail de `yserver.log`.

L11. Atómico verificado + Dvorak (2026-11-01): reboot con `Kernel-7.2.8-bfq-atomic` OK (`/proc/cmdline` trae `nouveau.atomic=1`, sysfs `atomic`=1 vía doas). `starty` levanta dwm desde consola (yserver.log limpio, session.log con sesión viva). `/tmp/.X11-unix` se pierde en cada reboot (tmpfs) → recomponer a root:root 1777. Wrapper personal `~/.local/bin/starty-dvorak` (fuera del repo): exporta `XKB_DEFAULT_*=evdev/pc105/us/dvorak` y agrega `-layout us` del lado servidor (parseo POSIX con rotación, verificado con starty falso en 5 casos).
