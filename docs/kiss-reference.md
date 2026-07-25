# KISS Reference

## Comandos

| Comando | Alias | Descripción |
|---------|-------|-------------|
| `kiss build pkg` | `kiss b pkg` | Compilar |
| `kiss install pkg` | `kiss i pkg` | Instalar |
| `kiss remove pkg` | `kiss r pkg` | Eliminar |
| `kiss download pkg` | `kiss d pkg` | Solo descargar |
| `kiss checksum pkg` | `kiss c pkg` | Regenerar blake3 |
| `kiss update` | `kiss u` | Git pull repos |
| `kiss upgrade` | `kiss U` | Upgrade sistema |
| `kiss list` | `kiss l` | Listar instalados |
| `kiss search pkg` | `kiss s pkg` | Buscar en repos |
| `kiss alternatives` | `kiss a` | Alternativas |
| `kiss verify` | `kiss v` | Verificar checksums |

## Variables

| Variable | Default | Descripción |
|----------|---------|-------------|
| `KISS_PATH` | `/var/db/kiss/installed` | Repos separados por `:` |
| `KISS_ROOT` | `/` | Root del sistema |
| `KISS_PROMPT` | `1` | `0` = no pedir confirmación |
| `KISS_CHOICE` | `0` | `1` = forzar en conflictos |
| `KISS_STRIP` | `1` | `0` = no strippear |
| `KISS_KEEPLOG` | `0` | `1` = conservar logs |
| `KISS_HOOK` | vacío | Rutas a hooks |

## Flujo interno kiss b

```
1. pkg_find       → buscar en KISS_PATH
2. pkg_depends    → resolver dependencias
3. pkg_source     → descargar fuentes
4. pkg_verify     → verificar blake3
5. pkg_extract    → extraer tarballs, copiar parches
6. pkg_build      → ejecutar ./build
7. pkg_tar        → crear tarball
8. pkg_install    → descomprimir a /
```

## Hooks

```
pre-source    post-source
pre-extract
pre-build     post-build
build-fail
pre-install   post-install
pre-remove    post-remove
pre-update    post-update
queue-status
```

Formato: `hook_event paquete directorio`

## Alternativas

```bash
kiss a                                  # Ver alternativas
KISS_CHOICE=1 kiss i openjdk-17-bin     # Cambiar default
```

Archivos en conflicto → `/var/db/kiss/choices/`
