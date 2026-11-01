#!/bin/sh
# Installs the Telegram Alerts GUI into OPNsense. Run as root from the extracted folder.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
SRC="$HERE/src/opnsense"
DST=/usr/local/opnsense

if [ "$(id -u)" != "0" ]; then echo "Run as root"; exit 1; fi
if [ ! -d "$DST/mvc" ]; then echo "This does not look like OPNsense"; exit 1; fi

# Files copied from Windows may carry CRLF line endings, which break sh and configd.
find "$SRC" "$HERE/uninstall.sh" -type f -exec sed -i '' 's/\r$//' {} +

echo "Checking syntax..."
for f in "$SRC"/scripts/OPNsense/TelegramAlerts/*.sh; do
    sh -n "$f" || { echo "Syntax error in $f, nothing installed"; exit 1; }
done
for f in $(find "$SRC" -name '*.php'); do
    php -l "$f" >/dev/null || { echo "Syntax error in $f, nothing installed"; exit 1; }
done

echo "Copying files..."
cp -R "$SRC/mvc/"     "$DST/mvc/"
cp -R "$SRC/service/" "$DST/service/"
cp -R "$SRC/scripts/" "$DST/scripts/"
cp -R "$SRC/www/"     "$DST/www/"
cp "$HERE/uninstall.sh" "$DST/scripts/OPNsense/TelegramAlerts/uninstall.sh"

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

# Earlier versions learned the DHCPv6 "duid" line as a device; keep only MAC addresses.
K=/var/db/telegram-alerts/known_macs
if [ -f "$K" ]; then
    grep -iE '^([0-9a-f]{2}:){5}[0-9a-f]{2}$' "$K" > "$K.tmp" || true
    mv "$K.tmp" "$K"
fi
rm -f /tmp/telegramalerts_dashboard.json

echo "Done. Open Services > Telegram Alerts in the GUI (refresh the page)."
