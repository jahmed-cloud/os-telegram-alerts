#!/bin/sh
# Installs the Telegram Alerts GUI into OPNsense. Run as root from the extracted folder.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
SRC="$HERE/src/opnsense"
DST=/usr/local/opnsense

if [ "$(id -u)" != "0" ]; then echo "Run as root"; exit 1; fi
if [ ! -d "$DST/mvc" ]; then echo "This does not look like OPNsense"; exit 1; fi

echo "Copying files..."
cp -R "$SRC/mvc/"     "$DST/mvc/"
cp -R "$SRC/service/" "$DST/service/"
cp -R "$SRC/scripts/" "$DST/scripts/"
cp -R "$SRC/www/"     "$DST/www/"

chmod 755 "$DST/scripts/OPNsense/TelegramAlerts/"*.sh

# Stable paths used by the Monit tests
ln -sf "$DST/scripts/OPNsense/TelegramAlerts/send.sh"       /usr/local/bin/tg-alert.sh
ln -sf "$DST/scripts/OPNsense/TelegramAlerts/temp-check.sh" /usr/local/bin/tg-temp-check.sh
ln -sf "$DST/scripts/OPNsense/TelegramAlerts/net-watch.sh"    /usr/local/bin/tg-net-watch.sh
ln -sf "$DST/scripts/OPNsense/TelegramAlerts/update-check.sh" /usr/local/bin/tg-update-check.sh
ln -sf "$DST/scripts/OPNsense/TelegramAlerts/events.sh"       /usr/local/bin/tg-events.sh
ln -sf "$DST/scripts/OPNsense/TelegramAlerts/smart-check.sh"  /usr/local/bin/tg-smart-check.sh
ln -sf "$DST/scripts/OPNsense/TelegramAlerts/wan-quality.sh"  /usr/local/bin/tg-wan-quality.sh

echo "Reloading configd, menu and ACL cache..."
service configd restart >/dev/null
rm -f /tmp/opnsense_menu_cache.xml /tmp/opnsense_acl_cache.json /var/lib/php/tmp/opnsense_menu_cache.xml /var/lib/php/tmp/opnsense_acl_cache.json
/usr/local/sbin/configctl template reload OPNsense/TelegramAlerts >/dev/null
/usr/local/sbin/configctl telegramalerts secure >/dev/null

echo "Done. Open Services > Telegram Alerts in the GUI (refresh the page)."
