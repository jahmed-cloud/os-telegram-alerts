#!/bin/sh
# Monit program check (service "tg_events"), runs every cycle, always exits 0.
# Reads only what is new since the previous run; first run learns state silently.
PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
ENV=/usr/local/etc/telegram-alerts.env
SEND=/usr/local/opnsense/scripts/OPNsense/TelegramAlerts/send.sh
STATE=/var/db/telegram-alerts
mkdir -p "$STATE"; chmod 700 "$STATE"
[ -r "$ENV" ] && . "$ENV"
[ "$TG_ENABLED" = "1" ] || { echo "alerts disabled"; exit 0; }

notify() { MONIT_SERVICE="$1" MONIT_EVENT="$2" MONIT_DESCRIPTION="$3" "$SEND" >/dev/null 2>&1; }

# Print bytes appended to $1 since last call (tracked per key $2).
newdata() {
    f=$(realpath "$1" 2>/dev/null) || return 0
    [ -f "$f" ] || return 0
    ino=$(stat -f %i "$f"); size=$(stat -f %z "$f")
    st="$STATE/off.$2"; pino=""; poff=0
    [ -f "$st" ] && read pino poff < "$st"
    echo "$ino $size" > "$st"
    if [ -z "$pino" ]; then return 0; fi                       # first run: no backlog
    if [ "$pino" != "$ino" ] || [ "$poff" -gt "$size" ]; then poff=0; fi   # rotated
    [ "$size" -gt "$poff" ] && tail -c +"$((poff + 1))" "$f" | head -c "$((size - poff))"
    return 0
}

# --- Admin logins (web GUI + SSH)
if [ "${TG_LOGINS:-1}" = "1" ]; then
    new=$( { newdata /var/log/audit/latest.log audit; newdata /var/log/system/latest.log system; } )
    ok=$(printf '%s\n' "$new" | grep -E 'authenticated successfully|Accepted (password|publickey|keyboard-interactive)' \
         | sed -E 's/^.*(user [^ ]+ authenticated successfully for [^ ]+|Accepted [^ ]+ for [^ ]+ from [0-9a-fA-F.:]+).*$/\1/' | sort -u | head -5)
    bad=$(printf '%s\n' "$new" | grep -cE 'authentication error|Failed password|Invalid user|authentication failure')
    if [ -n "$ok" ]; then
        notify "auth" "Admin login" "$ok"
    fi
    if [ "$bad" -gt 0 ]; then
        src=$(printf '%s\n' "$new" | grep -E 'authentication error|Failed password|Invalid user' \
              | grep -oE '(from|for .* from) [0-9a-fA-F.:]+' | grep -oE '[0-9a-fA-F.:]+$' | sort | uniq -c | sort -rn | head -3 | awk '{printf "%s (%s) ", $2, $1}')
        notify "auth" "Failed login attempts" "${bad} failed admin login attempt(s) in the last minute. Sources: ${src:-unknown}"
    fi
fi

# --- Configuration changes
if [ "${TG_CONFIGCHANGE:-1}" = "1" ] && [ -f /conf/config.xml ]; then
    m=$(stat -f %m /conf/config.xml)
    pm=$(cat "$STATE/config.mtime" 2>/dev/null)
    echo "$m" > "$STATE/config.mtime"
    if [ -n "$pm" ] && [ "$m" != "$pm" ]; then
        rev=$(sed -n '/<revision>/,/<\/revision>/p' /conf/config.xml | head -20)
        who=$(printf '%s\n' "$rev" | sed -n 's:.*<username>\(.*\)</username>.*:\1:p' | head -1)
        what=$(printf '%s\n' "$rev" | sed -n 's:.*<description>\(.*\)</description>.*:\1:p' | head -1)
        notify "config" "Configuration changed" "By: ${who:-unknown}
${what:-no description}"
        [ "${TG_BACKUP:-0}" = "1" ] && touch "$STATE/backup.pending"
    fi
