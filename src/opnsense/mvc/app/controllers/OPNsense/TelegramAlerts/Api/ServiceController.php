<?php

namespace OPNsense\TelegramAlerts\Api;

use OPNsense\Base\ApiControllerBase;
use OPNsense\Core\Backend;
use OPNsense\Core\Config;
use OPNsense\TelegramAlerts\TelegramAlerts;

class ServiceController extends ApiControllerBase
{
    private const ALERT_SCRIPT = '/usr/local/bin/tg-alert.sh';
    private const CRON_COMMAND = 'telegramalerts daily';

    /** Monit tests owned by this plugin. */
    private const TESTS = [
        'TG_CPU' => ['cpu usage is greater than 90% for 5 cycles', 'SystemResource'],
        'TG_MEM' => ['memory usage is greater than 85%', 'SystemResource'],
        'TG_DISK' => ['space usage is greater than 80%', 'SpaceUsage'],
        'TG_STATUS' => ['status != 0 for 2 cycles', 'ProgramStatus'],
        'TG_STATUS5' => ['status != 0 for 5 cycles', 'ProgramStatus'],
    ];

    /**
     * Built-in Monit services: only our tests are attached/detached.
     * toggle => tests
     */
    private const BUILTIN = [
        '$HOST' => ['resources', ['TG_CPU', 'TG_MEM']],
        'RootFs' => ['resources', ['TG_DISK']],
        'gateway_alert' => ['gatewaydown', ['TG_STATUS']],
    ];

    /**
     * Custom Monit services owned by this plugin.
     * name => [toggle(s), path, tests, description]
     */
    private const CUSTOM = [
        'cpu_temp' => [['temperature'], '/usr/local/bin/tg-temp-check.sh', ['TG_STATUS'], 'Telegram: CPU temperature'],
        'smart_health' => [['smart'], '/usr/local/bin/tg-smart-check.sh', ['TG_STATUS'], 'Telegram: disk SMART health'],
        'fw_update' => [['updates'], '/usr/local/bin/tg-update-check.sh', ['TG_STATUS'], 'Telegram: firmware updates'],
        'net_watch' => [['netwatch'], '/usr/local/bin/tg-net-watch.sh', ['TG_STATUS'], 'Telegram: boot and outage notices'],
        'wan_quality' => [['wanquality'], '/usr/local/bin/tg-wan-quality.sh', ['TG_STATUS5'], 'Telegram: WAN latency and loss'],
        'tg_events' => [
            ['logins', 'configchange', 'newdevices', 'ids', 'wireguard', 'backup'],
            '/usr/local/bin/tg-events.sh', ['TG_STATUS'], 'Telegram: logins, config, devices, IDS, VPN, backup'
        ],
    ];

    /**
     * Render env file, then sync Monit services/tests and the cron job with the switches.
     */
    public function reconfigureAction()
    {
        if (!$this->request->isPost()) {
            return ['status' => 'failed', 'message' => 'POST required'];
        }
        $backend = new Backend();
        $backend->configdRun('template reload OPNsense/TelegramAlerts');
        $secure = trim($backend->configdRun('telegramalerts secure'));

        $warnings = [];
        $gen = (new TelegramAlerts())->general;
        $on = function ($field) use ($gen) {
            return (string)$gen->enabled === '1' && (string)$gen->$field === '1';
        };

        try {
            $warnings = array_merge($warnings, $this->syncMonit($on));
        } catch (\Throwable $e) {
            $warnings[] = 'Monit sync failed: ' . $e->getMessage();
        }
        try {
            $warnings = array_merge($warnings, $this->syncCron($on('daily'), (string)$gen->dailyhour));
        } catch (\Throwable $e) {
            $warnings[] = 'Cron sync failed: ' . $e->getMessage();
        }

        return [
            'status' => $secure === 'OK' && empty($warnings) ? 'ok' : 'failed',
            'message' => $secure === 'OK' ? 'Saved' : $secure,
            'warnings' => $warnings,
        ];
    }

    /**
     * Send a test message using the saved settings.
     */
    public function testAction()
    {
        if (!$this->request->isPost()) {
            return ['status' => 'failed', 'message' => 'POST required'];
        }
        $result = trim((new Backend())->configdRun('telegramalerts test'));
        return ['status' => $result === 'OK' ? 'ok' : 'failed', 'message' => $result];
    }

    /**
     * Send the daily summary now.
     */
    public function dailyAction()
    {
        if (!$this->request->isPost()) {
            return ['status' => 'failed', 'message' => 'POST required'];
        }
        (new Backend())->configdRun('telegramalerts daily');
        return ['status' => 'ok', 'message' => 'Daily summary sent (if alerts are enabled)'];
    }

