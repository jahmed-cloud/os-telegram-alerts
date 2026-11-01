#!/bin/sh
# Monit program check (service "net_watch"), runs every cycle, always exits 0.
# - Detects a new boot and reports "router started".
# - Tracks internet reachability; on recovery reports the outage window.
#   (A message cannot be delivered while the internet is down.)
PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
ENV=/usr/local/etc/telegram-alerts.env
SEND=/usr/local/opnsense/scripts/OPNsense/TelegramAlerts/send.sh
STATE=/var/db/telegram-alerts
mkdir -p "$STATE"; chmod 700 "$STATE"
[ -r "$ENV" ] && . "$ENV"
[ "$TG_ENABLED" = "1" ] && [ "${TG_NETWATCH:-1}" = "1" ] || { echo "net watch disabled"; exit 0; }

notify() {  # $1 event, $2 description; queue if delivery fails
    if MONIT_SERVICE="net_watch" MONIT_EVENT="$1" MONIT_DESCRIPTION="$2" "$SEND" >/dev/null 2>&1; then
        return 0
    fi
    mkdir -p "$STATE/queue"
    f="$STATE/queue/$(date +%s)-$$.msg"
    printf 'EV=%s\nDS=%s\n' "$1" "$2" > "$f"
}

online=0
for ip in 1.1.1.1 9.9.9.9 8.8.8.8; do
    if ping -c 1 -t 3 -q "$ip" >/dev/null 2>&1; then online=1; break; fi
done
now=$(date +%s)

# Boot detection
boot=$(sysctl -n kern.boottime | sed -n 's/^{ sec = \([0-9]*\),.*/\1/p')
if [ "$(cat "$STATE/boot" 2>/dev/null)" != "$boot" ]; then
    echo "$boot" > "$STATE/boot"
    notify "Router started" "Booted at $(date -r "$boot" '+%F %T %Z'). Check for a power loss or an unplanned reboot if you did not restart it."
fi

# Two failed checks in a row count as an outage, so a single lost ping is not reported.
prev=$(cat "$STATE/wan" 2>/dev/null || echo up)
if [ "$online" = "0" ]; then
    fails=$(( $(cat "$STATE/wan_fails" 2>/dev/null || echo 0) + 1 ))
    echo "$fails" > "$STATE/wan_fails"
    [ "$fails" = "1" ] && echo "$now" > "$STATE/down_since"
    [ "$fails" -ge 2 ] && [ "$prev" = "up" ] && echo down > "$STATE/wan"
else
    rm -f "$STATE/wan_fails"
fi
if [ "$online" = "1" ] && [ "$prev" = "down" ]; then
    since=$(cat "$STATE/down_since" 2>/dev/null || echo "$now")
    mins=$(( (now - since) / 60 ))
    echo up > "$STATE/wan"
    echo "$since $now $mins" >> "$STATE/outages.log"
    tail -n 200 "$STATE/outages.log" > "$STATE/outages.tmp" && mv "$STATE/outages.tmp" "$STATE/outages.log"
    notify "Internet back online" "Offline from $(date -r "$since" '+%F %T') to $(date -r "$now" '+%T %Z') (${mins} min)."
fi

# Deliver anything queued while offline
if [ "$online" = "1" ] && [ -d "$STATE/queue" ]; then
    for f in "$STATE"/queue/*.msg; do
        [ -f "$f" ] || continue
        EV=$(sed -n 's/^EV=//p' "$f"); DS=$(sed -n 's/^DS=//p' "$f")
        MONIT_SERVICE="net_watch" MONIT_EVENT="$EV (delayed)" MONIT_DESCRIPTION="$DS" "$SEND" >/dev/null 2>&1 && rm -f "$f"
    done
fi

[ "$online" = "1" ] && echo "internet up" || echo "internet down since $(date -r "$(cat "$STATE/down_since" 2>/dev/null || echo "$now")" '+%T')"
exit 0
