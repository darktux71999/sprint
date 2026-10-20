# Captura del fallo de parche para KISS

Cuando un parche no se aplica, KISS no deja nada utilizable. La construcción falla con un código de salida, el log de texto se guarda con un nombre fechado, los ficheros `.rej` que genera `patch(1)` se quedan en el directorio de build y ese directorio se borra acto seguido. Para un humano basta con releer el log; para un agente que tiene que corregir el parche, no: el `.rej` con el hunk que falló y su contexto es exactamente lo que hace falta, y desaparece.

KISS ofrece el punto de enganche: `run_hook build-fail` recibe `(hook, paquete, directorio de build)` y se ejecuta **antes** de `pkg_clean`, que es lo que borra el directorio de build (`kiss:1108-1127` y `kiss:1865-1873`). Es el único momento en que el fallo se puede leer.

`kiss-patch-fail` es ese hook:

```sh
export KISS_HOOK=/usr/bin/kiss-patch-fail
kiss build mesa
```

El hook nunca falla la construcción y solo escribe en la caché de KISS. Para cada paquete fallido deja:

- `~/.cache/kiss/patch-fail/<paquete>/<paquete>.json`: el informe.
- `~/.cache/kiss/patch-fail/<paquete>/rejects/`: una copia de los `.rej`.

El directorio de salida se puede cambiar con `KISS_PATCH_FAIL_DIR`.

## El informe

El JSON lleva la receta y la versión que se estaban construyendo, la URL del upstream, el directorio de build (donde está el código nuevo que rechazó el parche), el log de la construcción, los parches que se copiaron al directorio de build, las líneas del log que explican el fallo y los parches rechazados con el contenido de su `.rej`:

```json
{
  "tool": "kiss-patch-fail",
  "version": "1.0",
  "package": "mesa",
  "recipe": "/home/darktux/proyectos/sprint/xorg/mesa",
  "recipe_version": "26.2.4",
  "upstream": "http://.../mesa-26.2.4.tar.xz",
  "build_dir": "/home/darktux/.cache/kiss/proc/4242/build/mesa",
  "log": "/home/darktux/.cache/kiss/logs/2026-10-19/mesa-101010-4242",
  "captured_at": "2026-10-19T21:30:00Z",
  "rejects_dir": "/home/darktux/.cache/kiss/patch-fail/mesa/rejects",
  "copied_patches": ["nak-sustga-channel-mask.patch"],
  "patch_errors": [
    "Hunk #1 FAILED at 10."
  ],
  "rejected_patches": [
    {
      "patch": "nvc0-surface-0001.patch",
      "rej_file": "nvc0-surface-0001.patch.rej",
      "truncated": "no",
      "content": "diff --git a/src/main.c b/src/main.c\n..."
    }
  ]
}
```

`build_dir` es lo que permite seguir el rastro: ahí está el código del upstream contra el que el parche falló, y ahí es donde hay que probar el parche corregido antes de tocar la receta. El contenido de un `.rej` se corta a 400 líneas y el campo `truncated` lo indica.

El informe se sobrescribe en cada fallo del mismo paquete: lo que interesa es el último fallo, no el historial.

## Qué habilita

Con el informe y el código nuevo en el mismo sitio, la corrección de un parche deja de ser adivinar y pasa a ser un bucle con comprobación: el hunk rechazado y el código que lo rechazó como entrada, el hunk corregido como salida, y una comprobación en seco con `patch -p1 --dry-run --fuzz=0` antes de tocar la receta. Eso es el motor de corrección de parches, que todavía no existe en el repositorio.

Las pruebas reproducibles del script son `sh test/kiss-patch-fail/run`.
