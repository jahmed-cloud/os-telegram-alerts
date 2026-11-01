# OPNsense Telegram Alerts

Telegram notifications and dashboard widgets for OPNsense, configured from the GUI
under **Services > Telegram Alerts**. Every alert has its own switch; Save creates,
enables or disables the matching Monit checks and cron job for you.

Tested on OPNsense 26.7 (FreeBSD 15).

## What you get

| Group | Alerts |
|---|---|
| System health | CPU > 90% / memory > 85% for 5 min, root disk > 80%, CPU temperature limit, disk SMART failure, firmware updates available (checked every 6 h) |
| Internet | Router started (power loss / unplanned reboot), internet back online with the outage window, gateway down, WAN latency / packet loss over your limits |
| Security | Web GUI and SSH logins, failed-login summaries with source IPs, configuration changes (who and what), new devices on DHCP, high-severity Suricata alerts, WireGuard peer connect / disconnect |
| Reports | Daily summary at the hour you choose; encrypted (AES-256) `config.xml` backup sent to the chat after changes |

Dashboard widgets (Lobby > Dashboard > add widget): **Network Health**, **Clients**,
**Security and Alerts**.

Messages that cannot be delivered during an outage are queued and sent when the
internet is back.

## Deploy in one click

You need SSH enabled on the firewall (System > Settings > Administration > Secure
Shell, root login with a key). The default target is `root@10.99.99.1`; pass
another one as the first argument.

**Windows:** double-click `deploy.cmd` (or run `deploy.cmd root@192.168.1.1`).
It uses the `ssh` and `tar` built into Windows 10/11.

**Linux / macOS / Git Bash:**

```sh
./deploy.sh                    # root@10.99.99.1
./deploy.sh root@192.168.1.1
```

Both scripts use `~/.ssh/id_ed25519_gateway` when it exists; set `SSH_KEY` to use
another key.

**Directly on the firewall** (SSH shell), straight from GitHub:

```sh
fetch -o - https://github.com/jahmed-cloud/os-telegram-alerts/archive/refs/heads/main.tar.gz | tar -xzf - -C /tmp && sh /tmp/os-telegram-alerts-main/install.sh
```

Re-running any of these upgrades in place; your settings stay in `config.xml`.
The installer checks script and PHP syntax first and installs nothing if a file is broken.

## First-time setup

1. Create a bot with [@BotFather](https://t.me/BotFather) (`/newbot`) and copy the token.
2. Send your bot any message, then open
   `https://api.telegram.org/bot<TOKEN>/getUpdates` and copy `chat.id`
   (group chats start with `-`).
3. Refresh the GUI, open **Services > Telegram Alerts**, tick **Enable alerts**,
   paste the token and chat ID, choose the alerts you want, **Save**.
4. Click **Send test message**.

## Encrypted config backup

Turn on **Encrypted config backup** and set a 16+ character password (keep it in
your password manager). After configuration changes (at most every 10 minutes) the
chat receives `<host>-config-<date>.xml.enc`. To restore:

```sh
openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -md sha256 -in FILE.xml.enc -out config.xml
```

The decrypted file holds every secret on the firewall.

## How it works

- Settings: `config.xml` (`//OPNsense/TelegramAlerts`), rendered to
  `/usr/local/etc/telegram-alerts.env` (mode 600). The bot token is part of config backups.
- Monit runs the checks (`cpu_temp`, `smart_health`, `fw_update`, `net_watch`,
  `wan_quality`, `tg_events`) and calls `/usr/local/bin/tg-alert.sh` through the
  `TG_*` tests. Built-in services (`$HOST`, `RootFs`, `gateway_alert`) only get
  the `TG_*` tests attached or detached; nothing else of yours is changed.
- Cron runs `configctl telegramalerts daily` for the daily summary.
- State lives in `/var/db/telegram-alerts`.

Useful commands on the firewall:

```sh
configctl telegramalerts test        # send a test message
configctl telegramalerts daily       # send the daily summary now
configctl telegramalerts backup      # send an encrypted backup now
monit summary                        # state of the checks
```

## Troubleshooting

- **No menu entry:** refresh the browser (the installer clears the menu cache).
- **Test fails with "No response":** the firewall cannot reach `api.telegram.org`
  (DNS or outbound rules).
- **Save shows warnings:** they come from Monit or cron validation; see
  Services > Monit > Log File.
- **Alerts stopped after a firmware upgrade:** a major upgrade can remove files
  that are not pkg-managed. Deploy again; settings are kept.
- **Dashboard blank after a firmware update:** open Lobby > Dashboard after every
  update. The widgets are not pkg-managed and can be removed or broken by a new
  widget API. Deploy again; `sh tests/check-widgets.sh` must pass first (widget
  JS must not `import`: the base classes are globals).

## Uninstall

```sh
sh /usr/local/opnsense/scripts/OPNsense/TelegramAlerts/uninstall.sh
```

This removes the files. Delete the `TG_*` Monit tests, the custom Monit services
(Services > Monit) and the cron job if you no longer want them.
