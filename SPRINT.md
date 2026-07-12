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
# Ejemplo: sprint tiene prioridad, luego repo/kiss-xorg/community como respaldo
export KISS_PATH="/home/darktux/package-repos/sprint/core:/home/darktux/package-repos/sprint/extra:/home/darktux/package-repos/sprint/xorg:/home/darktux/package-repos/repo/core:/home/darktux/package-repos/repo/extra:/home/darktux/package-repos/repo/wayland:/home/darktux/package-repos/kiss-xorg/xorg:/home/darktux/package-repos/kiss-xorg/extra:/home/darktux/package-repos/kiss-xorg/community:/home/darktux/package-repos/community/community"
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

## Sistema de inicio

**PID 1:** `busybox init` (vía baseinit)
**Supervisor de servicios:** `runsvdir` / `runsv` (runit-style)
**Lanzador de sesión X:** `sx` (similar a `startx`, no es parte del init)

### Secuencia de arranque

```
/boot/limine.conf → kernel
init → /etc/inittab
  → ::sysinit:/lib/init/rc.boot    # rc.boot monta fs, devices, fstab, swap
  → ::respawn:runsvdir -P /var/service  # servicios supervisados
  → tty1::respawn:/bin/getty ...   # terminales
```

### /lib/init/rc.boot

El script principal de arranque hace (en orden):
1. Monta pseudo-fs (proc, sys, run, dev, pts, shm)
2. Inicia gestor de dispositivos (mdev)
3. Remount root como ro, fsck, rw
4. `mount -a` (monta todo en /etc/fstab)
5. `swapon -a` (swap activa)
6. Hooks `.boot`: recorre `/etc/rc.d/*.boot`

### Hooks de arranque (.boot)

Se ejecutan en orden alfabético al final de rc.boot.

| Hook | Descripción |
|------|-------------|
| `zram.boot` | Crea zram0 (4G lz4, prio=100) y zram1 (4G zstd, prio=99) vía `zramctl` |
| `keymap.boot` | Carga teclado: `loadkmap < /usr/share/bkeymaps/dvorak/dvorak.bmap` |
| `network.boot` | Configura IP estática en eth0 (192.168.1.12/24) + DNS Cloudflare |

### xlible — forks de X.org

El sistema usa **xlibre** en vez de xorg-server, por ser más activo en desarrollo.

```
xorg/xlibre-server/          # servidor X fork
xorg/xlibre-xf86-input-libinput/  # input driver fork
xorg/xwallpaper/             # wallpaper setter minimal
```

Dependencias: `libdrm`, `mesa`, `libepoxy`, `libxkbcommon`, `pixman`, `libxcvt`

## LLM / AI local (~/models)

### Ubicación de modelos

Todos los `.gguf` se almacenan en `~/models/`. Pesan típicamente 500MB–2GB.

### Script `chat` (~/bin/chat)

Wrapper para interactuar con modelos via llama.cpp.

| Uso | Descripción |
|-----|-------------|
| `chat` | Menú interactivo de modelos |
| `chat vibe` | Filtra modelos que contengan "vibe" |
| `chat -s` | Servidor API (OpenAI-compatible) |
| `chat -s mini` | Servidor con modelo específico |

Opciones internas optimizadas para Xeon E5-2640 v3 (8C/16T, 7.7G RAM):

```
-t 8            # hilos CPU
-c 4096         # contexto
-b 512          # batch size lógico
-ub 256          # batch size físico
-fa auto        # flash attention
--mlock         # evitar swap del modelo
--ctx-checkpoints 16  # checkpoints de contexto
```

### Servidor API

```bash
chat -s    # expone en http://localhost:8080/v1/chat/completions
           # También accesible en red (0.0.0.0:8080)
```

Compatible con OpenAI. En Crush se configura:
```
provider: llama
url: http://localhost:8080/v1
key: none
```

### Paquetes relacionados

```
extra/llama.cpp/       # motor de inferencia (CPU)
extra/libomp/          # OpenMP para aceleración paralela
```

## Docker / containers

El sistema tiene `containerd`, `docker`, `runc`, `iptables`, `nftables` instalados pero NO son parte activa de la distro. Están disponibles si se necesitan, pero no hay builds en sprint (se instalaron desde binarios o paquetes de referencia).

## Formato de patches/ y files/

