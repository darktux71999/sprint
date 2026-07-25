# Repositorios de referencia

## Chimera Linux (cports)

- **Ubicación:** `~/package-repos/cports/main/`
- **Base:** musl + LLVM + FreeBSD userland (más cercano a sprint)

```bash
grep '^pkgver' ~/package-repos/cports/main/paquete/template.py
grep -A20 'makedepends\|hostmakedepends' ~/package-repos/cports/main/paquete/template.py
grep 'source' ~/package-repos/cports/main/paquete/template.py
```

Diferencias: cports usa `cbuild` (Python), tiene subpaquetes (`-devel`, `-libs`), separa `makedepends`/`hostmakedepends`

## Alpine Linux (aports)

- **Ubicación:** `~/package-repos/aports/`
- **Base:** musl + GCC (cuidado: usa GCC)

```bash
ls ~/package-repos/aports/community/paquete/
grep 'depends\|makedepends' ~/package-repos/aports/community/paquete/APKBUILD
```

Diferencias: aports usa GCC, parches pueden necesitar adaptación para LLVM

## Gentoo

- **Ubicación:** `~/package-repos/gentoo/`
- **Base:** GCC + glibc (muy diferente)

Útil como referencia de dependencias, no de build logic.
