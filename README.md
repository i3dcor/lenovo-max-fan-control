# legion-fan-auto

Daemon que fuerza los ventiladores del Lenovo Legion 5 Pro 16ACH6H (82JQ) al máximo
cuando la CPU se calienta, y los devuelve a una curva moderada cuando se enfría.

Probado en CachyOS (Arch) con kernel 7.2.4-3-cachyos, BIOS GKCN65WW, vía el módulo
`legion-laptop` del proyecto [LenovoLegionLinux](https://github.com/johnfanv2/LenovoLegionLinux).

## Archivos

| Archivo | Destino | Descripción |
|---|---|---|
| `legion-fan-auto.sh` | `/usr/local/bin/legion-fan-auto.sh` | Loop que lee la temperatura de CPU y GPU y cambia de perfil |
| `legion-fan-auto.service` | `/etc/systemd/system/legion-fan-auto.service` | Unit de systemd que mantiene el script corriendo |
| `legion-fan-auto-sleep-hook.sh` | `/usr/lib/systemd/system-sleep/legion-fan-auto` | Para el daemon antes de suspender y, solo en la primera suspensión del boot, devuelve el EC a `balanced` |
| `max-fan.yaml` | `/etc/legion_linux/max-fan.yaml` | Curva de ventilador fija a 4500 RPM (techo real de hardware de este modelo) en todos los puntos de temperatura |
| `normal-fan.yaml` | `/etc/legion_linux/normal-fan.yaml` | Curva moderada para el modo normal: 0 RPM en reposo, escalando hasta 4500 RPM si la temperatura se dispara |

## Requisitos previos

1. Módulo `legion-laptop` cargado (paquete `lenovolegionlinux-dkms` en el repo `cachyos`):
   ```bash
   sudo pacman -S lenovolegionlinux-dkms
   sudo modprobe legion-laptop
   ```
2. `legion_cli` disponible en el PATH (lo instala el paquete `lenovolegionlinux`).
3. Verificar que tu modelo soporte fan curve custom:
   ```bash
   sudo cat /sys/kernel/debug/legion/fancurve
   ```
   Debe mostrar `EC Chip ID: 8227` y una tabla de curva no vacía.

## Instalación

```bash
sudo install -m 644 -D max-fan.yaml /etc/legion_linux/max-fan.yaml
sudo install -m 644 -D normal-fan.yaml /etc/legion_linux/normal-fan.yaml
sudo install -m 755 legion-fan-auto.sh /usr/local/bin/legion-fan-auto.sh
sudo install -m 644 legion-fan-auto.service /etc/systemd/system/legion-fan-auto.service
sudo install -m 755 legion-fan-auto-sleep-hook.sh /usr/lib/systemd/system-sleep/legion-fan-auto
sudo systemctl daemon-reload
```

**No se habilita ni se arranca automáticamente.** El servicio no tiene
`WantedBy`, así que `systemctl enable` no aplica y nunca arranca solo en el
boot. Se activa a mano solo cuando el usuario lo pide (ver `## Operación`).

## Cómo funciona

El script lee cada 5 segundos la temperatura de CPU y GPU desde
`/sys/class/hwmon/hwmonX/temp1_input` y `temp2_input` (hwmon `legion_hwmon`,
en miligrados).

- **Al arrancar el daemon** → escribe `platform_profile=custom` **una sola
  vez** y carga `normal-fan.yaml`. A partir de ahí el perfil no se vuelve a
  tocar nunca (ver `## Notas / limitaciones`).
- **CPU > 70°C O GPU > 64°C** → modo **max**: basta con que una sola de las
  dos temperaturas supere su límite superior para que ambos ventiladores
  pasen a `max-fan.yaml` (4500 RPM fijo en todo el rango). Cada sensor tiene
  su propio límite.
- **CPU < 62°C Y GPU < 60°C** (viniendo de modo max) → vuelve a modo
  **normal** recargando `normal-fan.yaml`. Se necesita que **ambas**
  temperaturas bajen de su límite inferior; si una sola sigue por encima, el
  modo max se mantiene.
- Dentro de la banda de histéresis de cada sensor (62-70°C en CPU, 60-64°C en
  GPU) se mantiene el modo activo, lo que evita que el ventilador oscile
  entre modos cuando una temperatura fluctúa cerca del límite.

**Por qué OR para subir y AND para bajar:** subir a modo max es una medida
de protección térmica, así que basta con que un solo componente (CPU o GPU)
supere su propio límite para justificarla. Bajar a modo normal, en cambio,
solo debe ocurrir cuando **todo** el sistema ya se enfrió; si se bajara con
que un solo componente estuviera frío, el otro podría seguir caliente sin
refrigeración adecuada. Esta asimetría es una decisión de diseño explícita, documentada
también en `AGENT.md`, y no debe cambiarse a menos que el usuario lo pida.

El EC permanece siempre en `platform_profile=custom`. Cambiar de modo es
**solo** un cambio de curva (`fancurve-write-file-to-hw`), nunca una escritura
de perfil. Esto es deliberado y crítico: la escritura de `platform_profile` es
la causa confirmada de los apagados en seco (ver `## Notas / limitaciones`).

Permanecer en `custom` **no** impone un piso de RPM: la primera fila de
`normal-fan.yaml` es 0 RPM, así que en reposo los ventiladores pueden pararse
igual que bajo control del firmware.

**Nota histórica:** se probó un piso permanente de 3000 RPM vía `min-fan.yaml`
y se atribuyeron a él unos apagados espontáneos. Esa atribución resultó ser
incorrecta: la causa real era la escritura de `platform_profile`. Aun así el
piso de RPM no se reintrodujo, porque no aporta nada frente a una curva normal
que arranca en 0 RPM.

## Ajustar umbrales

Editar las constantes al principio de `legion-fan-auto.sh` (en el destino
instalado, `/usr/local/bin/legion-fan-auto.sh`):

```bash
CPU_TEMP_ON=70000   # miligrados = 70°C -> activa modo max si la CPU lo supera
GPU_TEMP_ON=64000   # miligrados = 64°C -> activa modo max si la GPU lo supera
CPU_TEMP_OFF=62000  # miligrados = 62°C -> la CPU debe bajar de esto para volver a normal
GPU_TEMP_OFF=60000  # miligrados = 60°C -> la GPU debe bajar de esto para volver a normal
POLL_INTERVAL=5     # segundos entre lecturas
```

También se pueden ajustar las curvas editando `max-fan.yaml` y
`normal-fan.yaml` y reinstalándolas en `/etc/legion_linux/`.

Después de editar, reiniciar el servicio:

```bash
sudo systemctl restart legion-fan-auto.service
```

## Operación

```bash
# activar el daemon (solo cuando el usuario lo pida explícitamente)
sudo systemctl start legion-fan-auto.service

# ver cambios de modo en vivo
sudo journalctl -u legion-fan-auto.service -f

# ver RPM y temperaturas actuales
sensors | grep -A5 legion_hwmon

# desactivar (siempre al terminar, no queda corriendo en background)
sudo systemctl stop legion-fan-auto.service

# forzar una curva a mano (con el daemon parado)
sudo legion_cli fancurve-write-file-to-hw /etc/legion_linux/max-fan.yaml
sudo legion_cli fancurve-write-file-to-hw /etc/legion_linux/normal-fan.yaml

# devolver el control al firmware (solo si el daemon está parado)
sudo legion_cli set-feature PlatformProfileFeature balanced
```

## Notas / limitaciones

- El módulo `legion-laptop` no persiste solo entre reinicios si se cargó con
  `modprobe` manual; DKMS lo reconstruye para cada kernel, pero confirmar con
  `lsmod | grep legion` tras reiniciar. Si hace falta, agregarlo a
  `/etc/modules-load.d/legion-laptop.conf`.
- `maximumfanspeed` (el método WMI "fan full speed" nativo) **no está
  soportado por el firmware de este modelo** (BIOS GKCN*); por eso se usa una
  curva de ventilador custom fijada al máximo en vez de ese sysfs.
- El techo real de RPM de este modelo es ~4500-4550 RPM, no el `max = 10000
  RPM` que reporta `sensors` (ese valor es solo el límite teórico de la
  unidad, no el máximo alcanzable por el hardware).
- No dejar el modo máximo corriendo permanentemente sin necesidad: acelera el
  desgaste de los ventiladores.
- **Escribir `platform_profile=balanced` después de un resume apaga el equipo
  en seco.** Es la causa real de los apagados espontáneos, no la curva ni el
  piso de RPM. Los dos apagados confirmados comparten el mismo último registro
  antes del corte: `kernel: legion_laptop: Set powermode`, sin secuencia de
  shutdown, sin MCE y sin thermal critical.

  Evidencia completa de escrituras de perfil registradas en el journal:

  | Boot | Hora | ¿Tras un resume? | Valor | Resultado |
  |---|---|---|---|---|
  | -2 | 07:47:00 | sí (62 s antes) | `balanced` | **muerte a los 40 ms** |
  | -1 | 08:22:49 | no | `custom` | sobrevivió |
  | -1 | 08:28:36 | no | `balanced` | sobrevivió |
  | -1 | 08:35:58 | sí (3 min antes) | `custom` | sobrevivió 12 min más |
  | -1 | 08:47:30 | sí (15 min antes) | `balanced` | **muerte a los 56 s** |

  El patrón no es "cualquier escritura de perfil tras un resume". Es más
  concreto: **`balanced` tras un resume**. Escribir `custom` tras un resume se
  observó una vez y sobrevivió, y antes de la primera suspensión del boot
  cualquier valor ha sido inocuo.

  **No se conoce el mecanismo.** La muestra es pequeña (una sola observación
  del caso `custom` post-resume), así que el patrón es una correlación bien
  soportada, no una explicación demostrada. Tratar `balanced` post-resume como
  fatal y no fiarse de extrapolaciones.

  Tres defensas en el código, no quitar ninguna:
  1. El perfil se escribe a `custom` **una sola vez**, al arrancar el daemon.
     El bucle nunca vuelve a tocarlo: normal y max son solo curvas distintas
     escritas con `fancurve-write-file-to-hw`, que jamás ha provocado un
     apagado.
  2. `write_profile()` lee `/sys/firmware/acpi/platform_profile` y no escribe
     si el perfil ya es el deseado. Una escritura redundante **no** es un
     no-op a nivel de EC.
  3. El hook de `systemd-sleep` solo devuelve el EC a `balanced` en la
     **primera** suspensión del boot. Si el boot ya resumió alguna vez, marca
     `/run/legion-fan-auto.resumed` y deja el EC en `custom`, que sigue siendo
     térmicamente seguro porque `normal-fan.yaml` sube hasta 4500 RPM por sí
     solo. El daemon **no** se rearranca al despertar; hay que arrancarlo a
     mano.

  `legion_cli set-feature PlatformProfileFeature` escribe en
  `.../platform-profile-N/profile` del driver, o sea el mismo camino EC/WMI que
  el sysfs del kernel: cambiar de interfaz no evita el problema.
- Cambiar a `platform_profile=custom` resetea momentáneamente la curva en el
  EC; escribir la curva sin pausa justo después dejaba filas a medias (el
  ventilador se quedaba en ~3000 RPM en vez de 4500). Por eso el daemon espera
  1s tras la escritura inicial del perfil, antes de cargar la primera curva;
  no quitar esa pausa.
