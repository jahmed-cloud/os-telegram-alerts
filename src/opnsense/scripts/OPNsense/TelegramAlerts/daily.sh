#!/bin/sh
# Daily summary, run from System > Settings > Cron ("Telegram Alerts daily summary").
PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
ENV=/usr/local/etc/telegram-alerts.env
SEND=/usr/local/opnsense/scripts/OPNsense/TelegramAlerts/send.sh
STATE=/var/db/telegram-alerts
mkdir -p "$STATE"; chmod 700 "$STATE"
[ -r "$ENV" ] && . "$ENV"
[ "$TG_ENABLED" = "1" ] || { echo "alerts disabled"; exit 0; }
now=$(date +%s); since=$(cat "$STATE/daily.last" 2>/dev/null || echo $((now - 86400)))

boot=$(sysctl -n kern.boottime | sed -n 's/^{ sec = \([0-9]*\),.*/\1/p')
up_d=$(( (now - boot) / 86400 )); up_h=$(( (now - boot) % 86400 / 3600 ))

gw=$(php /usr/local/opnsense/scripts/OPNsense/TelegramAlerts/gw-stats.php | awk 'NR==1 {printf "%s ms, %s%% loss", $2, $3}')

out_n=0; out_m=0
if [ -f "$STATE/outages.log" ]; then
    out_n=$(awk -v s="$since" '$2 >= s' "$STATE/outages.log" | wc -l | tr -d ' ')
    out_m=$(awk -v s="$since" '$2 >= s {m += $3} END {print m + 0}' "$STATE/outages.log")
fi

q_now=$(unbound-control -c /var/unbound/unbound.conf stats_noreset 2>/dev/null | sed -n 's/^total.num.queries=//p')
q_prev=$(cat "$STATE/dns.queries" 2>/dev/null)
[ -n "$q_now" ] && echo "$q_now" > "$STATE/dns.queries"
if [ -n "$q_now" ] && [ -n "$q_prev" ] && [ "$q_now" -ge "$q_prev" ]; then dns=$((q_now - q_prev))
elif [ -z "$q_prev" ]; then dns="collecting (first report)"
else dns="${q_now} (resolver restarted)"; fi

ids=0
if [ -f /var/log/suricata/eve.json ]; then
    # Alerts since the previous report (eve timestamps are local time, so they compare as strings)
    ts=$(date -r "$since" '+%Y-%m-%dT%H:%M:%S')
    ids=$(grep '"event_type":"alert"' /var/log/suricata/eve.json \
        | sed -n 's/.*"timestamp":"\([0-9T:-]\{19\}\).*/\1/p' | awk -v s="$ts" '$0 >= s' | wc -l | tr -d ' ')
fi

macs_now=$(wc -l < "$STATE/known_macs" 2>/dev/null | tr -d ' '); macs_prev=$(cat "$STATE/macs.count" 2>/dev/null || echo "$macs_now")
echo "${macs_now:-0}" > "$STATE/macs.count"
newdev=$(( ${macs_now:-0} - ${macs_prev:-0} ))

temp=$(sh /usr/local/opnsense/scripts/OPNsense/TelegramAlerts/temp-check.sh | sed -n 's/^CPU \([0-9]*\)C.*/\1/p')
disk=$(df -h / | awk 'NR==2 {print $5 " used of " $2}')
mem=$(sysctl -n hw.physmem vm.stats.vm.v_free_count hw.pagesize vm.stats.vm.v_inactive_count | xargs | awk '{printf "%.0f%%", 100 - ($2 + $4) * $3 / $1 * 100}')
upd=$(cat "$STATE/update.out" 2>/dev/null | sed 's/ Install via.*//' || true)
[ -n "$upd" ] || upd="not checked yet"
wg_n=$(wg show all latest-handshakes 2>/dev/null | awk -v n="$now" '$3 > 0 && n - $3 < 180' | wc -l | tr -d ' ')

echo "$now" > "$STATE/daily.last"
row() { printf '%-10s %s\n' "$1" "$2"; }
DESC=$(
    row "Uptime"   "${up_d}d ${up_h}h"
    row "WAN"      "${gw:-n/a}"
    row "Outages"  "${out_n} (${out_m} min total)"
    row "DNS"      "${dns} queries"
    row "IDS"      "${ids} alerts"
    row "Devices"  "${newdev} new"
    row "VPN"      "${wg_n} peers online"
    row "CPU"      "${temp:-?} C"
    row "Memory"   "${mem} used"
    row "Disk"     "${disk}"
    row "Firmware" "${upd}"
)
MONIT_SERVICE="daily" MONIT_EVENT="Daily summary" MONIT_DESCRIPTION="$DESC" "$SEND"
exit 0
