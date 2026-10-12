#!/bin/sh
# Habilita DAMON_LRU_SORT (reclaim proactivo: ordena las LRU caliente/frio).
echo Y > /sys/module/damon_lru_sort/parameters/enabled 2>/dev/null || true