### patches/
- Se referencian en `sources` como `patches/fix.patch`
- KISS los copia **planos** al directorio de build (sin el prefijo `patches/`)
- Aplicar con `patch -p1 < fix.patch` en el build script
- Usar `|| true` si el parche es opcional

### files/
- Se referencian en `sources` como `files/script.sh destino/relativo`
- El segundo campo indica el directorio destino dentro del build
- Si no hay destino, se copian planos como los patches
- Ejemplo en `yt-dlp/sources`:
  ```
  files/youtube-dl    # se copia a build/
  ```

Ejemplo de build que usa files:
```sh
# En build:
cp youtube-dl "$1/usr/bin/youtube-dl"
chmod +x "$1/usr/bin/youtube-dl"
```

## gitignore y checksums

Los archivos `checksums` vacíos o inexistentes hacen que KISS salte verificación.
Si existen y están desactualizados, el build falla al verificar.
Regenerar con: `kiss checksum paquete`

Los `checksums` NO están en `.gitignore` — se commitean con valores reales generados por `kiss checksum`.

## Prioridad de dependencias (make vs runtime)

En `depends`, una línea sin `make` es dependencia **runtime** (se instala automáticamente con el paquete). Con `make` al final, es solo **build-time** (solo para compilar).

```sh
# depends
openssl              # runtime: openssl debe estar instalado
cmake make           # build-only: solo necesario para compilar
rust make            # build-only: para proyectos Rust
```

KISS resuelve dependencias recursivamente. Si A depende de B y B depende de C, KISS instala C → B → A en ese orden.
- `picom/` — compositor config
- `tridactyl/` — browser vi keybinds
- `librewolf-theme/` — userChrome.css + user.js
- `netsurf/` — browser config
- `chat` — LLM chat wrapper

---

## Style Guide para builds (kisscommunity.org)

Referencia: https://kisscommunity.org/kiss/style-guide/

### GENERAL

- Todo shell code debe pasar `shellcheck`. Falsos positivos deben tener rationale comentado.
- Usar 4 espacios para indentación.
- Líneas máx 80 caracteres.
- Shebang POSIX con `-e` para exit on error (o `-ef` si se requiere word-splitting). Línea en blanco debajo.
- Comentarios: mayúscula inicial, ortografía/gramática correcta, explicar **por qué** no **qué**.
- Sin llaves en variables si no se necesita: `$var` no `${var}`.
- Sin quotes innecesarias: `[ "$var" = test ]` no `[ "$var" = "test" ]`.
- Quotes en strings completos: `"$1/usr/bin/file"` no `"$1"/usr/bin/file`.
- Alinear argumentos en bloques de comandos.
- Preferir `mkdir` + `cp` sobre `install`.
- Preferir `"${CC:-cc}"` sobre `gcc`.
- Siempre `-p` con `mkdir`.
- Siempre `printf`, nunca `echo`.

### BUILD

#### GNU Autotools
```sh
./configure \
    --prefix=/usr \
    --more_args_here

make
make DESTDIR="$1" install
```
Evitar `autogen.sh`/`autoreconf`. Si es inevitable, preferir `autoreconf`.

#### Meson
```sh
export DESTDIR="$1"

meson setup \
    -Dprefix=/usr \
    -Dexample=false \
    output

ninja -C output
ninja -C output install
```

#### CMake
```sh
export DESTDIR="$1"

cmake -B build \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DFLAG=1

cmake --build   build
cmake --install build
```

#### Make
```sh
make
make DESTDIR="$1" PREFIX=/usr install
```
Para muchas variables:
```sh
make \
    PREFIX=/usr \
    SBINDIR=/usr/bin \
    OPT="$CFLAGS"

make \
    DESTDIR="$1" \
    PREFIX=/usr \
    install
```
Para variables que aplican a todos los targets:
```sh
mk() {
    make \
         PREFIX=/usr \
         DESTDIR="$1" \
         EXAMPLE=1 \
         "$@"
}

mk
mk install
```

#### Rust
```sh
cargo build --release
install -Dm755 target/release/rg "$1/usr/bin/rg"
```

#### Go
```sh
export GOPATH="$PWD/go"
export GO111MODULE=on

go build \
    -modcacherw \
    -trimpath

install -Dm755 lazygit "$1/usr/bin/lazygit"
```
Si existe `vendor/`:
```sh
go build -mod=vendor -further-options
```

