#!/bin/sh
# One-command deploy from a workstation (Linux, macOS, Git Bash on Windows):
#   ./deploy.sh                    # root@10.99.99.1
#   ./deploy.sh root@192.168.1.1   # another firewall
# Streams this folder over SSH and runs install.sh on the firewall. Settings in
# config.xml are kept. Set SSH_KEY to use a specific private key.
set -e
TARGET=${1:-root@10.99.99.1}
KEY=${SSH_KEY:-$HOME/.ssh/id_ed25519_gateway}
cd "$(dirname "$0")"

set -- -o ConnectTimeout=10
[ -f "$KEY" ] && set -- "$@" -i "$KEY"

echo "Deploying to $TARGET..."
tar -czf - install.sh uninstall.sh src | ssh "$@" "$TARGET" \
    "sh -c 'rm -rf /tmp/os-telegram-alerts && mkdir -p /tmp/os-telegram-alerts && tar -xzf - -C /tmp/os-telegram-alerts && sh /tmp/os-telegram-alerts/install.sh'"
