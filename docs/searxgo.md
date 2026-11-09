# searxgo — metasearch autohospedado

Recipe `extra/searxgo`: metasearch en un solo binario Go (SearxGo, snapshot git de `Openmentia/SearxGo`; no hay releases upstream, sin checksums del snapshot).

## Motores

Los motores están compilados en el binario (registro en `internal/config/config.go`); el `config.toml` solo activa/desactiva y pone prioridad. Fuentes de los motores:

| motor | endpoint | notas |
|---|---|---|
| duckduckgo | html.duckduckgo.com | prioridad 1 |
| bing | bing.com | prioridad 2 |
| google | google.com/search | desactivado por defecto (CAPTCHAs) |
| reddit | reddit.com/search.json | prioridad 3; necesita UA real (403 anónima es común) |
| wikipedia | wikipedia | compilado, sin sección en el config por defecto |
| github | api.github.com/search | repos + issues; sin token (code search requiere auth) |
| codeberg | codeberg.org/api/v1/repos/search | Forgejo API; best-effort: TTFB 3–10s, a menudo fuera del timeout de 6s |
| sourcegraph | sourcegraph.com/.api/search/stream | SSE; código público; count cap 10 (streams amplios son lentos) |
| gitlab | gitlab.com/api/v4/projects | búsqueda de proyectos |

Los cuatro últimos los agrega `patches/code-engines.patch` (motores en `internal/engines/`, casos en el switch de `internal/config/config.go`, secciones por defecto en `config.toml`).

## Parches propios

- `patches/nojs-html.patch`: `?format=html` devuelve HTML plano sin JS (formulario + enlaces); el JSON por defecto queda intacto.
- `patches/code-engines.patch`: agrega los motores github, codeberg, sourcegraph y gitlab.
- `patches/searxng-compat.patch`: `?format=json` devuelve objeto estilo SearXNG (`{query,number_of_results,results:[{title,url,content,snippet,engine}]}`) para DeepTutor (Search → SearXNG → Base URL). `content` = `snippet`. El frontend propio nunca manda `format=json` (usa `timings=1`), así que no cambia la UI.

Convenciones kiss: los parches se listan en `sources` (ese es el orden de aplicación en `build`) y se verifican con b3sum (`-l 33`) en `checksums`.

## Ejecución

El binario lee `./config.toml` y `./static/` del directorio corriente:

    cd /usr/share/searxgo && /usr/bin/searxgo

Puerto 9000 (`server.port`), búsqueda en `/search?q=<query>&format=json|html&size=<n>`.

DeepTutor: `Settings → Search → SearXNG → Base URL = http://127.0.0.1:9000` (bare metal). Si DeepTutor va en Docker, `http://host.docker.internal:9000`. Sin API key. Verificación: `curl "http://127.0.0.1:9000/search?q=linux&format=json&size=2"` debe traer `results[0].content` no vacío.

## Limitaciones

- SearxGo no indexa nada: agrega consultas en vivo a las APIs; la calidad depende de cada fuente.
- Los motores nuevos sirven la primera página (`page` no implementado), igual que el motor reddit upstream.
- GitHub code search requiere token; el motor usa repos + issues públicos sin auth (~10 req/min anónimos).
- Codeberg: búsqueda de repos solamente (la API pública no expone code search). La búsqueda de Forgejo es lenta servidor-side; el motor degrada graceful (el agregador registra el fallo y sirve los demás motores). Subir `server.timeout` mejora su participación a costa de latencia total.
- Sourcegraph: consultas muy amplias pueden exceder el budget de 6s del agregador aunque el stream vaya llegando; el cap de `count` a 10 corta temprano. Best-effort según la query.
- Reddit (motor upstream) suele dar 403 anónima; es un problema upstream de UA, no de los parches.
