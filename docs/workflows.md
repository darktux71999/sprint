# Workflows

## Actualizar paquete

```bash
# 1. Verificar versiones disponibles (comparar con cports)
for dir in ~/package-repos/sprint/core/*/ ~/package-repos/sprint/extra/*/; do
    pkg=$(basename "$dir")
    [ -f "$dir/version" ] || continue
    s=$(head -1 "$dir/version" | awk '{print $1}')
    [ -f ~/package-repos/cports/main/$pkg/template.py ] || continue
    c=$(grep '^pkgver' ~/package-repos/cports/main/$pkg/template.py | grep -o '"[^"]*"' | tr -d '"')
    [ -z "$c" ] || [ "$s" = "$c" ] || printf "%-20s sprint=%-10s cports=%-10s\n" "$pkg" "$s" "$c"
done | sort

# 2. Actualizar
echo "1.2.4 1" > extra/paquete/version
sed -i 's/1.2.3/1.2.4/g' extra/paquete/sources
kiss checksum paquete

# 3. Build e instalar
kiss b paquete
kiss i paquete

# 4. Commit
git add extra/paquete
git commit -m "upgrade: paquete 1.2.3 -> 1.2.4"
```

## Crear paquete nuevo

```bash
# 1. Estructura
mkdir -p extra/paquete

# 2. Archivos
echo "1.0.0 1" > extra/paquete/version
cat > extra/paquete/sources << 'EOF'
https://ejemplo.com/paquete-1.0.0.tar.gz
EOF
cat > extra/paquete/depends << 'EOF'
cmake make
openssl
EOF
cat > extra/paquete/build << 'EOF'
#!/bin/sh -e
export DESTDIR="$1"
./configure --prefix=/usr
make
make DESTDIR="$1" install
EOF
chmod +x extra/paquete/build

# 3. Checksums y test
kiss checksum paquete
kiss b paquete

# 4. Commit
git add extra/paquete
git commit -m "extra: add paquete"
```

## Logs de error

```bash
ls -t ~/.cache/kiss/logs/$(date +%Y-%m-%d)/paquete-* | head -1
```