    private function uuidsByName($arrayField)
    {
        $map = [];
        foreach ($arrayField->iterateItems() as $uuid => $node) {
            $map[(string)$node->name] = $uuid;
        }
        return $map;
    }

    private function syncMonit(callable $on)
    {
        $warnings = [];
        $mdl = new \OPNsense\Monit\Monit();

        // Tests: create missing ones (type set only on creation), then enforce condition/action/path.
        $tests = $this->uuidsByName($mdl->test);
        foreach (self::TESTS as $name => [$condition, $type]) {
            $fields = [
                'name' => $name,
                'condition' => $condition,
                'action' => 'exec',
                'path' => self::ALERT_SCRIPT,
            ];
            if (!isset($tests[$name])) {
                $node = $mdl->test->Add();
                $tests[$name] = $node->getAttribute('uuid');
                $fields['type'] = $type;
            }
            $mdl->getNodeByReference('test.' . $tests[$name])->setNodes($fields);
        }
        $ourTestUuids = array_values(array_intersect_key($tests, self::TESTS));

        $services = $this->uuidsByName($mdl->service);

        // Built-in services: attach or detach our tests, keep everything else.
        foreach (self::BUILTIN as $name => [$toggle, $want]) {
            if (!isset($services[$name])) {
                $warnings[] = "Monit service $name not found";
                continue;
            }
            $node = $mdl->getNodeByReference('service.' . $services[$name]);
            $current = array_filter(explode(',', (string)$node->tests));
            $current = array_values(array_diff($current, $ourTestUuids));
            if ($on($toggle)) {
                foreach ($want as $t) {
                    $current[] = $tests[$t];
                }
                $node->enabled = '1';
            }
            $node->tests = implode(',', array_unique($current));
        }

        // Custom services owned by the plugin.
        foreach (self::CUSTOM as $name => [$toggles, $path, $want, $descr]) {
            $enabled = false;
            foreach ($toggles as $t) {
                $enabled = $enabled || $on($t);
            }
            if (!isset($services[$name])) {
                $node = $mdl->service->Add();
                $services[$name] = $node->getAttribute('uuid');
            }
            $node = $mdl->getNodeByReference('service.' . $services[$name]);
            $node->setNodes([
                'enabled' => $enabled ? '1' : '0',
                'name' => $name,
                'type' => 'custom',
                'path' => $path,
                'tests' => implode(',', array_map(function ($t) use ($tests) {
                    return $tests[$t];
                }, $want)),
                'description' => $descr,
            ]);
        }

        $errors = $mdl->performValidation();
        if (count($errors)) {
            foreach ($errors as $msg) {
                $warnings[] = 'Monit: ' . $msg->getField() . ': ' . $msg->getMessage();
            }
            return $warnings;
        }
        $mdl->serializeToConfig();
        Config::getInstance()->save();

        // Same steps as Services > Monit > Apply. Monit itself refuses an invalid
        // file and keeps the previous configuration running.
        $backend = new Backend();
        $backend->configdRun('template reload OPNsense/Monit');
        $result = trim($backend->configdRun('monit restart'));
        if (stripos($result, 'error') !== false || stripos($result, 'fail') !== false) {
            $warnings[] = 'Monit restart: ' . $result . ' (see Services > Monit > Log File)';
        }
        return $warnings;
    }

    private function syncCron($enabled, $hour)
    {
        $mdl = new \OPNsense\Cron\Cron();
        $uuid = null;
        foreach ($mdl->jobs->job->iterateItems() as $id => $job) {
            if ((string)$job->command === self::CRON_COMMAND) {
                $uuid = $id;
                break;
            }
        }
        if ($uuid === null) {
            if (!$enabled) {
                return [];
            }
            $uuid = $mdl->jobs->job->Add()->getAttribute('uuid');
        }
        $job = $mdl->getNodeByReference('jobs.job.' . $uuid);
        $job->setNodes([
            'enabled' => $enabled ? '1' : '0',
            'minutes' => '3',
            'hours' => $hour,
            'days' => '*',
            'months' => '*',
            'weekdays' => '*',
            'who' => 'root',
            'command' => self::CRON_COMMAND,
            'description' => 'Telegram Alerts daily summary',
        ]);
        $errors = $mdl->performValidation();
        if (count($errors)) {
            $out = [];
            foreach ($errors as $msg) {
                $out[] = 'Cron: ' . $msg->getField() . ': ' . $msg->getMessage();
            }
            return $out;
        }
        $mdl->serializeToConfig();
        Config::getInstance()->save();
        $backend = new Backend();
        $backend->configdRun('template reload OPNsense/Cron');
        $backend->configdRun('cron restart');
        return [];
    }
}
