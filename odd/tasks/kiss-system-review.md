# kiss-system-review

Objetivo: poner al día sprint + sistema KISS (integridad, outdates por severidad, atk, firefox).
Branch: main (local 38a332b, ahead 8 vs origin/github 03bdea7). Delivery: single-push directo a main (forecast <400 líneas). Test runner: kiss (kiss-integrity, kiss-outdated, kiss checksum/build).

## Specs

- S1: repo ~/proyectos/sprint al día — commitear pendientes y subir ramas. Cita: "puedes revisar mi sistema , es un sistema kiss , /usr/bin/kiss y mi repo ~/proyectos/sprint nesecito revisar updates pendientes" + "si" a "¿Quieres que lo haga (commits granulares + push, y revisar el checksum de firefox)?". Aceptación: `git status` limpio salvo excluidos, local == origin/main == github/main tras push.
- S2: firefox 158.0 checksum. Cita: "revisar el checksum de firefox". Aceptación: `kiss checksum firefox` pasa o checksums actualizados con evidencia.
- S3: actualizar referencias antes de outdate. Cita: "antes de hacer una revision con kiss-outdate hacer git pull ala refercias en local es aports y cports". Aceptación: `git -C ~/proyectos/aports pull` y `git -C ~/proyectos/cports pull` ejecutados, HEAD registrado.
- S4: integridad. Cita: "revisar integridad , con kiss-integrity". Aceptación: `kiss-integrity` ejecutado, resultado observado por paquete.
- S5: outdates por severidad. Cita: "con kiss-outdate revisar nuevas updates y separar segun severidad". Nota: binario real es `kiss-outdated` (no `kiss-outdate`). Aceptación: lista de updates separada en severidades con evidencia.
- S6: atk vs at-spi2-core + REMOCIÓN AUTORIZADA. Cita: "en el caso de atk por que se supone que estoy tirando de at-spi2-core que es algo mas moderno a atk entoces quisiera botarlo pero creo que hay cosas que estorban" + "borra atk y reorganiza". Aceptación: `kiss r atk` ejecutado, `pkg-config --exists atk` sigue true vía at-spi2-core, `kiss-integrity` sin errores nuevos.
- S7: organizar home + EJECUCIÓN AUTORIZADA POR FASES. Cita: "la mayoria de cosas estan en ~/proyectos y hay que organizar mi home" + "borra atk y reorganiza". Aceptación: moves por fases con verificación, cero deletes sin confirmación. Herramientas: "rg y fd son mejores que find y grep", "tenemos codegraph por si es nesesario".
- Modelos delegados autorizados por el usuario. Cita: "puedes usar subagentes , mimo-v2.6-flash y deepseek-v4.1-flash de opencodego".

## Tasks

- T1 (S1): sprint commit+push — 4 untracked (aria2 1.37.0, c-ares 1.34.8, ctorrent-dnh 3.3.2, libuv 1.52.1) en commits granulares + push a codeberg/github. Route: inline. Status: done (4 commits a26c226, 461f3a6, dd32c9a, ad01ae0). Push: pending.
- T2 (S2): firefox checksum fix. Route: inline. Status: done (e7499db, c1d0…→e26e…, `kiss c firefox` verificado idempotente). Push: pending.
- T3 (S3): pull aports/cports. Route: inline. Status: done. Evidencia: aports f223d8d0d1a, cports 38675f2df.
- T4 (S4): kiss-integrity. Route: delegated (mimo-v2.6-flash). Status: done. Evidencia: 335 pkgs, 97763 paths, 698 ELF, errors=0, updates=1 (firefox).
- T5 (S5): kiss-outdated por severidad. Route: delegated (deepseek-v4.1-flash). Status: done. Evidencia: 19 genuinos (critical 7, medium 10, low 2); firefox 159.0 ya disponible (decidir 158-fix vs salto).
- T6 (S6): remover atk. Route: inline. Status: done. Evidencia: `kiss r atk` OK vía doas, `kiss l atk` → not found, `pkg-config --exists atk` true vía at-spi2-core 2.62.0, lib soname .26209.1 presente, orphans sin atk.
- T7 (S7): organización home por fases. Route: inline por fases (sin duplicar modelos). Status: done fase 1-2, diferido resto riesgoso. Evidencia: home 40+→17 entradas; movidos docs/html/scripts/bin, OldFirefox, screenshots→data, npx→proyectos/npx-scratch, 9 proyectos→~/proyectos; node_modules era root (doas+chown); diferidos: confs X activas, Downloads 50G (triage), build trees con paths absolutos.

## Log

- L1 (2026-11-01): "puedes revisar mi sistema , es un sistema kiss , /usr/bin/kiss y mi repo ~/proyectos/sprint nesecito revisar updates pendientes"
- L2 (2026-11-01): "si , tambien lo que veas fuera del repositorio revisar si es nesesario en el caso de atk por que se supone que estoy tirando de at-spi2-core que es algo mas moderno a atk entoces quisiera botarlo pero creo que hay cosas que estorban , revisar integridad , con kiss-integrity , con kiss-outdate revisar nuevas updates y separar segun severidad puedes usar subagentes , mimo-v2.6-flash y deepseek-v4.1-flash de opencodego , antes de hacer una revision con kiss-outdate hacer git pull ala refercias en local es aports y cports , la mayoria de cosas estan en ~/proyectos y hay que organizar mi home"
- L3 (2026-11-01): "tenemos codegraph por si es nesesario tambien rg y fd son mejores que find y grep"
- L4 (2026-11-01): "para la proxima evita lanzar tantos subajentes con los mismo modelos un subagente por modelo"
- L5 (2026-11-01): "borra atk y reorganiza , pero upstream es la referencia de cports?"
- Estado inicial verificado: /usr/bin/kiss 6.2.0; KISS_PATH sprint (core:extra:xorg:test:python); `kiss u` Already up to date; local 38a332b ahead 8 vs origin/github 03bdea7; `kiss U` ofrece firefox 157.0.1-1=>158.0-1 bloqueado por checksum mismatch (sin restos en /tmp/kiss); sin repo: atk, xcb-util-cursor, xclip, xdotool; binario real `kiss-outdated` + `kiss-integrity` presentes; aports/cports en master con remotos github alpinelinux/chimera; cports con untracked user/ctorrent-dnh/.
