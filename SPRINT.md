# Sprint — Distro personal KISS Linux (musl + LLVM)

Repositorio de paquetes para una distribución Linux minimalista basada en:
- **Kernel Linux** actual
- **musl libc** (sin glibc)
- **LLVM/Clang** como toolchain (sin GCC)
- **BusyBox** como coreutils
- **KISS** como gestor de paquetes

---

## KISS Package Manager

KISS es un gestor de paquetes minimalista escrito en POSIX shell (~2000 líneas).

### Comandos principales

| Comando | Alias | Descripción |
|---------|-------|-------------|
| `kiss build pkg` | `kiss b pkg` | Compilar paquete(s) |
| `kiss install pkg` | `kiss i pkg` | Instalar paquete(s) |
| `kiss remove pkg` | `kiss r pkg` | Eliminar paquete(s) |
| `kiss download pkg` | `kiss d pkg` | Solo descargar fuentes |
| `kiss checksum pkg` | `kiss c pkg` | Regenerar checksums blake3 |
| `kiss update` | `kiss u` | Actualizar repositorios (git pull) |
| `kiss upgrade` | `kiss U` | Actualizar sistema completo |
| `kiss list` | `kiss l` | Listar paquetes instalados |
| `kiss search pkg` | `kiss s pkg` | Buscar paquete en repos |
| `kiss alternatives` | `kiss a` | Gestionar alternativas |
| `kiss preferred` | `kiss p` | Mostrar dueños de archivos con alternativas |
| `kiss verify` | `kiss v` | Verificar checksums del paquete |
| `kiss version` | | Versión del gestor (actualmente 6.2.0) |

### Variables de entorno

| Variable | Default | Descripción |
|----------|---------|-------------|
| `KISS_PATH` | `/var/db/kiss/installed` | Ruta de repos separados por `:` (izquierda = mayor prioridad) |
| `KISS_ROOT` | `/` | Root del sistema (para chroot) |
| `KISS_PROMPT` | `1` | `0` = no pedir confirmación |
| `KISS_CHOICE` | `0` | `1` = forzar instalación en conflictos |
| `KISS_STRIP` | `1` | `0` = no strippear binarios |
| `KISS_KEEPLOG` | `0` | `1` = conservar logs de build |
| `KISS_HOOK` | vacío | Ruta a hooks separados por `:` |

### Rutas internas

| Ruta | Descripción |
|------|-------------|
| `/var/db/kiss/installed/` | Base de datos de paquetes instalados |
| `~/.cache/kiss/sources/` | Fuentes descargadas (caché) |
| `~/.cache/kiss/logs/` | Logs de builds (se borran si éxito) |
| `~/.cache/kiss/proc/` | Directorios de build temporales |

### Flujo interno de `kiss b pkg`

```
1. pkg_find       → buscar paquete en KISS_PATH
2. pkg_depends    → resolver dependencias recursivamente
3. pkg_source     → descargar fuentes remotas, copiar locales
4. pkg_verify     → verificar blake3 checksums
5. pkg_extract    → extraer tarballs (strips top dir), copiar parches
6. pkg_build      → ejecutar ./build con $1=DESTDIR, $2=versión
7. pkg_tar        → crear tarball con manifest
8. pkg_install    → descomprimir tarball a / (si pedida)
```

### Hooks

Los hooks se ejecutan en puntos específicos del ciclo. Se definen en `KISS_HOOK` (separados por `:`).

```
pre-source     post-source      # antes/después de descargar fuente
pre-extract                     # antes de extraer
pre-build       post-build      # antes/después de build
build-fail                      # cuando build falla
pre-install     post-install    # antes/después de instalar
pre-remove      post-remove     # antes/después de eliminar
pre-update      post-update     # antes/después de upgrade
queue-status                    # progreso de la cola de builds
```

Formato: `hook_event paquete directorio`

Los paquetes individuales pueden tener hooks en su directorio de base de datos instalado (post-install, post-remove).

### Sistema de alternativas

Cuando dos paquetes instalan el mismo archivo, KISS lo detecta y ofrece "alternativas":

```bash
# Ver alternativas disponibles
kiss a

# Cambiar alternativa (ej: cambiar java default)
KISS_CHOICE=1 kiss i openjdk-17-bin
```

