<?php
/*
 * Collects data for the Telegram Alerts dashboard widgets and prints JSON.
 * Kept dependency-free (no OPNsense bootstrap) and fast: called every 30 s.
 */
$STATE = '/var/db/telegram-alerts';
$now = time();
$out = ['generated' => $now];

function run($cmd)
{
    $o = [];
    @exec($cmd . ' 2>/dev/null', $o);
    return $o;
}
function first_line($file)
{
    return is_readable($file) ? trim((string)@file_get_contents($file)) : '';
}
function ago($ts, $now)
{
    if (!$ts) {
        return 'never';
    }
    $d = $now - $ts;
    if ($d < 90) {
        return $d . 's ago';
    }
    if ($d < 5400) {
        return round($d / 60) . 'm ago';
    }
    if ($d < 172800) {
        return round($d / 3600) . 'h ago';
    }
    return round($d / 86400) . 'd ago';
}

/* ---------- interfaces from config.xml ---------- */
$ifmap = [];
$cfg = @simplexml_load_file('/conf/config.xml');
if ($cfg && isset($cfg->interfaces)) {
    foreach ($cfg->interfaces->children() as $key => $node) {
        $dev = (string)$node->if;
        if ($dev !== '') {
            $ifmap[$dev] = (string)$node->descr !== '' ? (string)$node->descr : strtoupper($key);
        }
    }
}

/* ---------- health ---------- */
$boot = 0;
foreach (run('sysctl -n kern.boottime') as $l) {
    if (preg_match('/sec = (\d+)/', $l, $m)) {
        $boot = (int)$m[1];
    }
}
$up = $now - $boot;
$health = [
    'uptime' => sprintf('%dd %dh %dm', intdiv($up, 86400), intdiv($up % 86400, 3600), intdiv($up % 3600, 60)),
    'internet' => first_line("$STATE/wan") === 'down' ? 'down' : 'up',
];
$gw = run('php /usr/local/opnsense/scripts/OPNsense/TelegramAlerts/gw-stats.php');
if (!empty($gw)) {
    $p = preg_split('/\s+/', trim($gw[0]));
    $health['gateway'] = $p[0] ?? '';
    $health['latency'] = isset($p[1]) ? $p[1] . ' ms' : 'n/a';
    $health['loss'] = isset($p[2]) ? $p[2] . ' %' : 'n/a';
    $health['gw_status'] = $p[3] ?? '';
}
$wanip = '';
$route = run('route -n get default');
foreach ($route as $l) {
    if (preg_match('/interface:\s+(\S+)/', $l, $m)) {
        foreach (run('ifconfig ' . escapeshellarg($m[1]) . ' inet') as $il) {
            if (preg_match('/inet (\S+)/', $il, $mm)) {
                $wanip = $mm[1];
                break;
            }
        }
    }
}
$health['wan_ip'] = $wanip ?: 'n/a';
$o24 = 0;
$omin = 0;
$last = '';
if (is_readable("$STATE/outages.log")) {
    foreach (file("$STATE/outages.log", FILE_IGNORE_NEW_LINES) as $l) {
        $p = preg_split('/\s+/', trim($l));
        if (count($p) >= 3) {
            if ((int)$p[1] >= $now - 86400) {
                $o24++;
                $omin += (int)$p[2];
            }
            $last = date('d M H:i', (int)$p[0]) . ' (' . (int)$p[2] . ' min)';
        }
    }
}
$health['outages_24h'] = $o24 . ($o24 ? " ($omin min)" : '');
$health['last_outage'] = $last ?: 'none recorded';
$temp = '';
foreach (['hw.acpi.thermal.tz0.temperature', 'dev.cpu.0.temperature'] as $oid) {
    $t = run('sysctl -n ' . $oid);
    if (!empty($t) && preg_match('/([\d.]+)/', $t[0], $m)) {
        $temp = round((float)$m[1]) . ' C';
        break;
    }
}
$health['cpu_temp'] = $temp ?: 'n/a';
$out['health'] = $health;

