#!/bin/bash
# Read-only status of the legion-fan-auto daemon and the EC fan state.
set -u

SERVICE=legion-fan-auto.service

service_state=$(systemctl is-active "$SERVICE")
profile=$(cat /sys/firmware/acpi/platform_profile)
curve=$(journalctl -u "$SERVICE" -n 50 --no-pager -o cat 2>/dev/null |
	grep -oE 'switched to (MAX|NORMAL) curve' | tail -1)

echo "servicio : $service_state"
echo "perfil   : $profile"
echo "curva    : ${curve:-desconocida (sin cambios de curva en el log reciente)}"

if [[ -e /run/legion-fan-auto.resumed ]]; then
	echo "resume   : este boot ya resumió -> el hook no escribirá 'balanced' al suspender"
else
	echo "resume   : sin resumes en este boot -> la próxima suspensión devolverá el EC a 'balanced'"
fi

# active + balanced means the daemon is running without the profile it needs.
if [[ "$service_state" == "active" && "$profile" != custom ]]; then
	echo "AVISO    : servicio activo pero el perfil no es 'custom'"
fi

echo
sensors 2>/dev/null | grep -E '^Fan|Temperature'
