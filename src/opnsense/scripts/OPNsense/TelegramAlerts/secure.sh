#!/bin/sh
ENV=/usr/local/etc/telegram-alerts.env
if [ -f "$ENV" ]; then
    chown root:wheel "$ENV"
    chmod 600 "$ENV"
fi
echo "OK"
