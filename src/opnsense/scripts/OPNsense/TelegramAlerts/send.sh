#!/bin/sh
# Sends a formatted Telegram message (HTML). Called by Monit (exec action,
# MONIT_* env vars set), by the plugin scripts, or by configd with --test.
PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
ENV=/usr/local/etc/telegram-alerts.env
if [ ! -r "$ENV" ]; then
    echo "Settings not found - save the Telegram Alerts page first"
    exit 1
fi
. "$ENV"

if [ "$1" = "--test" ]; then
    MONIT_SERVICE="test"
    MONIT_EVENT="Test message"
    MONIT_DESCRIPTION="Telegram alerts are working."
elif [ "$TG_ENABLED" != "1" ]; then
    exit 0
fi

if [ -z "$TG_TOKEN" ] || [ -z "$TG_CHAT" ]; then
    echo "Bot token or chat ID is not set"
    exit 1
fi

esc() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

HOST=$(hostname)
SVC="${MONIT_SERVICE:-unknown}"
EVT="${MONIT_EVENT:-}"
DESC="${MONIT_DESCRIPTION:-}"

# Friendly names for Monit services
case "$SVC" in
    "$HOST"|"$(hostname -s)") NAME="System resources" ;;
    RootFs)        NAME="Disk space" ;;
    gateway_alert) NAME="WAN gateway" ;;
    cpu_temp)      NAME="CPU temperature" ;;
    fw_update)     NAME="Firmware" ;;
    smart_health)  NAME="Disk health" ;;
    wan_quality)   NAME="WAN quality" ;;
    *)             NAME="" ;;
esac

# Severity tag
case "$SVC:$EVT" in
    test:*)                                   TAG="TEST" ;;
    daily:*)                                  TAG="REPORT" ;;
    *succeeded*|*"back online"*|*recovered*|*"Exists"*) TAG="RESOLVED" ;;
    *"Failed login"*|ids:*)                   TAG="SECURITY" ;;
    fw_update:*)                              TAG="UPDATE" ;;
    net_watch:*|auth:*|config:*|dhcp:*|wireguard:*) TAG="INFO" ;;
    *)                                        TAG="ALERT" ;;
esac

if [ -n "$NAME" ]; then
    TITLE="$NAME"
    [ -n "$EVT" ] && TITLE="$NAME - $EVT"
else
    TITLE="${EVT:-$SVC}"
fi

NOW=$(date '+%a %d %b %Y, %H:%M %Z')
MSG="<b>${TAG}</b>  |  <b>$(esc "$TITLE")</b>
<i>$(esc "${TG_PREFIX} ${HOST}")</i>
"
[ -n "$DESC" ] && MSG="${MSG}
<pre>$(esc "$DESC")</pre>
"
MSG="${MSG}
<i>${NOW}</i>"

post() {  # $1 text, $2 parse mode (optional)
    if [ -n "$2" ]; then
        curl -s -m 15 "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
            --data-urlencode "chat_id=${TG_CHAT}" --data-urlencode "parse_mode=$2" \
            --data-urlencode "disable_web_page_preview=true" --data-urlencode "text=$1" 2>&1
    else
        curl -s -m 15 "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
            --data-urlencode "chat_id=${TG_CHAT}" --data-urlencode "text=$1" 2>&1
    fi
}

mark_sent() { mkdir -p /var/db/telegram-alerts && printf '%s\t%s\n' "$(date +%s)" "${TAG} | ${TITLE}" > /var/db/telegram-alerts/last_sent; }
RESP=$(post "$MSG" HTML)
case "$RESP" in
    *'"ok":true'*) mark_sent; echo "OK"; exit 0 ;;
    *"can't parse entities"*)
        # Fall back to plain text if Telegram rejects the markup
        PLAIN="${TAG} | ${TITLE}
${TG_PREFIX} ${HOST}

${DESC}

${NOW}"
        RESP=$(post "$PLAIN")
        case "$RESP" in *'"ok":true'*) mark_sent; echo "OK"; exit 0 ;; esac ;;
esac

if [ -z "$RESP" ]; then
    echo "No response from api.telegram.org (DNS, firewall or network problem)"
else
    DESC_ERR=$(echo "$RESP" | sed -n 's/.*"description":"\([^"]*\)".*/\1/p')
    echo "Telegram API error: ${DESC_ERR:-$RESP}"
fi
exit 1
