#!/bin/sh
# Configuración de red estática para KISS Linux
# Interfaz: eth0

# Configurar IP estática
ip addr add 192.168.1.45/24 dev eth0

# Levantar la interfaz
ip link set eth0 up

# Configurar gateway por defecto
ip route add default via 192.168.1.1

# Configurar DNS (Cloudflare)
cat > /etc/resolv.conf << EOF
nameserver 1.1.1.1
nameserver 1.0.0.1
EOF
