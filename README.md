# OPNsense Telegram Alerts (GUI)

Adds **Services > Telegram Alerts** (v1.4: alerts with per-alert switches synced to Monit and cron, plus dashboard widgets Network Health, Clients, Security and Alerts).
CPU temperature limit, Save, and a "Send test message" button.
Monit triggers alerts via `/usr/local/bin/tg-alert.sh` (tests TG_CPU, TG_MEM,
TG_DISK, TG_STATUS; services $HOST, RootFs, gateway_alert, cpu_temp).

## Install
    scp os-telegram-alerts.tar.gz root@10.99.99.1:/root/
    ssh root@10.99.99.1
    cd /root && tar xzf os-telegram-alerts.tar.gz && sh os-telegram-alerts/install.sh

Then: refresh the GUI > Services > Telegram Alerts > fill in > Save > Send test message.
Then: Services > Monit > Settings > Apply.

## Notes
- Settings live in config.xml (token is included in config backups).
- Files are not pkg-managed: re-run install.sh after a reinstall or if a major
  upgrade removes them. Settings survive in config.xml.
- Uninstall: sh os-telegram-alerts/uninstall.sh