/* ---------- clients ---------- */
$per = [];
foreach (run('arp -an') as $l) {
    if (preg_match('/\(([\d.]+)\) at ([0-9a-f:]{17}) on (\S+)(.*)$/i', $l, $m)) {
        if (stripos($m[4], 'permanent') !== false) {
            continue;   // the firewall's own addresses
        }
        $name = $ifmap[$m[3]] ?? $m[3];
        $per[$name] = ($per[$name] ?? 0) + 1;
    }
}
ksort($per);
$leases = 0;
foreach (['/var/db/dnsmasq.leases', '/var/lib/misc/dnsmasq.leases'] as $lf) {
    if (is_readable($lf)) {
        $leases = count(array_filter(file($lf, FILE_IGNORE_NEW_LINES)));
        break;
    }
}
$wg_total = 0;
$wg_on = 0;
foreach (run('wg show all dump') as $l) {
    $p = explode("\t", $l);
    if (count($p) >= 9) {
        $wg_total++;
        if ((int)$p[5] > 0 && $now - (int)$p[5] < 180) {
            $wg_on++;
        }
    }
}
$recent = [];
if (is_readable("$STATE/new_devices.log")) {
    $lines = array_slice(file("$STATE/new_devices.log", FILE_IGNORE_NEW_LINES), -5);
    foreach (array_reverse($lines) as $l) {
        $p = preg_split('/\s+/', trim($l), 4);
        if (count($p) >= 3) {
            $recent[] = ($p[3] ?? '*') . ' ' . $p[1] . ' (' . ago((int)$p[0], $now) . ')';
        }
    }
}
$out['clients'] = [
    'online' => array_sum($per),
    'per_network' => $per,
    'dhcp_leases' => $leases,
    'vpn' => $wg_on . ' of ' . $wg_total . ' peers online',
    'recent' => $recent,
];

/* ---------- security ---------- */
$fh = 'n/a';
$tables = run('pfctl -vvsT');
for ($i = 0; $i < count($tables); $i++) {
    if (preg_match('/\sBLOCK_FIREHOL_L1$/', $tables[$i])) {
        for ($j = $i + 1; $j < min($i + 12, count($tables)); $j++) {
            if (preg_match('/In\/Block:\s+\[\s*Packets:\s*(\d+)/', $tables[$j], $m)) {
                $fh = number_format((int)$m[1]) . ' packets';
                break 2;
            }
        }
    }
}
$today = date('Y-m-d');
$ids = 0;
if (is_readable('/var/log/suricata/eve.json')) {
    $r = run('grep -c ' . escapeshellarg('"timestamp":"' . $today) . ' /var/log/suricata/eve.json');
    $all = (int)($r[0] ?? 0);
    $r2 = run('grep ' . escapeshellarg('"timestamp":"' . $today) . ' /var/log/suricata/eve.json | grep -c \'"event_type":"alert"\'');
    $ids = (int)($r2[0] ?? 0);
}
$failed = 0;
foreach (['/var/log/audit/latest.log', '/var/log/system/latest.log'] as $lf) {
    if (is_readable($lf)) {
        $r = run("grep -cE 'authentication error|Failed password|Invalid user|authentication failure' " . escapeshellarg($lf));
        $failed += (int)($r[0] ?? 0);
    }
}
$who = '';
$when = 0;
if ($cfg && isset($cfg->revision)) {
    $who = (string)$cfg->revision->username;
    $when = (int)$cfg->revision->time;
}
$monit_ok = 0;
$monit_bad = [];
foreach (run('/usr/local/bin/monit -B summary') as $l) {
    if (preg_match("/^\s*(\S+)\s+(OK|Status failed|Resource limit matched|Does not exist|Not monitored|Initializing|.+?)\s{2,}(System|Filesystem|Program|Process|File|Host|Network)\s*$/", $l, $m)) {
        if ($m[2] === 'OK' || $m[2] === 'Initializing') {
            $monit_ok++;
        } else {
            $monit_bad[] = $m[1] . ': ' . $m[2];
        }
    }
}
$lastsent = first_line("$STATE/last_sent");
$ls = explode("\t", $lastsent, 2);
$out['security'] = [
    'firehol' => $fh,
    'ids_today' => $ids,
    'failed_logins_today' => $failed,
    'last_change' => $when ? (ago($when, $now) . ' by ' . ($who ?: 'unknown')) : 'n/a',
    'checks' => $monit_ok . ' OK' . (count($monit_bad) ? ', ' . count($monit_bad) . ' failing' : ''),
    'failing' => $monit_bad,
    'last_alert' => count($ls) == 2 ? ($ls[1] . ' (' . ago((int)$ls[0], $now) . ')') : 'none yet',
];

echo json_encode($out);
