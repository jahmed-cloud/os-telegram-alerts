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
        $data = $this->cached();
        if ($data !== null) {
            return $data;
        }
        // The widgets refresh together; the lock makes them wait for one collector run.
        $lock = @fopen(self::CACHE . '.lock', 'c');
        if ($lock) {
            flock($lock, LOCK_EX);
            $data = $this->cached();
        }
        if ($data === null) {
            $raw = trim((new Backend())->configdRun('telegramalerts dashboard'));
            $data = json_decode($raw, true);
            if (is_array($data)) {
                $old = umask(077);
                @file_put_contents(self::CACHE, json_encode($data));
                umask($old);
            } else {
                $data = ['error' => 'collector returned no data'];
            }
        }
        if ($lock) {
            flock($lock, LOCK_UN);
            fclose($lock);
        }
        return $data;
    }

    private function cached()
    {
        clearstatcache(true, self::CACHE);
        if (is_file(self::CACHE) && time() - filemtime(self::CACHE) < self::TTL) {
            $data = json_decode((string)@file_get_contents(self::CACHE), true);
            if (is_array($data)) {
                return $data;
            }
        }
        return null;
    }
}
