<?php

namespace OPNsense\TelegramAlerts\Api;

use OPNsense\Base\ApiControllerBase;
use OPNsense\Core\Backend;

class DashboardController extends ApiControllerBase
{
    private const CACHE = '/tmp/telegramalerts_dashboard.json';
    private const TTL = 20;

    /**
     * Data for the dashboard widgets; cached briefly so several widgets share one run.
     */
    public function summaryAction()
    {
        if (is_file(self::CACHE) && time() - filemtime(self::CACHE) < self::TTL) {
            $data = json_decode((string)file_get_contents(self::CACHE), true);
            if (is_array($data)) {
                return $data;
            }
        }
        $raw = trim((new Backend())->configdRun('telegramalerts dashboard'));
        $data = json_decode($raw, true);
        if (!is_array($data)) {
            return ['error' => 'collector returned no data'];
        }
        @file_put_contents(self::CACHE, json_encode($data));
        return $data;
    }
}
