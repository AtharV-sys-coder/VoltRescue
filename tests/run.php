<?php
declare(strict_types=1);

$base = getenv('VR_BASE') ?: 'http://127.0.0.1:8765/api';
$failed = 0;
$passed = 0;
$report = [];

function req(string $method, string $path, $body = null, ?string $token = null, bool $json = true): array
{
    global $base;
    $ch = curl_init($base . $path);
    $headers = ['Accept: application/json'];
    if ($token) {
        $headers[] = 'Authorization: Bearer ' . $token;
    }
    if ($json && $body !== null) {
        $headers[] = 'Content-Type: application/json';
        curl_setopt($ch, CURLOPT_POSTFIELDS, is_string($body) ? $body : json_encode($body));
    }
    curl_setopt_array($ch, [
        CURLOPT_CUSTOMREQUEST => $method,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_HTTPHEADER => $headers,
        CURLOPT_TIMEOUT => 20,
    ]);
    $raw = curl_exec($ch);
    $code = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    return ['code' => $code, 'json' => json_decode($raw ?: '', true), 'raw' => $raw];
}

function check(string $name, bool $ok, string $detail = ''): void
{
    global $failed, $passed, $report;
    if ($ok) {
        $passed++;
        $report[] = "PASS  $name";
    } else {
        $failed++;
        $report[] = "FAIL  $name  $detail";
    }
}

$health = req('GET', '/health');
check('health', $health['code'] === 200 && !empty($health['json']['ok']));

$bad = req('POST', '/auth/login', ['identifier' => 'x', 'password' => 'nope']);
check('login rejection', $bad['code'] === 401);

$admin = req('POST', '/auth/login', ['identifier' => 'admin@voltrescue.local', 'password' => 'VoltRescue!23']);
check('admin login', $admin['code'] === 200 && !empty($admin['json']['token']));
$at = $admin['json']['token'] ?? '';

$cit = req('POST', '/auth/login', ['identifier' => 'citizen@voltrescue.local', 'password' => 'VoltRescue!23']);
check('citizen login', $cit['code'] === 200);
$ct = $cit['json']['token'] ?? '';

$col = req('POST', '/auth/login', ['identifier' => 'collector@voltrescue.local', 'password' => 'VoltRescue!23']);
$colt = $col['json']['token'] ?? '';
$rec = req('POST', '/auth/login', ['identifier' => 'recycler@voltrescue.local', 'password' => 'VoltRescue!23']);
$rt = $rec['json']['token'] ?? '';

$forbid = req('GET', '/admin/dashboard', null, $ct);
check('citizen blocked from admin', $forbid['code'] === 403);

$create = req('POST', '/pickup/create', [
    'location' => 'Kariakoo test stand',
    'area' => 'Kariakoo',
    'battery_type' => 'Lead-acid',
    'quantity' => 3,
    'latitude' => -6.82,
    'longitude' => 39.28,
    'remarks' => 'workflow test',
], $ct);
check('create pickup', $create['code'] === 201, (string) ($create['json']['error'] ?? $create['code']));
$rid = (int) ($create['json']['request']['request_id'] ?? 0);
check('pending assignment status', ($create['json']['request']['status'] ?? '') === 'PENDING_ASSIGNMENT');

$users = req('GET', '/admin/users', null, $at);
$cid = (int) ($users['json']['collectors'][0]['collector_id'] ?? 0);
$reid = (int) ($users['json']['recyclers'][0]['recycler_id'] ?? 0);
$asg = req('POST', '/admin/assign', ['request_id' => $rid, 'collector_id' => $cid], $at);
check('assign collector', $asg['code'] === 200 && ($asg['json']['request']['status'] ?? '') === 'COLLECTOR_ASSIGNED');

$acc = req('POST', '/collector/accept', ['request_id' => $rid], $colt);
check('collector accept', $acc['code'] === 200);

$illegal = req('PUT', '/pickup/status', ['request_id' => $rid, 'status' => 'PROCESS_COMPLETED'], $colt);
check('illegal transition blocked', $illegal['code'] === 409);

foreach (['COLLECTOR_EN_ROUTE', 'PICKUP_COMPLETED', 'IN_COLLECTOR_CUSTODY'] as $st) {
    $r = req('PUT', '/pickup/status', ['request_id' => $rid, 'status' => $st], $colt);
    check("status $st", $r['code'] === 200 && ($r['json']['request']['status'] ?? '') === $st, (string) ($r['json']['error'] ?? ''));
}

$hand = req('POST', '/collector/handover', ['request_id' => $rid, 'recycler_id' => $reid], $colt);
check('handover', $hand['code'] === 200, (string) ($hand['json']['error'] ?? ''));

$recv = req('POST', '/recycler/confirm', ['request_id' => $rid, 'action' => 'receive'], $rt);
check('recycler receive', $recv['code'] === 200);
$val = req('POST', '/recycler/confirm', ['request_id' => $rid, 'action' => 'validate'], $rt);
check('recycler validate', $val['code'] === 200);
$done = req('POST', '/recycler/confirm', ['request_id' => $rid, 'action' => 'complete'], $rt);
check('process completed', $done['code'] === 200 && ($done['json']['request']['status'] ?? '') === 'PROCESS_COMPLETED');

$dash = req('GET', '/admin/dashboard', null, $at);
check('admin dashboard', $dash['code'] === 200 && isset($dash['json']['kpis']));
$logs = req('GET', '/audit/logs', null, $at);
check('audit logs', $logs['code'] === 200 && !empty($logs['json']['items']));
$notes = req('GET', '/notifications', null, $ct);
check('notifications persisted', $notes['code'] === 200);
$mp = req('GET', '/mpesa/sandbox/auth', null, $at);
check('mpesa sandbox', $mp['code'] === 200 && !empty($mp['json']['ok']));
$life = req('GET', '/meta/lifecycle');
check('lifecycle meta', $life['code'] === 200 && count($life['json']['success'] ?? []) === 12);

echo implode(PHP_EOL, $report) . PHP_EOL;
echo "Passed=$passed Failed=$failed" . PHP_EOL;
exit($failed ? 1 : 0);
