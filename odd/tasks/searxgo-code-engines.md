# searxgo-code-engines — motores de código (GitHub/Codeberg/Sourcegraph/GitLab) en SearxGo

Objetivo: agregar 4 motores de búsqueda de código/proyectos al SearxGo instalado (GitHub, Codeberg, Sourcegraph, GitLab.com) mediante un segundo parche al snapshot upstream en la recipe `extra/searxgo`, sin tocar los motores existentes (duckduckgo, bing, google, reddit, wikipedia).
Rama: `main` (historial lineal, convención del repo tras la consolidación de ramas).
Entrega: commits granulares en `main`. El rebuild del paquete instalado (cbuild) y la edición de `/usr/share/searxgo/config.toml` requieren root: entrega commands handoff al usuario.
Test runner: `go build ./...` + `go test ./...` sobre el snapshot upstream parcheado en scratch; verificación viva con `curl` contra instancia local en :9000 (formato JSON y `format=html` sin-JS).

## Specs

S1. Petición original del usuario: "podemos hacer que un buscador local como searxgo que tengo instalado indexe en github, codeberg, sourcehunt ... etc aparte de buscar en los ya puestos como duckduckgo , bing , reddit"

S2. Configuración instalada (usuario): "esta parte de la config en /usr/share/searxgo/". Hallazgo: `config.toml` solo activa/desactiva los 5 motores compilados en el binario (switch en `internal/config/config.go` → `LoadEnabledEngines`); agregar `[engines.github]` sin parchear produce "Warning: Unknown engine" y se ignora. Agregar motores exige parche Go.

S3. Motores elegidos por el usuario (respuesta multi-select): "GitHub (repos + issues), Codeberg (Forgejo API), Sourcegraph, GitLab.com".

S4. Supuesto declarado: "sourcehunt" no tiene API pública de búsqueda (ni sourcehunt.net ni SourceHut ofrecen búsqueda general vía API); se interpretó como fuentes de código y Sourcegraph cubre ese hueco. Si el usuario quería SourceHut/sourcehunt.net, queda como extensión futura (no viable sin scraping frágil).

S5. Semántica de los motores nuevos (SearxGo no indexa; consulta APIs en vivo):
- github: `GET api.github.com/search/repositories` + `GET api.github.com/search/issues`, sin token (code search de GitHub requiere auth; queda fuera). Límite unauth ~10 req/min.
- codeberg: `GET codeberg.org/api/v1/repos/search?q=&limit=` (Forgejo, público, responde `{"ok":true,"data":[...]}`).
- sourcegraph: `GET sourcegraph.com/.api/search/stream?q=context:global <query> count:<size>&v=V3`, parser SSE de eventos `matches`.
- gitlab: `GET gitlab.com/api/v4/projects?search=&per_page=`.
- Todos mapean a `en.Result{Title,URL,Snippet,Engine,Favicon}` y respetan `size`; snippet truncado a 300 chars como el motor reddit.

S6. Compatibilidad: cambio puramente aditivo. Un `config.toml` viejo sigue funcionando (las secciones nuevas son opcionales; `enabled=true` en los defaults del recipe). Los 5 motores existentes no se tocan.

S7. Convenciones del repo a replicar: segundo parche en `extra/searxgo/patches/code-engines.patch`, listado en `extra/searxgo/sources` (kiss: parches locales van en sources), aplicado en `extra/searxgo/build` después de `nojs-html.patch`, bump `version` 2026.08.29 2 → 2026.08.29 3, documentación en `docs/searxgo.md`. Precedente: nojs-html.patch.

## Tasks

- T1 · 4 motores Go + casos en el switch de `config.go` + defaults en `config.toml` upstream · S3, S5, S6 · inline · scratch en `/tmp/opencode` (clone upstream + nojs patch + cambios) · `go build`, `go test ./...`, corrida viva con curl JSON + html sin-JS · genera `code-engines.patch` · commit 447aeab
- T2 · recipe: `patches/code-engines.patch`, `sources`, `build`, `version`, `checksums` · S7 · inline · commit 447aeab
- T3 · `docs/searxgo.md`, handoff de instalación (cbuild rebuild, enable en `/usr/share/searxgo/config.toml`, arranque) · S2, S7 · inline · commit b789798

