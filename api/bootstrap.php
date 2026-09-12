<?php
declare(strict_types=1);

const ROOT = dirname(__DIR__);

function env_load(): void
{
    $path = ROOT . DIRECTORY_SEPARATOR . '.env';
    if (!is_file($path)) {
        $path = ROOT . DIRECTORY_SEPARATOR . '.env.example';
    }
    foreach (file($path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [] as $line) {
        if ($line[0] === '#' || !str_contains($line, '=')) {
            continue;
        }
        [$k, $v] = explode('=', $line, 2);
        $k = trim($k);
        $v = trim($v);
        if (getenv($k) === false) {
            putenv("$k=$v");
            $_ENV[$k] = $v;
        }
    }
}

function envv(string $key, string $default = ''): string
{
    $v = getenv($key);
    return $v === false || $v === '' ? $default : $v;
}

function now_iso(): string
{
    return gmdate('c');
}

function json_input(): array
{
    $raw = file_get_contents('php://input') ?: '';
    $data = json_decode($raw, true);
    return is_array($data) ? $data : [];
}

function respond(int $code, array $payload): never
{
    http_response_code($code);
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store');
    echo json_encode($payload, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
    exit;
}

function db(): PDO
{
    static $pdo = null;
    if ($pdo) {
        return $pdo;
    }
    $dir = ROOT . DIRECTORY_SEPARATOR . 'data';
    if (!is_dir($dir)) {
        mkdir($dir, 0777, true);
    }
    $file = $dir . DIRECTORY_SEPARATOR . 'voltrescue.sqlite';
    $needsSchema = !is_file($file);
    $pdo = new PDO('sqlite:' . $file, null, null, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ]);
    $pdo->exec('PRAGMA foreign_keys = ON');
    $pdo->exec(file_get_contents(__DIR__ . DIRECTORY_SEPARATOR . 'schema.sql'));
    seed_if_empty($pdo);
    return $pdo;
}

function b64url(string $data): string
{
    return rtrim(strtr(base64_encode($data), '+/', '-_'), '=');
}

function b64url_decode(string $data): string
{
    $remainder = strlen($data) % 4;
    if ($remainder) {
        $data .= str_repeat('=', 4 - $remainder);
    }
    return base64_decode(strtr($data, '-_', '+/')) ?: '';
}

function jwt_issue(array $user): string
{
    $secret = envv('JWT_SECRET', 'dev-secret');
    $ttl = (int) envv('JWT_TTL_SECONDS', '28800');
    $header = b64url(json_encode(['typ' => 'JWT', 'alg' => 'HS256']));
    $payload = b64url(json_encode([
        'sub' => (int) $user['user_id'],
        'role' => $user['role'],
        'name' => $user['name'],
        'iat' => time(),
        'exp' => time() + $ttl,
    ]));
    $sig = b64url(hash_hmac('sha256', "$header.$payload", $secret, true));
    return "$header.$payload.$sig";
}

function jwt_verify(?string $token): ?array
{
    if (!$token) {
        return null;
    }
    $parts = explode('.', $token);
    if (count($parts) !== 3) {
        return null;
    }
    [$h, $p, $s] = $parts;
    $secret = envv('JWT_SECRET', 'dev-secret');
    $check = b64url(hash_hmac('sha256', "$h.$p", $secret, true));
    if (!hash_equals($check, $s)) {
        return null;
    }
    $payload = json_decode(b64url_decode($p), true);
    if (!is_array($payload) || ($payload['exp'] ?? 0) < time()) {
        return null;
    }
    return $payload;
}

function bearer_token(): ?string
{
    $hdr = $_SERVER['HTTP_AUTHORIZATION'] ?? '';
    if (preg_match('/Bearer\s+(\S+)/i', $hdr, $m)) {
        return $m[1];
    }
    return $_GET['token'] ?? null;
}

function current_user(): ?array
{
    $payload = jwt_verify(bearer_token());
    if (!$payload) {
        return null;
    }
    $st = db()->prepare('SELECT * FROM users WHERE user_id = ? AND active_flag = 1');
    $st->execute([(int) $payload['sub']]);
    $user = $st->fetch();
    return $user ?: null;
}

function require_user(array $roles = []): array
{
    $user = current_user();
    if (!$user) {
        respond(401, ['error' => 'Authentication required']);
    }
    if ($roles && !in_array($user['role'], $roles, true)) {
        respond(403, ['error' => 'Insufficient role permission', 'role' => $user['role']]);
    }
    return $user;
}

function rate_limit(string $bucket, int $max = 60, int $window = 60): void
{
    $ip = $_SERVER['REMOTE_ADDR'] ?? 'local';
    $key = $bucket . ':' . $ip;
    $now = time();
    $pdo = db();
    $st = $pdo->prepare('SELECT * FROM rate_limits WHERE key = ?');
    $st->execute([$key]);
    $row = $st->fetch();
    if (!$row || ($now - (int) $row['window_start']) >= $window) {
        $pdo->prepare('INSERT OR REPLACE INTO rate_limits(key, hits, window_start) VALUES (?,?,?)')
            ->execute([$key, 1, $now]);
        return;
    }
    if ((int) $row['hits'] >= $max) {
        respond(429, ['error' => 'Too many requests. Retry shortly.']);
    }
    $pdo->prepare('UPDATE rate_limits SET hits = hits + 1 WHERE key = ?')->execute([$key]);
}

function audit(string $action, ?int $actor, string $entity, string $entityId, array $detail = []): void
{
    db()->prepare('INSERT INTO audit_logs(action, actor, entity, entity_id, detail, timestamp) VALUES (?,?,?,?,?,?)')
        ->execute([$action, $actor, $entity, $entityId, json_encode($detail), now_iso()]);
}

function seed_if_empty(PDO $pdo): void
{
    $n = (int) $pdo->query('SELECT COUNT(*) FROM users')->fetchColumn();
    if ($n > 0) {
        return;
    }
    $hash = password_hash('VoltRescue!23', PASSWORD_DEFAULT);
    $now = now_iso();
    $people = [
        ['Amina Citizen', '255711111111', 'citizen@voltrescue.local', 'citizen'],
        ['Juma Collector', '255722222222', 'collector@voltrescue.local', 'collector'],
        ['Neema Collector', '255733333333', 'neema.collector@voltrescue.local', 'collector'],
        ['GreenCycle Recycler', '255744444444', 'recycler@voltrescue.local', 'recycler'],
        ['Menelick Admin', '255755555555', 'admin@voltrescue.local', 'admin'],
    ];
    $ins = $pdo->prepare('INSERT INTO users(name, phone, email, role, password_hash, created_at) VALUES (?,?,?,?,?,?)');
    foreach ($people as $p) {
        $ins->execute([$p[0], $p[1], $p[2], $p[3], $hash, $now]);
    }
    $juma = (int) $pdo->query("SELECT user_id FROM users WHERE email='collector@voltrescue.local'")->fetchColumn();
    $neema = (int) $pdo->query("SELECT user_id FROM users WHERE email='neema.collector@voltrescue.local'")->fetchColumn();
    $rec = (int) $pdo->query("SELECT user_id FROM users WHERE email='recycler@voltrescue.local'")->fetchColumn();
    $pdo->prepare('INSERT INTO collectors(user_id, name, phone, vehicle, area, active_flag) VALUES (?,?,?,?,?,1)')
        ->execute([$juma, 'Juma Collector', '255722222222', 'Bajaj TR-01', 'Kariakoo']);
    $pdo->prepare('INSERT INTO collectors(user_id, name, phone, vehicle, area, active_flag) VALUES (?,?,?,?,?,1)')
        ->execute([$neema, 'Neema Collector', '255733333333', 'Van TM-19', 'Kinondoni']);
    $pdo->prepare('INSERT INTO recyclers(user_id, company_name, location, contact_person, phone) VALUES (?,?,?,?,?)')
        ->execute([$rec, 'GreenCycle Dar', 'Vingunguti Industrial Area', 'Hassan Partner', '255744444444']);
}

env_load();
