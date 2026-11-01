#!/bin/sh
# Sends config.xml to Telegram encrypted with AES-256-CBC (PBKDF2, 200k iterations).
# Called by events.sh after config changes (rate limited) or with --force (configd/cron).
PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
ENV=/usr/local/etc/telegram-alerts.env
STATE=/var/db/telegram-alerts
mkdir -p "$STATE"; chmod 700 "$STATE"
[ -r "$ENV" ] && . "$ENV"
[ "$TG_ENABLED" = "1" ] && [ "$TG_BACKUP" = "1" ] || { echo "backup disabled"; exit 0; }
[ ${#TG_BACKUPPASS} -ge 16 ] || { echo "backup password not set (16+ chars)"; exit 0; }

now=$(date +%s)
if [ "$1" != "--force" ]; then
    last=$(cat "$STATE/backup.last" 2>/dev/null || echo 0)
    [ $((now - last)) -ge 600 ] || { touch "$STATE/backup.pending"; echo "backup deferred"; exit 0; }
fi

host=$(hostname -s)
out="$STATE/${host}-config-$(date '+%Y%m%d-%H%M').xml.enc"
umask 077
if ! TG_BACKUPPASS="$TG_BACKUPPASS" openssl enc -aes-256-cbc -pbkdf2 -iter 200000 -md sha256 -salt \
        -in /conf/config.xml -out "$out" -pass env:TG_BACKUPPASS 2>/dev/null; then
    echo "encryption failed"; rm -f "$out"; exit 0
fi
sha=$(sha256 -q /conf/config.xml)
resp=$(curl -s -m 60 "https://api.telegram.org/bot${TG_TOKEN}/sendDocument" \
    -F "chat_id=${TG_CHAT}" -F "document=@${out}" \
    -F "caption=${TG_PREFIX} ${host} config backup $(date '+%F %T %Z') (AES-256, sha256 of plaintext ${sha%${sha#????????????}})" 2>&1)
rm -f "$out"
case "$resp" in
    *'"ok":true'*) echo "$now" > "$STATE/backup.last"; rm -f "$STATE/backup.pending"; echo "OK";;
    *) touch "$STATE/backup.pending"; echo "backup upload failed";;
esac
exit 0