fi

# --- New devices (first DHCP lease for a MAC)
if [ "${TG_NEWDEVICES:-1}" = "1" ]; then
    for L in /var/db/dnsmasq.leases /var/lib/misc/dnsmasq.leases; do [ -f "$L" ] && break; done
    if [ -f "$L" ]; then
        known="$STATE/known_macs"
        first=0; [ -f "$known" ] || { first=1; : > "$known"; }
        while read -r exp mac ip host rest; do
            # IPv4 leases only: skips the "duid" line and DHCPv6 leases (IAID in field 2)
            echo "$mac" | grep -qiE '^([0-9a-f]{2}:){5}[0-9a-f]{2}$' || continue
            if ! grep -qix "$mac" "$known"; then
                echo "$mac" >> "$known"
                [ "$first" = "1" ] && continue
                echo "$(date +%s) $ip $mac ${host:-*}" >> "$STATE/new_devices.log"
                notify "dhcp" "New device on network" "IP: ${ip}
MAC: ${mac}
Hostname: ${host:-*}"
            fi
        done < "$L"
    fi
fi

# --- Suricata high-severity alerts
if [ "${TG_IDS:-1}" = "1" ]; then
    hi=$(newdata /var/log/suricata/eve.json eve | grep '"event_type":"alert"' | grep -E '"severity":1[,}]')
    n=$(printf '%s\n' "$hi" | grep -c .)
    if [ "$n" -gt 0 ]; then
        sigs=$(printf '%s\n' "$hi" | sed -n 's/.*"signature":"\([^"]*\)".*/\1/p' | sort | uniq -c | sort -rn | head -3 | sed 's/^ *//')
        srcs=$(printf '%s\n' "$hi" | sed -n 's/.*"src_ip":"\([^"]*\)".*/\1/p' | sort | uniq -c | sort -rn | head -3 | awk '{printf "%s (%s) ", $2, $1}')
        notify "ids" "IDS: ${n} high-severity alert(s)" "Top signatures:
${sigs}
Sources: ${srcs}"
    fi
fi

# --- Encrypted config backup (pending after a change, rate limited in backup.sh)
if [ "${TG_BACKUP:-0}" = "1" ] && [ -f "$STATE/backup.pending" ]; then
    /usr/local/opnsense/scripts/OPNsense/TelegramAlerts/backup.sh >/dev/null 2>&1
fi

# --- WireGuard peers: connected = handshake within 180 s
if [ "${TG_WIREGUARD:-1}" = "1" ] && command -v wg >/dev/null; then
    names=$(php -r '$x=@simplexml_load_file("/conf/config.xml"); if($x && isset($x->OPNsense->wireguard->client->clients)) foreach($x->OPNsense->wireguard->client->clients->client as $c) echo $c->pubkey," ",str_replace(" ","_",(string)$c->name),"\n";' 2>/dev/null)
    now=$(date +%s)
    wg show all dump 2>/dev/null | awk 'NF >= 9 {print $2, $4, $6}' | while read -r pub ep hs; do
        id=$(echo "$pub" | tr '/+=' '_-.')
        st="$STATE/wg.$id"
        prev=$(cat "$st" 2>/dev/null || echo down)
        if [ "$hs" -gt 0 ] && [ $((now - hs)) -lt 180 ]; then cur=up; else cur=down; fi
        [ "$cur" = "$prev" ] && continue
        echo "$cur" > "$st"
        name=$(printf '%s\n' "$names" | awk -v p="$pub" '$1 == p {print $2}')
        if [ "$cur" = "up" ]; then
            notify "wireguard" "VPN peer connected" "Peer: ${name:-unknown key ${pub%${pub#????????}}...}
From: ${ep}"
        else
            notify "wireguard" "VPN peer disconnected" "Peer: ${name:-unknown key ${pub%${pub#????????}}...}"
        fi
    done
fi

echo "events checked"
exit 0
