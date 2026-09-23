#!/bin/bash
set -euo pipefail

HWMON=$(dirname "$(grep -l legion_hwmon /sys/class/hwmon/hwmon*/name)")
CPU_TEMP_FILE="$HWMON/temp1_input"
GPU_TEMP_FILE="$HWMON/temp2_input"
MAX_CURVE="/etc/legion_linux/max-fan.yaml"
NORMAL_CURVE="/etc/legion_linux/normal-fan.yaml"
PROFILE_FILE="/sys/firmware/acpi/platform_profile"
CPU_TEMP_ON=70000
GPU_TEMP_ON=64000
CPU_TEMP_OFF=62000
GPU_TEMP_OFF=60000
POLL_INTERVAL=5

# Writing the platform profile goes straight to the EC through legion_laptop.
# Both hard poweroffs on record were writes of "balanced" after an S3 resume,
# 40ms and 56s after the write. Writing "custom" after a resume survived, and
# any value before the first suspend of a boot has been harmless. The
# mechanism is unknown and the sample is small, so the daemon avoids the
# pattern entirely: platform_profile is written to custom exactly once, at
# startup, and never touched again; normal vs max is a fan-curve swap only
# (fancurve-write-file-to-hw), which has never been observed to crash the EC.
write_profile() {
	local target=$1
	if [[ "$(cat "$PROFILE_FILE")" == "$target" ]]; then
		return 1
	fi
	legion_cli set-feature PlatformProfileFeature "$target" >/dev/null
	return 0
}

if write_profile custom; then
	# switching to custom momentarily resets the curve in the EC; without
	# this pause the next write lands half-applied (some rows stay at 0)
	sleep 1
fi

set_max() {
	legion_cli fancurve-write-file-to-hw "$MAX_CURVE" >/dev/null
	logger -t legion-fan-auto "switched to MAX curve"
}

set_normal() {
	legion_cli fancurve-write-file-to-hw "$NORMAL_CURVE" >/dev/null
	logger -t legion-fan-auto "switched to NORMAL curve"
}

set_normal
state="normal"

while true; do
	cpu_temp=$(cat "$CPU_TEMP_FILE")
	gpu_temp=$(cat "$GPU_TEMP_FILE")
	if [[ "$state" == "normal" && ( "$cpu_temp" -gt "$CPU_TEMP_ON" || "$gpu_temp" -gt "$GPU_TEMP_ON" ) ]]; then
		set_max
		state="max"
	elif [[ "$state" == "max" && "$cpu_temp" -lt "$CPU_TEMP_OFF" && "$gpu_temp" -lt "$GPU_TEMP_OFF" ]]; then
		set_normal
		state="normal"
	fi
	sleep "$POLL_INTERVAL"
done
