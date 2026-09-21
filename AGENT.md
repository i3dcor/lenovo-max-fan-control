# AGENT.md — Normas del proyecto legion-fan-auto

Instrucciones persistentes para cualquier agente (o humano) que modifique este
repositorio. Estas normas reflejan decisiones explícitas del usuario y no
deben revertirse sin que el usuario lo pida de nuevo.

## Norma: umbrales de temperatura y lógica de disparo (CPU/GPU)

- **Límite superior (activa modo max): 66°C.**
- **Límite inferior (vuelve a modo normal): 55°C.**
- El chequeo de temperatura se hace **tanto en CPU como en GPU**.
- **Subir a modo max**: alcanza con que **una sola** de las dos temperaturas
  (CPU o GPU) supere los 66°C. No hace falta que ambas lo superen.
- **Bajar a modo normal**: se requiere que **las dos** temperaturas (CPU y
  GPU) estén por debajo de 55°C al mismo tiempo. Si una sola sigue por
  encima de 55°C, el modo max se mantiene.
- Esta asimetría (OR para subir, AND para bajar) es intencional: prioriza
  evitar sobrecalentamiento por sobre evitar ruido, y evita que el modo
  oscile (histéresis) cuando una sola temperatura fluctúa cerca del límite.

Implementado en `legion-fan-auto.sh` mediante `TEMP_ON=66000` / `TEMP_OFF=55000`
(miligrados) y lectura de `temp1_input` (CPU) y `temp2_input` (GPU) del hwmon
`legion_hwmon`.

## Norma: sin piso mínimo de RPM (revertido 2026-09-21)

- Se probó imponer un piso de 3000 RPM permanente vía `platform_profile=custom`
  + `min-fan.yaml`, pero causó apagados espontáneos del portátil (posible
  conflicto con el EC al mantener `custom` de forma continua). El usuario
  restauró un snapshot y pidió revertir este cambio.
- **Modo normal ahora es `platform_profile=balanced`**: el firmware controla
  la curva de ventiladores libremente por debajo del límite superior de
  temperatura, sin piso forzado.
- **Modo max sigue siendo `platform_profile=custom` + `max-fan.yaml`**
  (ventiladores fijos a 4500 RPM) y solo se activa cuando CPU o GPU superan
  el límite superior.
- No reintroducir el piso de RPM ni `min-fan.yaml` sin instrucción explícita
  del usuario.

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
- `set_max()` en `legion-fan-auto.sh` debe mantener `sleep 1` entre
  `set-feature PlatformProfileFeature custom` y
  `fancurve-write-file-to-hw "$MAX_CURVE"`. No quitar esta pausa.

## Al modificar este proyecto

- Si se cambian los umbrales o la lógica CPU/GPU, actualizar esta norma en
  `AGENT.md`, el bloque `## Cómo funciona` de `README.md`, y las constantes
  `TEMP_ON`/`TEMP_OFF` en `legion-fan-auto.sh` de forma consistente entre
  los tres.
- No revertir la lógica OR-para-subir / AND-para-bajar sin instrucción
  explícita del usuario: es una decisión de diseño, no un valor por defecto.
