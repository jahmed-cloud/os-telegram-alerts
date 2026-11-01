#!/bin/sh
# configd discards output of scripts that exit non-zero; always exit 0 so the
# GUI can show the real error text.
/usr/local/opnsense/scripts/OPNsense/TelegramAlerts/send.sh --test
exit 0