#### Python
```sh
python setup.py build
python setup.py install --prefix=/usr --root="$1"
```

### DEPENDS

- Si no se necesita dependencia, eliminarla.
- `gcc`, `make`, `musl` se asumen siempre disponibles → eliminarlos de depends.
- Build-only markers con `make` (ej: `cmake make`).
- Runtime deps sin `make`.
- Archivo ordenado alfabéticamente.
- Si está vacío, eliminar el archivo.

### SOURCES

- URLs HTTPS si posible.
- Parches locales, no remotos: `patches/fix.patch` no URL.
- No usar git repo si hay release tarball.
- Quitar `www.` y `.git` de URLs si posible.

### VERSION

- Última versión upstream siempre.
- Usar `git` no `9999` para versiones git.
- Debe contener release: `1.0.0 1` no `1.0.0`.

### PATCHES

```sh
patch -p1 < patch.patch

# Múltiples parches
for patch in *.patch; do
    patch -p1 < "$patch"
done
```
Todos los parches deben usar el mismo strip amount.

---

## KISS Package Manager — features y uso avanzado

Referencia: https://kisscommunity.org/kiss/package-manager/

### Runtime dependency detector

KISS detecta dependencias dinámicas faltantes usando `ldd` sobre los binarios instalados. Si un build system trajo librerías no declaradas en `depends`, KISS las agrega automáticamente.

```
-> libXmu Checking for missing dependencies
--- /home/dylan/conf/cache/kiss/build-4477/depends
+++ depends
@@ -1,3 +1,8 @@
+libX11
+libXau
 libXext
 libXt
+libxcb
 xorg-util-macros make
```

Esto permite que dependencias opcionales funcionen sin declaración explícita.

### Sistema de alternativas dinámico

Cualquier conflicto de archivos entre dos paquetes se convierte automáticamente en una alternativa.

```bash
# Listar alternativas disponibles
kiss a

# Cambiar a GNU grep
kiss a gnugrep /usr/bin/grep

# Cambiar todas las alternativas de un paquete (sbase)
kiss a | grep ^sbase | kiss a -
```

La salida de `kiss a` es directamente usable como entrada para `kiss a`.

### 3-way handshake para /etc/

- Si el usuario modificó el archivo **y** el nuevo paquete trae cambios → se instala como `.new`.
- Si el usuario **no** tocó el archivo → se overwrite automático.
- Si el usuario tocó el archivo **pero** no cambió entre versiones → se salta.

### Gestión de repositorios

`KISS_PATH` funciona como `$PATH` — lista separada por `:` de directorios de repositorios. El orden define prioridad.

```bash
export KISS_PATH="/home/darktux/package-repos/sprint/core:/home/darktux/package-repos/sprint/extra"
```

#### Prevenir actualizaciones de un paquete

```bash
mkdir -p no_updates
cp -r /var/db/kiss/installed/PKG_NAME no_updates/
export KISS_PATH=/path/to/no_updates:$KISS_PATH
```

#### Bypass KISS_PATH (uso CRUX-like)

```bash
cd /path/to/repo/pkg
kiss b   # usa el directorio actual como repo
kiss i
```

### Hooks — ejemplos

#### Logging de duración de build
```sh
PKG="$2"

case $1 in
    pre-build)
        cat /proc/uptime > "${KISS_TMPDIR:-/tmp}/_kiss_start"
    ;;

    post-build)
        IFS=. read -r _start _ < "${KISS_TMPDIR:-/tmp}/_kiss_start"
        IFS=. read -r _end _ < /proc/uptime
        rm -f "${KISS_TMPDIR:-/tmp}/_kiss_start"

        (
            _s=$((_end - _start))
            _h=$((_s / 60 / 60 % 24))
            _m=$((_s / 60 % 60))
            [ "$_h" = 0 ] || _u="${_u}${_h}h "
            [ "$_m" = 0 ] || _u="${_u}${_m}m "
            printf "-> %s %s\n" "$PKG" "Build finished in ${_u:-${_s}s}"
        )
    ;;
esac
```

#### Terminal title con progreso
```sh
case $1 in
    queue-status|queue)
        [ -t 2 ] && {
            printf '\033]0;kiss: %s (%d/%d)\a' \
                "$2" "${3:-?}" "${4:-?}" >&2
        }
    ;;
esac
```

