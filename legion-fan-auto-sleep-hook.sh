#!/bin/bash
# systemd-sleep hook: install as /usr/lib/systemd/system-sleep/legion-fan-auto
#
# Writing platform_profile=balanced after a resume is the confirmed cause of
# the hard poweroffs. Both deaths were exactly that write, 40ms and 56s after
# it. The same write before the first suspend of a boot has always been
# harmless, and writing custom after a resume has been observed to survive.
#
# So: on the first suspend of a boot, return the EC to balanced and stop the
# daemon. Once this boot has resumed at least once, never write the profile
# again: stop the daemon and leave the EC in custom. That stays thermally
# safe on its own because normal-fan.yaml ramps to 4500 RPM as temperature
# rises, with no daemon needed.
set -u

SERVICE=legion-fan-auto.service
STATE_FILE=/run/legion-fan-auto.was-active
RESUMED_FILE=/run/legion-fan-auto.resumed

case "$1" in
pre)
	if systemctl is-active --quiet "$SERVICE"; then
		touch "$STATE_FILE"
		systemctl stop "$SERVICE"
		if [[ -e "$RESUMED_FILE" ]]; then
			logger -t legion-fan-auto "stopped before suspend, EC left in custom (balanced is unsafe once this boot has resumed)"
		elif [[ "$(cat /sys/firmware/acpi/platform_profile)" != balanced ]]; then
			legion_cli set-feature PlatformProfileFeature balanced >/dev/null 2>&1
			logger -t legion-fan-auto "stopped before suspend, EC left in balanced"
		else
			logger -t legion-fan-auto "stopped before suspend, EC already in balanced"
		fi
	fi
	;;
post)
	# Mark the boot on every resume, even when the daemon was not running:
	# the next pre-suspend hook needs to know a resume already happened.
	touch "$RESUMED_FILE"
	if [[ -e "$STATE_FILE" ]]; then
		rm -f "$STATE_FILE"
		logger -t legion-fan-auto "resumed: service left stopped on purpose, start it manually"
	fi
	;;
esac