Los archivos en conflicto se mueven a `/var/db/kiss/choices/`.

### Fuente de paquetes

La búsqueda de paquetes sigue el orden de `KISS_PATH`:
1. Repositorio izquierda (mayor prioridad)
2. Repositorios siguientes
3. `/var/db/kiss/installed` (último recurso)

```bash
# Ejemplo: sprint tiene prioridad sobre cports
export KISS_PATH="/home/darktux/package-repos/sprint/core:/home/darktux/package-repos/sprint/extra:/home/darktux/package-repos/sprint/xorg"
```

---

## Estructura del repo

```
sprint/
├── core/       # Paquetes esenciales del sistema
├── extra/      # Paquetes de usuario, herramientas, navegadores
├── xorg/       # Paquetes de servidor X, drivers, libs X11
└── test/       # Paquetes experimentales
```

Cada paquete es un directorio con:

```
paquete/
├── version      # "versión release" (ej: "1.2.3 1")
├── sources      # URLs de fuentes, parches (uno por línea)
├── checksums    # Blake3 (b3sum -l 33) de cada fuente/parche
├── depends      # Dependencias (una por línea, "make" para build-only)
├── build        # Script de compilación (shell, ejecutable)
├── patches/     # Parches opcionales (referenciados en sources)
├── files/       # Archivos auxiliares opcionales
├── README       # Descripción opcional
└── manifest     # Lista de archivos instalados (se genera)
```

---

## Formato de archivos

### version
```
1.2.3 1
```
Primera línea: `versión release`. El release se incrementa con cada rebuild sin cambio de versión.

### sources
```
https://ejemplo.com/paquete-1.2.3.tar.gz
patches/fix-musl.patch
patches/no-gcc.patch
```
- URLs remotas se descargan a caché
- Rutas locales (sin `http`) se copian al directorio de build
- Parches se copian **planos** (sin prefijo `patches/`) al directorio de build

### checksums
```
abcdef1234567890abcdef1234567890abcdef1234567890abcdef123456789012
9876fedc...5678
```
Generado con: `kiss checksum paquete`
Usa **Blake3** con longitud 33 bytes (66 hex chars).
Si no existe, KISS salta verificación.
**NO usar SHA256** (KISS lo rechaza desde 2024).

### depends
```
cmake make
openssl
libpng
samurai make
linux-headers make
```
- `make` al final = dependencia solo de build (no runtime)
- Sin `make` = dependencia runtime

### build
```sh
#!/bin/sh -e
# Ejecutable, recibe $1=DESTDIR, $2=versión

export DESTDIR="$1"

# Parches ya están planos en el directorio de build
patch -p1 < fix-musl.patch

./configure --prefix=/usr
make
make DESTDIR="$1" install
```

---

## Convenciones importantes

### Toolchain LLVM/Clang
- `CC=cc` → symlink a `clang`
- `CXX=c++` → symlink a `clang++`
- NO existe `gcc` ni `g++`
- Builds que fuerzan `gcc` deben ser parcheados con `sed`

### musl libc
- NO glibc. Builds que esperan glibc fallan.
- Parches comunes: `fix-musl.patch`, `no-gcc.patch`, `posix.patch`
- `musl-devel` implícito en todo build
- Librerías BSD: `libbsd` o equivalentes como `libedit`

### BusyBox
- `install` no soporta `-C` ni `-T` de GNU coreutils
- Opciones: parchear Makefile, sed en caliente, o `export INSTALL=install`
- `ash` es el shell default del sistema

### Versiones
- **Versiones git**: usar timestamp o hash (ej: `9999` para HEAD)
- **Versiones estándar**: `1.2.3 1`
- **Release**: incrementar si el rebuild sin cambio de versión

### Parches
- Se copian **planos** al build dir (sin prefijo `patches/`)
- En `sources`: `patches/fix-musl.patch` → en build: `fix-musl.patch`
- Aplicar con `patch -p1 < archivo.patch`
- Preferir `sed` para cambios simples de una línea

---

## Repositorios de referencia

### Chimera Linux (cports)
**Ubicación:** `~/package-repos/cports/main/`
**Motor:** Python (template.py)
**Base:** musl + LLVM + FreeBSD userland

