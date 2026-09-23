#!/bin/bash
# systemd-sleep hook: install as /usr/lib/systemd/system-sleep/legion-fan-auto
#
# legion_laptop EC writes are fatal after an S3 resume: the machine hard-powers
# off within milliseconds of "Set powermode". Two confirmed hard shutdowns were
# traced to exactly that write, while every pre-suspend write in the same boot
# was harmless.
#
# So: return the EC to balanced while it is still safe to write (before S3) and
# stop the daemon. It is not restarted on resume; start it manually when needed.
set -u

SERVICE=legion-fan-auto.service
STATE_FILE=/run/legion-fan-auto.was-active

case "$1" in
pre)
	if systemctl is-active --quiet "$SERVICE"; then
		touch "$STATE_FILE"
		systemctl stop "$SERVICE"
		if [[ "$(cat /sys/firmware/acpi/platform_profile)" != balanced ]]; then
			legion_cli set-feature PlatformProfileFeature balanced >/dev/null 2>&1
		fi
		logger -t legion-fan-auto "stopped before suspend, EC left in balanced"
	fi
	;;
post)
	if [[ -e "$STATE_FILE" ]]; then
		rm -f "$STATE_FILE"
		logger -t legion-fan-auto "resumed: service left stopped on purpose, EC writes are unsafe until reboot"
	fi
	;;
esac