#### Drop to shell on build fail
```sh
case $1 in
    build-fail)
        printf "-> %s %s\a\n" "$2" "Dropped into shell"
        sh >/dev/tty
    ;;
esac
```

### Tips

- **GNU grep**: cambiar busybox grep por GNU grep da aceleración significativa: `kiss b gnugrep && kiss i gnugrep && kiss a gnugrep /usr/bin/grep`.
- **Shallow clone**: KISS hace shallow clone por defecto. Para submodules, agregar `git submodule update --init` al build.

---

## Paquetes nuevos: webkit2gtk + dependencias faltantes


Se agregaron 14 paquetes a `extra/` para autosuficiencia de sprint:

| Paquete | Versión | Descripción |
|---------|---------|-------------|
| `libwpe` | 1.16.3 | Librería base para WPE WebKit |
| `wpebackend-fdo` | 1.16.1 | Backend FreeDesktop.org para WPE |
| `unifdef` | 2.12 | Preprocesador de condicionales C (build-time) |
| `harfbuzz-icu` | 14.2.0 | ICU bindings para harfbuzz |
| `icu` | 74.2 | Internacionalización Unicode |
| `libgcrypt` | 1.12.2 | Criptografía |
| `libgpg-error` | — | Códigos de error para libgcrypt |
| `libsoup3` | 3.4.4 | Cliente HTTP para GLib |
| `glib-networking` | 2.80.1 | TLS/network para GLib |
| `libnghttp2` | — | HTTP/2 |
| `libpsl` | — | Public Suffix List |
| `libtasn1` | 4.21.0 | ASN.1 |
| `libxslt` | 1.1.45 | XSLT |
| `ruby` | 3.1.2 | Lenguaje de scripting (build-time) |

**Nota:** webkit2gtk 2.48.x NO requiere libwpe ni wpebackend-fdo.
Usa el renderer DMA-BUF que funciona sobre X11 y Wayland.

### webkit2gtk — build inteligente

Las features opcionales se detectan automáticamente via `pkg-config`:
si el paquete está instalado, la feature se habilita; si no, se desactiva.
Esto permite activar funcionalidad sin editar el build script.

| Feature | Detecta vía pkg-config | Dependencia |
|---------|----------------------|-------------|
| Video/Audio | `gstreamer-1.0` | gstreamer + plugins |
| WebRTC | `gst-webrtc-1.0` | gstreamer webrtc |
| Spellcheck | `enchant2` | enchant2 |
| Geolocalización | `geoclue-2.0` | geoclue |
| Gamepad | `libmanette-0.2` | libmanette |
| Síntesis voz | `flite` | flite |
| WebGL | `glesv2` | mesa (gles) |
| Sandbox | `bubblewrap` | bubblewrap, libseccomp, xdg-dbus-proxy |
| Keyring | `libsecret-1` | libsecret |
| AVIF | `libavif` | libavif |
| JPEG XL | `libjxl` | libjxl |
| CMS | `lcms2` | lcms2 |
| WOFF2 | `libwoff2dec` | woff2 |
| Hiphenación | `hyphen` | hyphen |

**Siempre desactivados:** MiniBrowser, WebDriver, WebGPU, WebXR, Documentación,
Introspection, Journald, Sampling Profiler (no afectan runtime).

**Toolchain:** LLVM/Clang con LTO thin, `-fuse-ld=lld`, debug reducidos (`-g1`).

### Orden de construcción (todo en sprint)

```bash
# Construir cadena de dependencias
kiss b icu && kiss i icu
kiss b libgpg-error && kiss i libgpg-error
kiss b libgcrypt && kiss i libgcrypt
kiss b libtasn1 && kiss i libtasn1
kiss b libnghttp2 && kiss i libnghttp2
kiss b libpsl && kiss i libpsl
kiss b glib-networking && kiss i glib-networking
kiss b libsoup3 && kiss i libsoup3
kiss b libxslt && kiss i libxslt
kiss b ruby && kiss i ruby
kiss b unifdef && kiss i unifdef
kiss b harfbuzz-icu && kiss i harfbuzz-icu

# webkit2gtk (~18GB disco, <1 hora en Xeon E5-2640 v3 con -j4)
# Usar -j4 para evitar OOM (LTO thin consume mucha RAM por job)
kiss b webkit2gtk && kiss i webkit2gtk
```