```bash
# Buscar versión de un paquete
grep '^pkgver' ~/package-repos/cports/main/paquete/template.py

# Ver dependencias
grep -A20 'makedepends\|hostmakedepends' ~/package-repos/cports/main/paquete/template.py

# Ver fuente
grep 'source' ~/package-repos/cports/main/paquete/template.py
```

**Diferencias clave con cports:**
- cports usa `cbuild` (Python), sprint usa scripts shell
- cports separa `makedepends` (build) y `hostmakedepends` (host tools)
- cports tiene subpaquetes (`-devel`, `-libs`), sprint no
- cports usa `configure_gen = []` para saltar autoconf

### Alpine Linux (aports)
**Ubicación:** `~/package-repos/aports/`
**Motor:** shell (APKBUILD)
**Base:** musl (pero GCC, no LLVM)

```bash
# Ver estructura
ls ~/package-repos/aports/community/paquete/
ls ~/package-repos/aports/main/paquete/

# Buscar en APKBUILD
grep 'depends\|makedepends' ~/package-repos/aports/community/paquete/APKBUILD
```

**Diferencias clave con aports:**
- aports usa GCC, sprint usa Clang
- aports tiene `abuild` como gestor, sprint usa `kiss`
- Parches de aports pueden necesitar adaptación para LLVM

### Gentoo
**Ubicación:** `~/package-repos/gentoo/`
**Motor:** ebuild (bash)
**Base:** GCC + glibc (muy diferente)

```bash
# Buscar paquete
find ~/package-repos/gentoo -maxdepth 2 -name 'paquete' -type d

# Ver ebuild
ls ~/package-repos/gentoo/categoria/paquete/*.ebuild
```

**Diferencias clave con Gentoo:**
- Gentoo usa GCC + glibc, sprint LLVM + musl
- Gentoo tiene USE flags, sprint no
- Gentoo tiene `ebuild`, sprint usa `kiss`
- Útil como referencia de patches y dependencias, no de build logic

---

## Flujo de trabajo: Actualizar paquetes

### 1. Verificar si hay updates disponibles

```bash
# Comparar con cports
for dir in ~/package-repos/sprint/core/*/ ~/package-repos/sprint/extra/*/ ~/package-repos/sprint/xorg/*/; do
    pkg=$(basename "$dir")
    [ -f "$dir/version" ] || continue
    s=$(head -1 "$dir/version" | awk '{print $1}')
    [ -f ~/package-repos/cports/main/$pkg/template.py ] || continue
    c=$(grep '^pkgver' ~/package-repos/cports/main/$pkg/template.py | grep -o '"[^"]*"' | tr -d '"')
    [ -z "$c" ] || [ "$s" = "$c" ] || printf "%-20s sprint=%-10s cports=%-10s\n" "$pkg" "$s" "$c"
done | sort
```

### 2. Actualizar versión y fuentes

```bash
# Editar version
echo "1.2.4 1" > ~/package-repos/sprint/extra/paquete/version

# Editar sources (URL nueva)
sed -i 's/1.2.3/1.2.4/g' ~/package-repos/sprint/extra/paquete/sources

# Regenerar checksums (KISS descarga y calcula)
kiss checksum paquete

# Verificar que checksums tiene contenido
cat ~/package-repos/sprint/extra/paquete/checksums
```

### 3. Compilar y probar

```bash
# Construir
kiss b paquete

# Si falla, revisar log
ls -t /root/.cache/kiss/logs/$(date +%Y-%m-%d)/paquete-* | head -1

# Instalar
kiss i paquete
```

### 4. Commit

```bash
cd ~/package-repos/sprint
git add extra/paquete
git commit -m "upgrade: paquete 1.2.3 -> 1.2.4"
```

---

## Flujo de trabajo: Crear paquete nuevo

### 1. Crear directorio y archivos

```bash
mkdir -p ~/package-repos/sprint/extra/paquete
```

### 2. Crear archivos básicos

