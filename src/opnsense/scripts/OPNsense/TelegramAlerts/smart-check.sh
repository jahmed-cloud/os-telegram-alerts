#!/bin/sh
# Monit program check (service "smart_health"): exit 1 if any disk fails SMART.
PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
command -v smartctl >/dev/null || { echo "smartctl not installed (os-smart)"; exit 0; }
rc=0; out=""
for d in $(sysctl -n kern.disks); do
    case "$d" in cd*|md*) continue;; esac
    if smartctl -H "/dev/$d" | grep -qE 'PASSED|OK$'; then
        out="$out $d:OK"
    else
        out="$out $d:FAILING"; rc=1
    fi
done
echo "SMART:${out}"
exit $rc
