<?php
declare(strict_types=1);

require __DIR__ . '/bootstrap.php';
require __DIR__ . '/NotificationService.php';
require __DIR__ . '/Domain.php';

header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, POST, PUT, PATCH, DELETE, OPTIONS');
if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    http_response_code(204);
    exit;
}

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
$uri = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';
$uri = preg_replace('#^/index\.php#', '', $uri);
if (str_starts_with($uri, '/api')) {
    $uri = substr($uri, 4) ?: '/';
}
$uri = '/' . trim($uri, '/');
if ($uri !== '/') {
    $uri = rtrim($uri, '/');
}

rate_limit('api', 120, 60);

function path_int(string $uri, string $pattern): ?int
{
    if (preg_match($pattern, $uri, $m)) {
        return (int) $m[1];
    }
    return null;
}

try {
    if ($method === 'GET' && $uri === '/health') {
        respond(200, ['ok' => true, 'service' => 'VoltRescue POC', 'time' => now_iso()]);
    }

    if ($method === 'POST' && $uri === '/auth/register') {
        rate_limit('register', 10, 300);
        $b = json_input();
        foreach (['name', 'phone', 'email', 'password'] as $f) {
            if (empty($b[$f])) {
                respond(422, ['error' => "Missing $f"]);
            }
        }
        if (!preg_match('/^255\d{9}$/', $b['phone'])) {
            respond(422, ['error' => 'Phone must be 255XXXXXXXXX']);
        }
        if (!filter_var($b['email'], FILTER_VALIDATE_EMAIL)) {
            respond(422, ['error' => 'Invalid email']);
        }
        if (strlen($b['password']) < 8) {
            respond(422, ['error' => 'Password must be at least 8 characters']);
        }
        $role = $b['role'] ?? 'citizen';
        if (!in_array($role, ['citizen', 'collector', 'recycler'], true)) {
            $role = 'citizen';
        }
        try {
            db()->prepare('INSERT INTO users(name, phone, email, role, password_hash, created_at) VALUES (?,?,?,?,?,?)')
                ->execute([$b['name'], $b['phone'], strtolower($b['email']), $role, password_hash($b['password'], PASSWORD_DEFAULT), now_iso()]);
        } catch (PDOException $e) {
            respond(409, ['error' => 'Phone or email already registered']);
        }
        $id = (int) db()->lastInsertId();
        if ($role === 'collector') {
            db()->prepare('INSERT INTO collectors(user_id, name, phone, vehicle, area, active_flag) VALUES (?,?,?,?,?,1)')
                ->execute([$id, $b['name'], $b['phone'], $b['vehicle'] ?? '', $b['area'] ?? '']);
        }
        if ($role === 'recycler') {
            db()->prepare('INSERT INTO recyclers(user_id, company_name, location, contact_person, phone) VALUES (?,?,?,?,?)')
                ->execute([$id, $b['company_name'] ?? $b['name'], $b['location'] ?? '', $b['name'], $b['phone']]);
        }
        $user = db()->query("SELECT user_id, name, phone, email, role, created_at FROM users WHERE user_id=$id")->fetch();
        audit('REGISTER', $id, 'users', (string) $id, ['role' => $role]);
        notify_user($id, $b['phone'], 'VoltRescue: account created. You can submit battery pickups.');
        respond(201, ['user' => $user, 'token' => jwt_issue($user + ['role' => $role, 'name' => $b['name'], 'user_id' => $id])]);
    }

    if ($method === 'POST' && $uri === '/auth/login') {
        rate_limit('login', 20, 300);
        $b = json_input();
        $id = trim((string) ($b['email'] ?? $b['phone'] ?? $b['identifier'] ?? ''));
        $pass = (string) ($b['password'] ?? '');
        if ($id === '' || $pass === '') {
            respond(422, ['error' => 'Identifier and password required']);
        }
        $st = db()->prepare('SELECT * FROM users WHERE email = ? OR phone = ?');
        $st->execute([strtolower($id), $id]);
        $user = $st->fetch();
        if (!$user || !$user['active_flag'] || !password_verify($pass, $user['password_hash'])) {
            audit('LOGIN_FAILED', null, 'users', $id, []);
            respond(401, ['error' => 'Invalid credentials']);
        }
        audit('LOGIN', (int) $user['user_id'], 'users', (string) $user['user_id'], []);
        unset($user['password_hash'], $user['reset_token']);
        respond(200, ['user' => $user, 'token' => jwt_issue($user)]);
    }

    if ($method === 'GET' && $uri === '/auth/me') {
        $u = require_user();
        unset($u['password_hash'], $u['reset_token']);
        respond(200, ['user' => $u]);
    }

    if ($method === 'PUT' && $uri === '/auth/me') {
        $u = require_user();
        $b = json_input();
        $name = $b['name'] ?? $u['name'];
        $email = strtolower($b['email'] ?? $u['email']);
        db()->prepare('UPDATE users SET name=?, email=? WHERE user_id=?')->execute([$name, $email, $u['user_id']]);
        audit('PROFILE_UPDATE', (int) $u['user_id'], 'users', (string) $u['user_id'], []);
        respond(200, ['ok' => true]);
    }

    if ($method === 'POST' && $uri === '/auth/password-reset') {
        $b = json_input();
        $phone = $b['phone'] ?? '';
        $st = db()->prepare('SELECT * FROM users WHERE phone=?');
        $st->execute([$phone]);
        $user = $st->fetch();
        if ($user) {
            $token = bin2hex(random_bytes(16));
            db()->prepare('UPDATE users SET reset_token=?, reset_expires_at=? WHERE user_id=?')
                ->execute([$token, gmdate('c', time() + 1800), $user['user_id']]);
            notify_user((int) $user['user_id'], $user['phone'], "VoltRescue password reset code: $token");
        }
        respond(200, ['ok' => true, 'message' => 'If the phone exists, a reset code was sent.']);
    }

    if ($method === 'POST' && $uri === '/auth/password-reset/confirm') {
        $b = json_input();
        $st = db()->prepare('SELECT * FROM users WHERE reset_token=? AND reset_expires_at > ?');
        $st->execute([$b['token'] ?? '', now_iso()]);
        $user = $st->fetch();
        if (!$user || empty($b['password']) || strlen($b['password']) < 8) {
            respond(422, ['error' => 'Invalid token or password']);
        }
        db()->prepare('UPDATE users SET password_hash=?, reset_token=NULL, reset_expires_at=NULL WHERE user_id=?')
            ->execute([password_hash($b['password'], PASSWORD_DEFAULT), $user['user_id']]);
        audit('PASSWORD_RESET', (int) $user['user_id'], 'users', (string) $user['user_id'], []);
        respond(200, ['ok' => true]);
    }

    if ($method === 'POST' && $uri === '/pickup/create') {
        $u = require_user(['citizen', 'admin']);
        $b = json_input();
        $loc = trim((string) ($b['location'] ?? ''));
        $qty = (int) ($b['quantity'] ?? 0);
        $type = trim((string) ($b['battery_type'] ?? ''));
        if ($loc === '' || $qty < 1 || $type === '') {
            respond(422, ['error' => 'location, battery_type and quantity (>=1) are required']);
        }
        $lat = isset($b['latitude']) ? (float) $b['latitude'] : null;
        $lng = isset($b['longitude']) ? (float) $b['longitude'] : null;
        db()->prepare('INSERT INTO pickup_requests(user_id, location, area, latitude, longitude, battery_type, quantity, remarks, status, created_at, updated_at)
            VALUES (?,?,?,?,?,?,?,?,?,?,?)')
            ->execute([
                $u['role'] === 'admin' && !empty($b['user_id']) ? (int) $b['user_id'] : $u['user_id'],
                $loc,
                $b['area'] ?? '',
                $lat,
                $lng,
                $type,
                $qty,
                $b['remarks'] ?? '',
                'REQUEST_SUBMITTED',
                now_iso(),
                now_iso(),
            ]);
        $id = (int) db()->lastInsertId();
        db()->prepare('INSERT INTO status_history(request_id, old_status, new_status, updated_by, updated_time, note) VALUES (?,?,?,?,?,?)')
            ->execute([$id, null, 'REQUEST_SUBMITTED', $u['user_id'], now_iso(), 'created']);
        audit('PICKUP_CREATE', (int) $u['user_id'], 'pickup_requests', (string) $id, $b);
        $row = set_status($id, 'PENDING_ASSIGNMENT', $u, 'Awaiting collector assignment');
        notify_user((int) $u['user_id'], $u['phone'], "VoltRescue: pickup #$id submitted ($qty x $type).");
        $admins = db()->query("SELECT user_id, phone FROM users WHERE role='admin' AND active_flag=1")->fetchAll();
        foreach ($admins as $a) {
            notify_user((int) $a['user_id'], $a['phone'], "VoltRescue: new pickup #$id needs assignment.");
        }
        respond(201, ['request' => $row]);
    }

    if ($method === 'GET' && $uri === '/pickup') {
        $u = require_user();
        $sql = 'SELECT p.*, u.name AS citizen_name FROM pickup_requests p JOIN users u ON u.user_id=p.user_id';
        $args = [];
        if ($u['role'] === 'citizen') {
            $sql .= ' WHERE p.user_id=?';
            $args[] = $u['user_id'];
        } elseif ($u['role'] === 'collector') {
            $sql .= ' JOIN assignments a ON a.request_id=p.request_id JOIN collectors c ON c.collector_id=a.collector_id WHERE c.user_id=?';
            $args[] = $u['user_id'];
        } elseif ($u['role'] === 'recycler') {
            $sql .= ' JOIN custody_transfers t ON t.request_id=p.request_id JOIN recyclers r ON r.recycler_id=t.recycler_id WHERE r.user_id=?';
            $args[] = $u['user_id'];
        }
        $sql .= ' ORDER BY p.request_id DESC';
        $st = db()->prepare($sql);
        $st->execute($args);
        respond(200, ['items' => $st->fetchAll()]);
    }

    $id = path_int($uri, '#^/pickup/(\d+)$#');
    if ($method === 'GET' && $id) {
        $u = require_user();
        $row = pickup_row($id);
        if (!$row) {
            respond(404, ['error' => 'Not found']);
        }
        if ($u['role'] === 'citizen' && (int) $row['user_id'] !== (int) $u['user_id']) {
            respond(403, ['error' => 'Forbidden']);
        }
        respond(200, ['request' => $row]);
    }

    if ($method === 'PUT' && $uri === '/pickup/status') {
        $u = require_user();
        $b = json_input();
        $rid = (int) ($b['request_id'] ?? 0);
        $status = (string) ($b['status'] ?? '');
        if (!$rid || $status === '') {
            respond(422, ['error' => 'request_id and status required']);
        }
        $override = $u['role'] === 'admin' && !empty($b['override']);
        $row = set_status($rid, $status, $u, (string) ($b['note'] ?? ''), $override);
        respond(200, ['request' => $row]);
    }

    if ($method === 'GET' && $uri === '/recyclers') {
        require_user(['collector', 'admin', 'recycler']);
        respond(200, ['items' => db()->query('SELECT recycler_id, company_name, location, contact_person, phone FROM recyclers')->fetchAll()]);
    }

    if ($method === 'GET' && $uri === '/collector/tasks') {
        $u = require_user(['collector', 'admin']);
        $sql = 'SELECT p.*, a.assignment_id, a.accepted_at, c.collector_id, c.name AS collector_name
                FROM pickup_requests p
                JOIN assignments a ON a.request_id=p.request_id
                JOIN collectors c ON c.collector_id=a.collector_id';
        $args = [];
        if ($u['role'] === 'collector') {
            $sql .= ' WHERE c.user_id=?';
            $args[] = $u['user_id'];
        }
        $sql .= ' ORDER BY p.updated_at DESC';
        $st = db()->prepare($sql);
        $st->execute($args);
        respond(200, ['items' => $st->fetchAll()]);
    }

    if ($method === 'POST' && $uri === '/collector/accept') {
        $u = require_user(['collector', 'admin']);
        $b = json_input();
        $rid = (int) ($b['request_id'] ?? 0);
        if (!$rid) {
            respond(422, ['error' => 'request_id required']);
        }
        if ($u['role'] === 'collector') {
            $col = db()->prepare('SELECT * FROM collectors WHERE user_id=?');
            $col->execute([$u['user_id']]);
            $collector = $col->fetch();
            if (!$collector) {
                respond(403, ['error' => 'Collector profile missing']);
            }
            $as = db()->prepare('SELECT * FROM assignments WHERE request_id=? AND collector_id=?');
            $as->execute([$rid, $collector['collector_id']]);
            if (!$as->fetch()) {
                respond(403, ['error' => 'Not assigned to this collector']);
            }
        } else {
            $as = db()->prepare('SELECT * FROM assignments WHERE request_id=?');
            $as->execute([$rid]);
            if (!$as->fetch()) {
                respond(403, ['error' => 'Request is not assigned']);
            }
        }
        db()->prepare('UPDATE assignments SET accepted_at=? WHERE request_id=?')->execute([now_iso(), $rid]);
        $row = set_status($rid, 'PICKUP_ACCEPTED', $u, 'Collector accepted assignment');
        respond(200, ['request' => $row]);
    }

    if ($method === 'POST' && $uri === '/collector/handover') {
        $u = require_user(['collector', 'admin']);
        $b = json_input();
        $rid = (int) ($b['request_id'] ?? 0);
        $recyclerId = (int) ($b['recycler_id'] ?? 0);
        if (!$rid || !$recyclerId) {
            respond(422, ['error' => 'request_id and recycler_id required']);
        }
        $current = pickup_row($rid);
        if ($u['role'] === 'collector') {
            $col = db()->prepare('SELECT * FROM collectors WHERE user_id=?');
            $col->execute([$u['user_id']]);
            $collector = $col->fetch();
            if (!$current || !$collector || (int) $current['collector_id'] !== (int) $collector['collector_id']) {
                respond(403, ['error' => 'Collector does not hold this request']);
            }
        } else {
            if (!$current || empty($current['collector_id'])) {
                respond(403, ['error' => 'Request is not assigned']);
            }
            $col = db()->prepare('SELECT * FROM collectors WHERE collector_id=?');
            $col->execute([(int) $current['collector_id']]);
            $collector = $col->fetch();
            if (!$collector) {
                respond(403, ['error' => 'Collector profile missing']);
            }
        }
        if ($current['status'] === 'IN_COLLECTOR_CUSTODY') {
            set_status($rid, 'TRANSFER_SCHEDULED', $u, 'Handover scheduled');
        }
        db()->prepare('INSERT INTO custody_transfers(request_id, collector_id, recycler_id, status, transfer_date, notes) VALUES (?,?,?,?,?,?)')
            ->execute([$rid, $collector['collector_id'], $recyclerId, 'IN_TRANSIT_TO_RECYCLER', now_iso(), $b['notes'] ?? '']);
        $row = pickup_row($rid);
        if ($row['status'] === 'TRANSFER_SCHEDULED') {
            $row = set_status($rid, 'IN_TRANSIT_TO_RECYCLER', $u, 'In transit to recycler');
        }
        $rec = db()->prepare('SELECT * FROM recyclers r JOIN users u ON u.user_id=r.user_id WHERE r.recycler_id=?');
        $rec->execute([$recyclerId]);
        $r = $rec->fetch();
        if ($r) {
            notify_user((int) $r['user_id'], $r['phone'], "VoltRescue: incoming transfer for request #$rid.");
        }
        respond(200, ['request' => $row]);
    }

    if ($method === 'POST' && $uri === '/recycler/confirm') {
        $u = require_user(['recycler', 'admin']);
        $b = json_input();
        $rid = (int) ($b['request_id'] ?? 0);
        $action = $b['action'] ?? 'receive';
        $row = pickup_row($rid);
        if (!$row) {
            respond(404, ['error' => 'Not found']);
        }
        if ($action === 'receive') {
            $row = set_status($rid, 'RECEIVED_BY_RECYCLER', $u, $b['note'] ?? 'Receipt confirmed');
        } elseif ($action === 'validate') {
            $row = set_status($rid, 'RECYCLER_VALIDATED', $u, $b['note'] ?? 'Materials validated');
        } elseif ($action === 'complete') {
            if ($row['status'] === 'RECEIVED_BY_RECYCLER') {
                set_status($rid, 'RECYCLER_VALIDATED', $u, 'Validated on complete');
            }
            $row = set_status($rid, 'PROCESS_COMPLETED', $u, $b['note'] ?? 'Intake complete');
        } elseif ($action === 'reject') {
            $row = set_status($rid, 'RECYCLER_REJECTED', $u, $b['note'] ?? 'Rejected at recycler');
        }
        db()->prepare('UPDATE custody_transfers SET status=? WHERE request_id=?')->execute([$row['status'], $rid]);
        respond(200, ['request' => $row]);
    }

    if ($method === 'GET' && $uri === '/admin/dashboard') {
        $u = require_user(['admin']);
        $pdo = db();
        $today = gmdate('Y-m-d');
        $count = function (string $where) use ($pdo): int {
            return (int) $pdo->query("SELECT COUNT(*) FROM pickup_requests WHERE $where")->fetchColumn();
        };
        $q = $_GET['q'] ?? '';
        $status = $_GET['status'] ?? '';
        $sort = in_array($_GET['sort'] ?? '', ['request_id', 'created_at', 'status', 'quantity'], true) ? $_GET['sort'] : 'request_id';
        $dir = strtolower($_GET['dir'] ?? 'desc') === 'asc' ? 'ASC' : 'DESC';
        $page = max(1, (int) ($_GET['page'] ?? 1));
        $size = min(50, max(5, (int) ($_GET['size'] ?? 10)));
        $where = '1=1';
        $args = [];
        if ($status !== '') {
            $where .= ' AND p.status=?';
            $args[] = $status;
        }
        if ($q !== '') {
            $where .= ' AND (p.location LIKE ? OR u.name LIKE ? OR p.battery_type LIKE ?)';
            $args[] = "%$q%";
            $args[] = "%$q%";
            $args[] = "%$q%";
        }
        $total = db()->prepare("SELECT COUNT(*) FROM pickup_requests p JOIN users u ON u.user_id=p.user_id WHERE $where");
        $total->execute($args);
        $off = ($page - 1) * $size;
        $st = db()->prepare("SELECT p.*, u.name AS citizen_name FROM pickup_requests p JOIN users u ON u.user_id=p.user_id WHERE $where ORDER BY p.$sort $dir LIMIT $size OFFSET $off");
        $st->execute($args);
        $workload = db()->query('SELECT c.name, COUNT(*) AS jobs FROM assignments a JOIN collectors c ON c.collector_id=a.collector_id JOIN pickup_requests p ON p.request_id=a.request_id WHERE p.status NOT IN ("PROCESS_COMPLETED","CANCELLED","REJECTED") GROUP BY c.collector_id')->fetchAll();
        respond(200, [
            'kpis' => [
                'today' => $count("substr(created_at,1,10)='$today'"),
                'pending_assignment' => $count("status='PENDING_ASSIGNMENT'"),
                'assigned' => $count("status IN ('COLLECTOR_ASSIGNED','PICKUP_ACCEPTED','COLLECTOR_EN_ROUTE')"),
                'recycler_pending' => $count("status IN ('IN_TRANSIT_TO_RECYCLER','RECEIVED_BY_RECYCLER')"),
                'completed' => $count("status='PROCESS_COMPLETED'"),
                'failed' => $count("status IN ('CANCELLED','REJECTED','NO_SHOW','TRANSFER_FAILED','RECYCLER_REJECTED')"),
            ],
            'workload' => $workload,
            'items' => $st->fetchAll(),
            'page' => $page,
            'size' => $size,
            'total' => (int) $total->fetchColumn(),
        ]);
    }

    if ($method === 'GET' && $uri === '/admin/export') {
        require_user(['admin']);
        header('Content-Type: text/csv');
        header('Content-Disposition: attachment; filename="voltrescue-requests.csv"');
        $out = fopen('php://output', 'w');
        fputcsv($out, ['request_id', 'citizen', 'location', 'battery_type', 'quantity', 'status', 'created_at']);
        $rows = db()->query('SELECT p.request_id, u.name, p.location, p.battery_type, p.quantity, p.status, p.created_at FROM pickup_requests p JOIN users u ON u.user_id=p.user_id')->fetchAll();
        foreach ($rows as $r) {
            fputcsv($out, $r);
        }
        fclose($out);
        exit;
    }

    if ($method === 'POST' && $uri === '/admin/assign') {
        $u = require_user(['admin']);
        $b = json_input();
        $rid = (int) ($b['request_id'] ?? 0);
        $cid = (int) ($b['collector_id'] ?? 0);
        $row = pickup_row($rid);
        if (!$row) {
            respond(404, ['error' => 'Request not found']);
        }
        $exists = db()->prepare('SELECT assignment_id FROM assignments WHERE request_id=?');
        $exists->execute([$rid]);
        if ($exists->fetch()) {
            db()->prepare('UPDATE assignments SET collector_id=?, assigned_at=?, assigned_by=?, accepted_at=NULL WHERE request_id=?')
                ->execute([$cid, now_iso(), $u['user_id'], $rid]);
        } else {
            db()->prepare('INSERT INTO assignments(request_id, collector_id, assigned_at, assigned_by) VALUES (?,?,?,?)')
                ->execute([$rid, $cid, now_iso(), $u['user_id']]);
        }
        $next = in_array($row['status'], ['REQUEST_SUBMITTED', 'PENDING_ASSIGNMENT', 'COLLECTOR_ASSIGNED'], true)
            ? 'COLLECTOR_ASSIGNED' : $row['status'];
        if ($row['status'] !== 'COLLECTOR_ASSIGNED') {
            $row = set_status($rid, 'COLLECTOR_ASSIGNED', $u, 'Admin assigned collector', $row['status'] !== 'PENDING_ASSIGNMENT' && $row['status'] !== 'REQUEST_SUBMITTED');
        } else {
            $row = pickup_row($rid);
        }
        $c = db()->prepare('SELECT * FROM collectors WHERE collector_id=?');
        $c->execute([$cid]);
        $col = $c->fetch();
        if ($col) {
            notify_user((int) $col['user_id'], $col['phone'], "VoltRescue: you were assigned pickup #$rid at {$row['location']}.");
        }
        respond(200, ['request' => $row]);
    }

    if ($method === 'GET' && $uri === '/admin/users') {
        require_user(['admin']);
        $users = db()->query('SELECT user_id, name, phone, email, role, active_flag, created_at FROM users ORDER BY user_id')->fetchAll();
        $collectors = db()->query('SELECT * FROM collectors')->fetchAll();
        $recyclers = db()->query('SELECT * FROM recyclers')->fetchAll();
        respond(200, ['users' => $users, 'collectors' => $collectors, 'recyclers' => $recyclers]);
    }

    if ($method === 'POST' && $uri === '/admin/users') {
        $u = require_user(['admin']);
        $b = json_input();
        $role = $b['role'] ?? 'citizen';
        if (!in_array($role, ['citizen', 'collector', 'recycler', 'admin'], true)) {
            respond(422, ['error' => 'Invalid role']);
        }
        db()->prepare('INSERT INTO users(name, phone, email, role, password_hash, created_at) VALUES (?,?,?,?,?,?)')
            ->execute([
                $b['name'], $b['phone'], strtolower($b['email']), $role,
                password_hash($b['password'] ?? 'VoltRescue!23', PASSWORD_DEFAULT), now_iso(),
            ]);
        $id = (int) db()->lastInsertId();
        if ($role === 'collector') {
            db()->prepare('INSERT INTO collectors(user_id, name, phone, vehicle, area, active_flag) VALUES (?,?,?,?,?,1)')
                ->execute([$id, $b['name'], $b['phone'], $b['vehicle'] ?? '', $b['area'] ?? '']);
        }
        if ($role === 'recycler') {
            db()->prepare('INSERT INTO recyclers(user_id, company_name, location, contact_person, phone) VALUES (?,?,?,?,?)')
                ->execute([$id, $b['company_name'] ?? $b['name'], $b['location'] ?? '', $b['contact_person'] ?? $b['name'], $b['phone']]);
        }
        audit('USER_CREATE', (int) $u['user_id'], 'users', (string) $id, ['role' => $role]);
        respond(201, ['user_id' => $id]);
    }

    if ($method === 'GET' && $uri === '/audit/logs') {
        require_user(['admin']);
        $page = max(1, (int) ($_GET['page'] ?? 1));
        $size = 25;
        $off = ($page - 1) * $size;
        $rows = db()->query("SELECT a.*, u.name AS actor_name FROM audit_logs a LEFT JOIN users u ON u.user_id=a.actor ORDER BY log_id DESC LIMIT $size OFFSET $off")->fetchAll();
        respond(200, ['items' => $rows, 'page' => $page]);
    }

    if ($method === 'GET' && $uri === '/notifications') {
        $u = require_user();
        $st = db()->prepare('SELECT * FROM notifications WHERE user_id=? OR recipient=? ORDER BY notification_id DESC LIMIT 50');
        $st->execute([$u['user_id'], $u['phone']]);
        respond(200, ['items' => $st->fetchAll()]);
    }

    if ($method === 'POST' && $uri === '/uploads') {
        $u = require_user();
        $rid = (int) ($_POST['request_id'] ?? 0);
        $kind = $_POST['kind'] ?? 'pickup';
        if (!$rid || empty($_FILES['file'])) {
            respond(422, ['error' => 'request_id and file required']);
        }
        $f = $_FILES['file'];
        if ($f['error'] !== UPLOAD_ERR_OK) {
            respond(400, ['error' => 'Upload failed']);
        }
        $allowed = ['image/jpeg' => 'jpg', 'image/png' => 'png', 'image/webp' => 'webp'];
        $finfo = finfo_open(FILEINFO_MIME_TYPE);
        $mime = finfo_file($finfo, $f['tmp_name']);
        finfo_close($finfo);
        if (!isset($allowed[$mime])) {
            respond(422, ['error' => 'Only JPEG, PNG, WebP allowed']);
        }
        if ($f['size'] > 5 * 1024 * 1024) {
            respond(422, ['error' => 'Max 5MB']);
        }
        $dir = ROOT . '/uploads/' . $rid;
        if (!is_dir($dir)) {
            mkdir($dir, 0777, true);
        }
        $name = $kind . '_' . time() . '_' . bin2hex(random_bytes(3)) . '.' . $allowed[$mime];
        $dest = $dir . '/' . $name;
        if (!move_uploaded_file($f['tmp_name'], $dest)) {
            respond(500, ['error' => 'Could not store file']);
        }
        $rel = 'uploads/' . $rid . '/' . $name;
        db()->prepare('INSERT INTO uploads(request_id, kind, file_path, mime_type, uploader, created_at) VALUES (?,?,?,?,?,?)')
            ->execute([$rid, $kind, $rel, $mime, $u['user_id'], now_iso()]);
        audit('UPLOAD', (int) $u['user_id'], 'uploads', (string) $rid, ['kind' => $kind]);
        respond(201, ['file_path' => $rel, 'kind' => $kind, 'created_at' => now_iso()]);
    }

    if ($method === 'GET' && $uri === '/mpesa/sandbox/auth') {
        require_user(['admin']);
        respond(200, (new MpesaSandbox())->authenticate());
    }

    if ($method === 'POST' && $uri === '/mpesa/sandbox/stk') {
        $u = require_user(['admin', 'citizen']);
        $b = json_input();
        $res = (new MpesaSandbox())->stkPush($b);
        audit('MPESA_SANDBOX', (int) $u['user_id'], 'mpesa_sandbox_tx', $b['phone'] ?? '', $res);
        respond(!empty($res['ok']) ? 200 : 422, $res);
    }

    if ($method === 'POST' && $uri === '/mpesa/callback') {
        $b = json_input();
        audit('MPESA_CALLBACK', null, 'mpesa_sandbox_tx', '', $b);
        respond(200, ['ResultCode' => 0]);
    }

    if ($method === 'GET' && $uri === '/meta/lifecycle') {
        respond(200, ['success' => SUCCESS_FLOW, 'failures' => FAILURE_STATES, 'allowed' => ALLOWED]);
    }

    respond(404, ['error' => 'Unknown API route', 'path' => $uri, 'method' => $method]);
} catch (Throwable $e) {
    audit('ERROR', null, 'system', '', ['message' => $e->getMessage()]);
    respond(500, ['error' => 'Server error', 'detail' => envv('APP_ENV') === 'poc' ? $e->getMessage() : null]);
}