## Log

L1. Petición original del usuario: "podemos hacer que un buscador local como searxgo que tengo instalado indexe en github, codeberg, sourcehunt ... etc aparte de buscar en los ya puestos como duckduckgo , bing , reddit"

L2. Aclaración del usuario sobre la config: "esta parte de la config en /usr/share/searxgo/".

L3. Selección de motores (respuesta del usuario): "GitHub (repos + issues), Codeberg (Forgejo API), Sourcegraph, GitLab.com".

L4. Evidencia de APIs (verificada en vivo 2026-10-25): GitHub repos search 200 JSON con items; Codeberg `{"ok":true,"data":[...]}` 200; Sourcegraph stream SSE con eventos filters/progress/matches; GitLab projects search 200. Go 1.27.2 y cbuild disponibles en el sistema. `/usr/local/bin` y `/usr/bin` no son escribibles por el usuario → la instalación del binario final va por el flujo de paquetes de la distro (cbuild), no por copia manual.

L5. Decisiones de alcance: motor codeberg = búsqueda de repos únicamente (la issue-search de Forgejo es POST y el helper httpx es GET; extensión futura). Motor github = repos + issues (code search requiere token). Sin tests herméticos nuevos (motores dependen de red; precedent upstream no testea motores; la verificación es la corrida viva + `go test ./...` existente).

L6. Descubrimiento de build: el KISS_PATH del sistema apunta a los directorios de categoría (`core:extra:xorg:python:test`), no a la raíz del repo. Con la raíz, kiss trata el paquete como "explicit" y reconstruye desde `/var/db/kiss/installed` (receta vieja, solo nojs). cbuild no funcionó en esta sesión (no puede escribir la delegación de cgroup user en este entorno); `kiss build` directo funciona sin root.

L7. Convención checksums resuelta empíricamente: b3sum `-l 33` (66 hex), una línea por fuente local en orden de `sources`; fuentes `git+` se excluyen de la generación (`${_res##git+*}` queda vacío). El hash guardado 98660cc… es el b3sum de nojs-html.patch (no sha256; por eso un guard sha256 inicial falló). Se agregó el b3sum de code-engines.patch a `checksums`.

L8. Build e instalación validados: `kiss build searxgo` con KISS_PATH correcto encontró ambos parches en la recipe, verificó los dos b3sums, aplicó nojs + code-engines, `go test ./...` ok, tarball `searxgo@2026.08.29-3`, instalado vía doas. `/usr/share/searxgo/config.toml` ya incluye los 4 motores nuevos (enabled=true, priority 4).

L9. Comportamiento de los motores nuevos verificado en vivo (scratch y binario instalado): github 8-12 resultados, gitlab 9-12, sourcegraph 9 (parser SSE funciona), codeberg best-effort (TTFB 3-10s servidor-side; dentro del budget de 6s del agregador contribuye intermitentemente, si no falla graceful con log). Reddit 403 es un problema upstream preexistente (UA bloqueada), fuera de alcance. nojs html intacto.

L10. Sourcegraph con consultas amplias ("searx") no termina dentro del budget de 6s del agregador aunque el stream vaya llegando; se capeó `count` a 10 en el motor (corte temprano del stream). Aun así es best-effort según la query (quickjs sí contribuyó: 2 resultados en corrida con el binario instalado).

L11. Gotcha de parcheado: `git add -A` en el scratch capturó el binario de prueba (`searxgo-test`, 15MB) dentro del parche generado. Regeneración limpia: compilar con `-o` FUERA del tree, borrar el stray, y verificar que `git diff --cached --stat` no contenga líneas "Bin" antes de escribir el parche. Parche final: 396 líneas, 6 archivos, b3sum `ef51c998…` en `checksums`. Rebuild + reinstall de searxgo@2026.08.29-3 validado en vivo: github 12-14 resultados, gitlab 14-16, sourcegraph intermitente según query, codeberg best-effort (timeout graceful), reddit 403 preexistente.
