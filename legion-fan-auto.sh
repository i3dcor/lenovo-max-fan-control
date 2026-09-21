#!/bin/bash
set -euo pipefail

HWMON=$(dirname "$(grep -l legion_hwmon /sys/class/hwmon/hwmon*/name)")
CPU_TEMP_FILE="$HWMON/temp1_input"
GPU_TEMP_FILE="$HWMON/temp2_input"
MAX_CURVE="/etc/legion_linux/max-fan.yaml"
TEMP_ON=66000
TEMP_OFF=55000
POLL_INTERVAL=5

state=""

set_max() {
	legion_cli set-feature PlatformProfileFeature custom >/dev/null
	# el cambio a custom resetea momentáneamente la curva en el EC; sin esta
	# pausa la escritura siguiente llega a medias (algunas filas quedan en 0)
	sleep 1
	legion_cli fancurve-write-file-to-hw "$MAX_CURVE" >/dev/null
	logger -t legion-fan-auto "switched to MAX mode"
}

set_normal() {
	legion_cli set-feature PlatformProfileFeature balanced >/dev/null
	logger -t legion-fan-auto "switched to NORMAL mode (firmware control)"
}

set_normal
state="normal"

while true; do
	cpu_temp=$(cat "$CPU_TEMP_FILE")
	gpu_temp=$(cat "$GPU_TEMP_FILE")
	if [[ "$state" == "normal" && ( "$cpu_temp" -ge "$TEMP_ON" || "$gpu_temp" -ge "$TEMP_ON" ) ]]; then
		set_max
		state="max"
	elif [[ "$state" == "max" && "$cpu_temp" -le "$TEMP_OFF" && "$gpu_temp" -le "$TEMP_OFF" ]]; then
		set_normal
		state="normal"
	fi
	sleep "$POLL_INTERVAL"
done
