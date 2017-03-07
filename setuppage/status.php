<?php
/**
 * Simple php file which will process the output of the boot.sh script
 * and output it as json, so we can process it in our setup page
 *
 * When called with the POST method and a 'restart' parameter, notify
 * the boot script to restart supervisord.
 */

$status = [
    'percentage' => 1,
    'message' => 'Starting AbuseIO setup',
    'login' => 'admin@isp.local',
    'password' => '',
    'finished' => false,
    'configured' => false
];

$restartFile  = __DIR__ . "/" . "restart.txt";
$progressFile = __DIR__ . "/" . "progress.txt";
$passwordFile = __DIR__ . "/" . "password.txt";
$configuredFile = "/config/.configured";

if ($_SERVER['REQUEST_METHOD'] == 'GET') {
    // called by GET, return the progress as JSON

    // if this container is already configured
    $status['configured'] = file_exists($configuredFile);

    // files are written by 'boot.sh' on startup
    $progress = @file_get_contents($progressFile);
    $password = @file_get_contents($passwordFile);

    // process the password
    $status['password'] = rtrim($password);

    // process the progress
    if (preg_match("/^(\d+)\s+(.+)$/", $progress, $matches) == 1) {
        $status['percentage'] = $matches[1];
        $status['message'] = $matches[2];
    }

    // only finished when the status message contains 'done' and
    // a password is set or the container is configured
    if (stripos($status['message'], "done") !== false &&
        (!empty($status['password']) || $status['configured']))
    {
        $status['finished'] = true;
    }

    // return JSON
    print(json_encode($status));

} elseif ($_SERVER['REQUEST_METHOD'] === 'POST') {
    // called by POST

    // touch the restart file, so the boot script will know that it can restart supervisor
    touch($restartFile);

    print(json_encode(['restart' => true]));

} else {
    // Request method is not implemented

    print(json_encode(['error' => 'Request method not implemented']));
}