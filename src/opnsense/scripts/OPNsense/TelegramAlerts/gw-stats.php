<?php
// Prints "name delay_ms loss_pct status" for each gateway with numeric stats.
exec('/usr/local/sbin/pluginctl -r return_gateways_status 2>/dev/null', $out);
$data = json_decode(implode("\n", $out), true);
$found = [];
$walk = function ($node, $key) use (&$walk, &$found) {
    if (!is_array($node)) {
        return;
    }
    if (isset($node['delay']) && isset($node['loss'])) {
        $name = $node['name'] ?? $key;
        $d = floatval(preg_replace('/[^0-9.]/', '', (string)$node['delay']));
        $l = floatval(preg_replace('/[^0-9.]/', '', (string)$node['loss']));
        if (preg_match('/[0-9]/', (string)$node['delay'])) {
            $found[$name] = sprintf("%s %.1f %.1f %s", $name, $d, $l, $node['status'] ?? 'unknown');
        }
        return;
    }
    foreach ($node as $k => $v) {
        $walk($v, is_string($k) ? $k : $key);
    }
};
$walk($data, '');
echo implode("\n", $found) . (count($found) ? "\n" : '');
