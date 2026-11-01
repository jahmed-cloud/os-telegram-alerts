#!/bin/sh
# Monit custom check: exit 1 when CPU temperature exceeds the configured limit.
ENV=/usr/local/etc/telegram-alerts.env
TG_TEMP_MAX=80
[ -r "$ENV" ] && . "$ENV"

T=$(sysctl -n hw.acpi.thermal.tz0.temperature 2>/dev/null | tr -d C | cut -d. -f1)
[ -z "$T" ] && T=$(sysctl -n dev.cpu.0.temperature 2>/dev/null | tr -d C | cut -d. -f1)

if [ -z "$T" ]; then
    echo "No temperature sensor found"
    exit 0
fi

echo "CPU ${T}C (limit ${TG_TEMP_MAX}C)"
[ "$T" -ge "$TG_TEMP_MAX" ] && exit 1
exit 0
