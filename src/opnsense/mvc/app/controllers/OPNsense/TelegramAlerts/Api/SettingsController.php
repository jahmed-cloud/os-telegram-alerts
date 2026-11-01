<?php

namespace OPNsense\TelegramAlerts\Api;

use OPNsense\Base\ApiMutableModelControllerBase;

class SettingsController extends ApiMutableModelControllerBase
{
    protected static $internalModelName = 'telegramalerts';
    protected static $internalModelClass = 'OPNsense\TelegramAlerts\TelegramAlerts';
}
