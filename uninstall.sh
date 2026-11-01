#!/bin/sh
# Removes the Telegram Alerts GUI. Settings stay in config.xml until removed there.
DST=/usr/local/opnsense
rm -rf "$DST/mvc/app/models/OPNsense/TelegramAlerts" \
       "$DST/mvc/app/controllers/OPNsense/TelegramAlerts" \
       "$DST/mvc/app/views/OPNsense/TelegramAlerts" \
       "$DST/service/templates/OPNsense/TelegramAlerts" \
       "$DST/scripts/OPNsense/TelegramAlerts" \
       "$DST/service/conf/actions.d/actions_telegramalerts.conf" \
       "$DST/www/js/widgets/TgNetworkHealth.js" "$DST/www/js/widgets/TgClients.js" \
       "$DST/www/js/widgets/TgSecurity.js" "$DST/www/js/widgets/Metadata/TelegramAlerts.xml" \
       /tmp/telegramalerts_dashboard.json \
       /usr/local/etc/telegram-alerts.env \
       /usr/local/bin/tg-alert.sh /usr/local/bin/tg-temp-check.sh \
       /usr/local/bin/tg-net-watch.sh /usr/local/bin/tg-update-check.sh /usr/local/bin/tg-events.sh /usr/local/bin/tg-smart-check.sh /usr/local/bin/tg-wan-quality.sh /var/db/telegram-alerts
service configd restart >/dev/null
rm -f /tmp/opnsense_menu_cache.xml /tmp/opnsense_acl_cache.json /var/lib/php/tmp/opnsense_menu_cache.xml /var/lib/php/tmp/opnsense_acl_cache.json
echo "Removed. Disable or delete the TG_* Monit tests and the cpu_temp service if you no longer need them."
