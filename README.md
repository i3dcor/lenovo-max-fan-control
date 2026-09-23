# legion-fan-auto

Daemon que fuerza los ventiladores del Lenovo Legion 5 Pro 16ACH6H (82JQ) al máximo
cuando la CPU se calienta, y los devuelve al control normal del firmware cuando se enfría.

Probado en CachyOS (Arch) con kernel 7.2.4-3-cachyos, BIOS GKCN65WW, vía el módulo
`legion-laptop` del proyecto [LenovoLegionLinux](https://github.com/johnfanv2/LenovoLegionLinux).

## Archivos

| Archivo | Destino | Descripción |
|---|---|---|
| `legion-fan-auto.sh` | `/usr/local/bin/legion-fan-auto.sh` | Loop que lee la temperatura de CPU y GPU y cambia de perfil |
| `legion-fan-auto.service` | `/etc/systemd/system/legion-fan-auto.service` | Unit de systemd que mantiene el script corriendo |
| `legion-fan-auto-sleep-hook.sh` | `/usr/lib/systemd/system-sleep/legion-fan-auto` | Devuelve el EC a `balanced` y para el daemon antes de suspender |
| `max-fan.yaml` | `/etc/legion_linux/max-fan.yaml` | Curva de ventilador fija a 4500 RPM (techo real de hardware de este modelo) en todos los puntos de temperatura |

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

- **Al arrancar el daemon** → modo **normal**: pone `platform_profile=balanced`
  y deja que el firmware controle la curva de ventiladores libremente (sin
  piso mínimo forzado).
- **CPU ≥ 66°C O GPU ≥ 66°C** → modo **max**: basta con que una sola de las
  dos temperaturas supere el límite superior para que ambos ventiladores
  pasen a `platform_profile=custom` + `max-fan.yaml` (4500 RPM fijo en todo
  el rango).
- **CPU ≤ 55°C Y GPU ≤ 55°C** (viniendo de modo max) → vuelve a modo
  **normal** (`platform_profile=balanced`, control del firmware). Se necesita
  que **ambas** temperaturas bajen del límite inferior; si una sola sigue por
  encima de 55°C, el modo max se mantiene.
- Entre 55°C y 66°C (para la temperatura que disparó el cambio) se mantiene
  el modo activo (histéresis, evita que el ventilador oscile entre modos).

**Por qué OR para subir y AND para bajar:** subir a modo max es una medida
de protección térmica, así que basta con que un solo componente (CPU o GPU)
se caliente para justificarla. Bajar a modo normal, en cambio, solo debe
ocurrir cuando **todo** el sistema ya se enfrió; si se bajara con que un solo
componente estuviera frío, el otro podría seguir caliente sin refrigeración
adecuada. Esta asimetría es una decisión de diseño explícita, documentada
también en `AGENT.md`, y no debe cambiarse a menos que el usuario lo pida.

`platform_profile=custom` solo se usa en modo max, para forzar la curva fija
de `max-fan.yaml`. En modo normal se usa `platform_profile=balanced`, que deja
el control de la curva al firmware/EC sin ningún piso de RPM impuesto por este
script.

**Nota histórica:** se probó un piso permanente de 3000 RPM (modo normal con
`platform_profile=custom` + `min-fan.yaml`), pero causó apagados espontáneos
del portátil. Se revirtió; ver `AGENT.md`.

## Ajustar umbrales

Editar las constantes al principio de `legion-fan-auto.sh` (en el destino
instalado, `/usr/local/bin/legion-fan-auto.sh`):

```bash
TEMP_ON=66000    # miligrados = 66°C -> activa modo max si CPU o GPU lo supera
TEMP_OFF=55000   # miligrados = 55°C -> vuelve a modo normal si CPU y GPU bajan de esto
POLL_INTERVAL=5  # segundos entre lecturas
```

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

# volver a control manual: forzar modo max/normal a mano
sudo legion_cli set-feature PlatformProfileFeature custom
sudo legion_cli fancurve-write-file-to-hw /etc/legion_linux/max-fan.yaml
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
- **Escribir `platform_profile` después de un resume de S3 apaga el equipo en
  seco.** Es la causa real de los apagados espontáneos, no la curva ni el piso
  de RPM. Evidencia en el journal: las 6 escrituras del boot `-2` previas a
  cualquier suspend fueron inocuas, mientras que las dos únicas escrituras
  posteriores a un resume mataron la máquina a los 1.1 s y a los 40 ms
  respectivamente, sin secuencia de shutdown, sin MCE y sin thermal critical.
  El último registro antes del corte es siempre `kernel: legion_laptop: Set
  powermode`.

  Dos defensas en el código, no quitar ninguna:
  1. `write_profile()` lee `/sys/firmware/acpi/platform_profile` y no escribe
     si el perfil ya es el deseado. Una escritura redundante **no** es un
     no-op a nivel de EC: es la que mataba el equipo al arrancar el servicio.
  2. El hook de `systemd-sleep` vuelve a `balanced` mientras todavía es seguro
     escribir (antes de S3) y para el daemon. **No** se rearranca solo al
     despertar; hay que arrancarlo a mano, idealmente tras reiniciar.

  `legion_cli set-feature PlatformProfileFeature` escribe en
  `.../platform-profile-N/profile` del driver, o sea el mismo camino EC/WMI que
  el sysfs del kernel: cambiar de interfaz no evita el problema.
- Cambiar a `platform_profile=custom` resetea momentáneamente la curva en el
  EC; escribir la curva sin pausa justo después dejaba filas a medias (el
  ventilador se quedaba en ~3000 RPM en vez de 4500). Por eso `set_max()`
  espera 1s antes de escribir `max-fan.yaml`; no quitar esa pausa.
