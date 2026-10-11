# Revisión de integridad para KISS

KISS ya distribuye utilidades útiles, pero ninguna hace por sí sola una auditoría integral del sistema:

- `kiss-manifest PKG` enumera los archivos que KISS cree que pertenecen al paquete; no verifica que existan.
- `kiss-revdepends PKG` consulta las dependencias runtime declaradas de los paquetes instalados. `kiss-reporevdepends PKG` hace la consulta sobre recetas del repositorio.
- `kiss-orphans` encuentra paquetes instalados que no aparecen como dependencia de otro paquete.
- `kiss upgrade` compara las versiones instaladas con las recetas y reconstruye los paquetes que cambiaron. No reconstruye automáticamente todos los consumidores de una biblioteca que cambió.
- `kiss-outdated` consulta versiones externas; no comprueba integridad local ni sustituye `kiss upgrade`.

`kiss-integrity` combina comprobaciones locales sin modificar el sistema:

```sh
kiss-integrity
kiss-integrity --no-elf
kiss-integrity --elf-all
kiss-integrity --rebuild-for llvm
```

Comprueba rutas de los manifests, enlaces simbólicos rotos, dependencias runtime ausentes y, en el root activo, dependencias ELF que el cargador no puede resolver. El modo predeterminado limita `ldd` a binarios en `bin/` y `sbin/`; en el sistema probado esto tardó unos 20 segundos para 657 binarios dinámicos. `--elf-all` extiende el chequeo a bibliotecas y plugins, que es significativamente más lento y puede encontrar símbolos indefinidos esperables fuera de sus procesos anfitriones. Compara las versiones instaladas con la primera receta coincidente en `KISS_PATH`; si cambió un paquete que contiene bibliotecas compartidas, imprime los consumidores runtime transitivos como candidatos a recompilación. `--rebuild-for PKG` muestra esa clausura para cualquier paquete instalado. El informe no reconstruye ni instala nada.

El análisis ELF emplea `readelf` para filtrar objetos dinámicos y `ldd` de musl para comprobar que carguen. No usa `ldd -r`: esa opción no está disponible en el `ldd` de musl, y cargar cada módulo de plugins fuera de su aplicación anfitriona produce símbolos indefinidos esperados. Por ello, un ABI roto que conserve el mismo SONAME puede no detectarse automáticamente. La lista inversa de dependencias es deliberadamente conservadora: una versión nueva de una biblioteca genera candidatos, no demuestra por sí misma incompatibilidad ABI.

Para un root alternativo definido mediante `KISS_ROOT`, el análisis ELF se desactiva porque `ldd` del host no representa el cargador ni las bibliotecas de ese root. La utilidad marca el estado con un resumen y devuelve código 1 si encuentra rutas/dependencias rotas o versiones de receta distintas, y código 2 ante uso incorrecto o base de paquetes ausente.

Las comprobaciones no cambian archivos. En el sistema actual los fallos apuntan a manifests antiguos o paquetes que requieren reinstalación: Avahi conserva enlaces a páginas man desactivadas; libomp y LuaJIT tienen enlaces sin su destino versionado; Python tiene `pip -> pip3` pero no el launcher; el manifest de Node.js conserva entradas de npm que ya no están en disco. Además, el `jq` instalado requiere `libonig.so.5` pese a que la receta actual configura Oniguruma integrado, y `xfs_scrub` conserva una dependencia de ICU 74 con RUNPATH al directorio temporal de un build anterior, mientras el sistema tiene ICU 78. Los releases de las recetas se incrementan para que KISS regenere paquetes y manifests; instala las actualizaciones con el flujo habitual de KISS y repite `kiss-integrity`. Las pruebas reproducibles del script son `sh test/kiss-integrity/run`.
