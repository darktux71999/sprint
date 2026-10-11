# Sprint — Distro KISS Linux (musl + LLVM)

Distribución Linux minimalista:
- **musl libc** (sin glibc)
- **LLVM/Clang** como toolchain (sin GCC)
- **BusyBox** como coreutils
- **KISS** como gestor de paquetes

## Estructura

```
sprint/
├── core/       # Sistema base
├── extra/      # Usuario, herramientas, libs
├── xorg/       # X server, drivers, X11
├── test/       # Experimental
├── python/     # Paquetes y librerías Python
└── etc/        # Configuración local del sistema (rc.d)
```

Los lenguajes solo se separan en su propio directorio cuando acumulan
muchas recetas (p. ej. Python, 16). Lua (5) y el resto de lenguajes con
una o dos recetas permanecen en `core/`/`extra/`.

## Paquete

```
paquete/
├── version      # "1.2.3 1" (versión release)
├── sources      # URLs + parches locales (uno por línea)
├── checksums    # Blake3 (b3sum -l 33), NO SHA256
├── depends      # Runtime: "libfoo", Build-only: "cmake make"
├── build        # Script shell ejecutable ($1=DESTDIR, $2=versión)
├── patches/     # Parches opcionales
├── files/       # Archivos auxiliares
└── manifest     # Se genera automáticamente
```

## Formatos clave

**version**: `1.2.3 1` — release se incrementa sin cambio de versión

**sources**:
```
https://ejemplo.com/paquete-1.2.3.tar.gz
patches/fix-musl.patch          # Se copia plano al build dir
```

**depends**:
```
cmake make              # Build-only
openssl                 # Runtime
```

**build**:
```sh
#!/bin/sh -e
export DESTDIR="$1"
patch -p1 < fix-musl.patch
./configure --prefix=/usr
make
make DESTDIR="$1" install
```

## Restricciones

### Toolchain
- `CC=cc` → clang, `CXX=c++` → clang++
- NO gcc/g++, parchear builds que lo fuerzan

### musl
- NO glibc, parches comunes: `fix-musl.patch`, `no-gcc.patch`
- Librerías BSD: `libedit` en vez de `libreadline`

### BusyBox
- `install` sin `-C` ni `-T` de GNU
- `ash` es el shell del sistema

### Checksums
- **Blake3** 33 bytes (66 hex chars)
- `kiss checksum paquete` para regenerar
- Paquetes con fuentes solo git no llevan archivo `checksums`
- **NO SHA256** (rechazado desde 2024)

## KISS_PATH

```sh
export KISS_PATH="$HOME/proyectos/sprint/core"
export KISS_PATH="$KISS_PATH:$HOME/proyectos/sprint/extra"
export KISS_PATH="$KISS_PATH:$HOME/proyectos/sprint/xorg"
export KISS_PATH="$KISS_PATH:$HOME/proyectos/sprint/test"
export KISS_PATH="$KISS_PATH:$HOME/proyectos/sprint/python"
```

Prioridad: izquierda > derecha. `kiss search` sigue el orden.

## Rutas

| Ruta | Descripción |
|------|-------------|
| `/var/db/kiss/installed/` | Paquetes instalados |
| `~/.cache/kiss/sources/` | Fuentes descargadas |
| `~/.cache/kiss/logs/` | Logs de build |
