#!/bin/sh
# Monit program check (service "fw_update"). Exit 1 when package updates are
# available; Monit then calls tg-alert.sh once per state change.
# The repository is queried at most every 6 hours; other runs return the cache.
PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
ENV=/usr/local/etc/telegram-alerts.env
STATE=/var/db/telegram-alerts
CACHE="$STATE/update.out"; RC="$STATE/update.rc"
mkdir -p "$STATE"; chmod 700 "$STATE"
[ -r "$ENV" ] && . "$ENV"
[ "${TG_UPDATES:-1}" = "1" ] || { echo "update check disabled"; exit 0; }

age=999999
[ -f "$CACHE" ] && age=$(( $(date +%s) - $(stat -f %m "$CACHE") ))
if [ "$age" -ge 21600 ]; then
    if pkg update -q >/dev/null 2>&1; then
        list=$(pkg upgrade -n 2>/dev/null | sed -n 's/^[[:space:]]*\([^ :]*\): \([^ ]*\) -> \([^ ]*\).*/\1 \2 -> \3/p')
        n=$(printf '%s\n' "$list" | grep -c .)
        if [ "$n" -gt 0 ]; then
            printf 'Updates available (%s packages): %s Install via System > Firmware > Updates.\n' \
                "$n" "$(printf '%s\n' "$list" | head -5 | tr '\n' ';' | sed 's/;/; /g')" > "$CACHE"
            echo 1 > "$RC"
        else
            echo "Up to date ($(opnsense-version -v 2>/dev/null))" > "$CACHE"
            echo 0 > "$RC"
        fi
    else
        echo "Update check could not reach the repository; will retry" > "$CACHE"
        echo 0 > "$RC"
        touch -t "$(date -v-5H '+%Y%m%d%H%M')" "$CACHE"   # retry in ~1 hour
    fi
fi
cat "$CACHE"
exit "$(cat "$RC" 2>/dev/null || echo 0)"