```bash
# version
echo "1.0.0 1" > ~/package-repos/sprint/extra/paquete/version

# sources
cat > ~/package-repos/sprint/extra/paquete/sources << 'EOF'
https://ejemplo.com/paquete-1.0.0.tar.gz
EOF

# depends (build-only con "make")
cat > ~/package-repos/sprint/extra/paquete/depends << 'EOF'
cmake make
samurai make
openssl
EOF

# build
cat > ~/package-repos/sprint/extra/paquete/build << 'EOF'
#!/bin/sh -e
export DESTDIR="$1"
./configure --prefix=/usr
make
make DESTDIR="$1" install
EOF

chmod +x ~/package-repos/sprint/extra/paquete/build
```

### 3. Regenerar checksums y probar

```bash
kiss checksum paquete
kiss b paquete
```

### 4. Commit

```bash
cd ~/package-repos/sprint
git add extra/paquete
git commit -m "extra: add paquete package"
```

---

## Paquetes fantasma (provided by another package)

Ejemplo: `clang` es proporcionado por `llvm`. Si un paquete lista `clang` como dependencia, debe eliminarse porque `llvm` ya lo incluye.

```bash
# Buscar dependencias de clang
grep -rl 'clang' ~/package-repos/sprint/*/*/depends

# Eliminar "clang make" o "clang" de los depends encontrados
```

---

## Errores comunes y soluciones

| Error | Causa | Solución |
|-------|-------|----------|
| `install: unrecognized option: C` | BusyBox no soporta `-C` | `sed -i 's/INSTALL ?= install -C/INSTALL ?= install/' Makefile` |
| `gcc: not found` | Builds que fuerzan GCC | Parchear Makefile con `sed 's/= gcc/= $CC/g'` |
| `glibc not found` | Builds que usan glibc internals | Parchear, usar `musl-bsd-headers`, o `musl-devel` |
| `undefined reference to __stack_chk_fail` | SSP no disponible en musl | `-fno-stack-protector` en CFLAGS |
| `unrecognized option '-Wl,--as-needed'` | Linker ld no soporta esa flag | Parchear o quitar de CFLAGS/LDFLAGS |
| `autoconf: not found` | Paquete necesita autotools | Agregar `autoconf make` a depends |
| Blake3 checksum mismatch | Archivo corrupto o URL cambió | `rm ~/.cache/kiss/sources/paquete/* && kiss checksum paquete` |
| Build falla en `make install` | GNU-only flags | Parchear Makefile o `export INSTALL=install` |

---

## Referencias rápidas

```bash
# Buscar paquete en sprint
find ~/package-repos/sprint -maxdepth 3 -type d -name 'paquete'

# Ver qué depende de un paquete
grep -rl 'paquete' ~/package-repos/sprint/*/*/depends

# Ver paquetes instalados
ls /var/db/kiss/installed/

# Verificar integridad de paquete
kiss checksum paquete
kiss v paquete  # verificar fuentes

# Actualizar todo
kiss u  # update

# Reinstalar paquete
kiss b paquete && kiss i paquete

# Cambiar prioridad de repositorios
# KISS_PATH ordena prioridad (izquierda = mayor)
echo $KISS_PATH
```

---

## Repositorio

- **Sprint** (principal): `~/package-repos/sprint/`
- **cports** (Chimera ref): `~/package-repos/cports/main/`
- **aports** (Alpine ref): `~/package-repos/aports/`
- **gentoo** (Gentoo ref): `~/package-repos/gentoo/`

Push: `git push origin main` (SSH: `git@codeberg.org:darktux71999/sprint.git`)

---

## Dotfiles

Respaldo de configuraciones del sistema en `~/kiss-dotfiles/`:
- `fstab` — mount points
- `zram.boot` — zram init hook
- `10-nvme.conf` — sysctl NVMe optimizations
- `as-wrapper` — assembler wrapper for musl/LLVM
- `pkgcd` — fuzzy cd to package dirs across repos
- `pkgfind` — cross-reference packages across repos
- `scr` — screenshot tool (ffmpeg)
- `sprint-fetch` — system info display
- `setwall` — wallpaper setter (xwallpaper)
- `vis/` — vis editor config (noir theme, Hare lexer)
- `sx/sxrc` — X session startup
- `picom/` — compositor config
- `tridactyl/` — browser vi keybinds
- `librewolf-theme/` — userChrome.css + user.js
- `netsurf/` — browser config
- `chat` — LLM chat wrapper
