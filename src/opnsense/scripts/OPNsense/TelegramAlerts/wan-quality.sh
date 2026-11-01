#!/bin/sh
# Monit program check (service "wan_quality"): exit 1 when any gateway's
# latency or loss is above the configured limits.
PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
ENV=/usr/local/etc/telegram-alerts.env
[ -r "$ENV" ] && . "$ENV"
LMAX=${TG_LATENCYMAX:-100}; PMAX=${TG_LOSSMAX:-5}
stats=$(php /usr/local/opnsense/scripts/OPNsense/TelegramAlerts/gw-stats.php)
[ -n "$stats" ] || { echo "no gateway statistics (monitoring disabled?)"; exit 0; }
rc=0; out=""
while read -r name delay loss status; do
    [ -n "$name" ] || continue
    bad=$(echo "$delay $loss $LMAX $PMAX" | awk '{print ($1 > $3 || $2 > $4) ? 1 : 0}')
    out="$out $name: ${delay}ms ${loss}% loss;"
    [ "$bad" = "1" ] && rc=1
done <<EOT
$stats
EOT
echo "WAN quality (limits ${LMAX}ms / ${PMAX}%):${out}"
exit $rc
