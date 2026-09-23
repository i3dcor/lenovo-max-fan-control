# AGENT.md — Normas del proyecto legion-fan-auto

Instrucciones persistentes para cualquier agente (o humano) que modifique este
repositorio. Estas normas reflejan decisiones explícitas del usuario y no
deben revertirse sin que el usuario lo pida de nuevo.

## Norma: umbrales de temperatura y lógica de disparo (CPU/GPU)

- **Cada sensor tiene sus propios límites** (decisión del usuario, 2026-09-23):

  | Sensor | Activa modo max | Vuelve a modo normal |
  |---|---|---|
  | CPU | > 70°C | < 62°C |
  | GPU | > 64°C | < 60°C |

- El chequeo de temperatura se hace **tanto en CPU como en GPU**.
- **Subir a modo max**: alcanza con que **una sola** de las dos temperaturas
  supere **su** límite superior. No hace falta que ambas lo superen.
- **Bajar a modo normal**: se requiere que **las dos** temperaturas estén por
  debajo de **su** límite inferior al mismo tiempo. Si una sola sigue por
  encima, el modo max se mantiene.
- Las comparaciones son estrictas (`-gt` para subir, `-lt` para bajar).
- Esta asimetría (OR para subir, AND para bajar) es intencional: prioriza
  evitar sobrecalentamiento por sobre evitar ruido, y evita que el modo
  oscile (histéresis) cuando una sola temperatura fluctúa cerca del límite.

Implementado en `legion-fan-auto.sh` mediante `CPU_TEMP_ON` / `GPU_TEMP_ON` /
`CPU_TEMP_OFF` / `GPU_TEMP_OFF` (miligrados) y lectura de `temp1_input` (CPU) y
`temp2_input` (GPU) del hwmon `legion_hwmon`.

## Norma: el EC se queda siempre en `custom` (2026-09-23)

- **`platform_profile` se escribe exactamente una vez**, al arrancar el
  daemon, para poner el EC en `custom`. El bucle principal **nunca** vuelve a
  escribirlo.
- Cambiar entre modo normal y modo max es **solo** un cambio de curva con
  `fancurve-write-file-to-hw`: `normal-fan.yaml` y `max-fan.yaml`. Esa
  operación nunca ha provocado un apagado.
- Motivo: los dos apagados en seco confirmados fueron escrituras de
  `balanced` **después de un resume** (muerte a los 40 ms y a los 56 s). En
  cambio, escribir `custom` después de un resume se observó una vez y
  sobrevivió, y antes de la primera suspensión del boot cualquier valor ha
  sido inocuo. El daemon ya no escribe `balanced` nunca, así que el ciclo
  normal/max queda fuera del patrón peligroso.
- El mecanismo **no se conoce** y la muestra es pequeña. No extrapolar más
  allá de lo observado ni relajar las defensas por comodidad.
- **Corrección de una hipótesis previa:** la norma anterior culpaba de los
  apagados a *mantener* `custom` de forma continua (vía `min-fan.yaml`). Es
  falso. La evidencia apunta a la *escritura* del perfil, no al estado. Por
  eso ahora se mantiene `custom` de forma permanente a propósito.
- Permanecer en `custom` no impone piso de RPM: la primera fila de
  `normal-fan.yaml` es 0 RPM, así que los ventiladores pueden pararse en
  reposo.
- No reintroducir escrituras de `platform_profile` en el bucle principal sin
  instrucción explícita del usuario.

## Norma: el hook de suspensión solo escribe `balanced` una vez por boot

- `legion-fan-auto-sleep-hook.sh` marca `/run/legion-fan-auto.resumed` en
  **cada** resume, incluso si el daemon no estaba corriendo.
- En `pre`, si ese marcador existe, el hook **no** escribe `balanced`: para el
  daemon y deja el EC en `custom`. Escribir `balanced` ahí sería exactamente
  el patrón que mató la máquina dos veces.
- `/run` es tmpfs, así que el marcador desaparece al reiniciar y la primera
  suspensión de cada boot vuelve a devolver el EC a `balanced`.
- Dejar el EC en `custom` durante la suspensión es térmicamente seguro:
  `normal-fan.yaml` escala hasta 4500 RPM sin necesidad del daemon.

## Norma: activación manual únicamente

- El servicio **no** debe arrancar solo en boot ni quedar habilitado con
  `systemctl enable`. `legion-fan-auto.service` no tiene sección `[Install]`
  a propósito.
- Solo se activa cuando el usuario lo pide explícitamente, con
  `sudo systemctl start legion-fan-auto.service`, y se detiene con `stop`
  cuando termina de usarse.
- No reintroducir `[Install]`/`WantedBy` ni `systemctl enable` en el README
  sin instrucción explícita del usuario.

## Norma: pausa entre `set-feature custom` y la escritura de curva

- Al cambiar `platform_profile` a `custom`, el EC resetea momentáneamente su
  tabla de curva. Si `fancurve-write-file-to-hw` se llama sin pausa
  inmediatamente después, la escritura llega incompleta (algunas filas quedan
  en 0 o con el valor anterior), y el ventilador nunca alcanza el máximo real
  (verificado: se quedaba en ~3000 RPM en vez de 4500).
- `legion-fan-auto.sh` debe mantener el `sleep 1` entre la escritura inicial
  de `set-feature PlatformProfileFeature custom` y la primera llamada a
  `fancurve-write-file-to-hw`. No quitar esta pausa.

## Al modificar este proyecto

- Si se cambian los umbrales o la lógica CPU/GPU, actualizar esta norma en
  `AGENT.md`, el bloque `## Cómo funciona` de `README.md`, y las constantes
  de umbral en `legion-fan-auto.sh` de forma consistente entre los tres.
- No revertir la lógica OR-para-subir / AND-para-bajar sin instrucción
  explícita del usuario: es una decisión de diseño, no un valor por defecto.
