<?php
declare(strict_types=1);

class MpesaSandbox
{
    public function authenticate(): array
    {
        $key = envv('MPESA_CONSUMER_KEY');
        $secret = envv('MPESA_CONSUMER_SECRET');
        if ($key === '' || $secret === '') {
            return [
                'ok' => true,
                'sandbox' => true,
                'token' => 'sandbox-token-' . substr(hash('sha256', 'voltrescue-mpesa'), 0, 16),
                'expires_in' => 3599,
                'note' => 'No live credentials. Sandbox connector only.',
            ];
        }
        $url = envv('MPESA_ENV', 'sandbox') === 'production'
            ? 'https://api.safaricom.co.ke/oauth/v1/generate?grant_type=client_credentials'
            : 'https://sandbox.safaricom.co.ke/oauth/v1/generate?grant_type=client_credentials';
        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_HTTPHEADER => ['Authorization: Basic ' . base64_encode("$key:$secret")],
            CURLOPT_TIMEOUT => 15,
        ]);
        $body = curl_exec($ch);
        $err = curl_error($ch);
        curl_close($ch);
        if ($body === false) {
            return ['ok' => false, 'error' => $err];
        }
        $json = json_decode($body, true) ?: [];
        return ['ok' => isset($json['access_token']), 'raw' => $json];
    }

    public function validateStk(array $input): array
    {
        $errors = [];
        if (empty($input['phone']) || !preg_match('/^255\d{9}$/', (string) $input['phone'])) {
            $errors[] = 'phone must be 255XXXXXXXXX';
        }
        $amount = (float) ($input['amount'] ?? 0);
        if ($amount <= 0) {
            $errors[] = 'amount must be > 0';
        }
        return $errors;
    }

    public function stkPush(array $input): array
    {
        $errors = $this->validateStk($input);
        if ($errors) {
            return ['ok' => false, 'errors' => $errors];
        }
        $auth = $this->authenticate();
        $checkout = 'ws_POC_' . bin2hex(random_bytes(6));
        db()->prepare('INSERT INTO mpesa_sandbox_tx(request_id, amount, phone, status, checkout_id, result, created_at) VALUES (?,?,?,?,?,?,?)')
            ->execute([
                $input['request_id'] ?? null,
                $input['amount'],
                $input['phone'],
                'SANDBOX_ACCEPTED',
                $checkout,
                json_encode(['auth' => $auth, 'live' => false]),
                now_iso(),
            ]);
        return [
            'ok' => true,
            'live' => false,
            'CheckoutRequestID' => $checkout,
            'CustomerMessage' => 'Sandbox STK recorded. No live debit.',
        ];
    }
}

const SUCCESS_FLOW = [
    'REQUEST_SUBMITTED',
    'PENDING_ASSIGNMENT',
    'COLLECTOR_ASSIGNED',
    'PICKUP_ACCEPTED',
    'COLLECTOR_EN_ROUTE',
    'PICKUP_COMPLETED',
    'IN_COLLECTOR_CUSTODY',
    'TRANSFER_SCHEDULED',
    'IN_TRANSIT_TO_RECYCLER',
    'RECEIVED_BY_RECYCLER',
    'RECYCLER_VALIDATED',
    'PROCESS_COMPLETED',
];

const FAILURE_STATES = ['CANCELLED', 'REJECTED', 'NO_SHOW', 'TRANSFER_FAILED', 'RECYCLER_REJECTED'];

const ALLOWED = [
    'REQUEST_SUBMITTED' => ['PENDING_ASSIGNMENT', 'CANCELLED', 'REJECTED'],
    'PENDING_ASSIGNMENT' => ['COLLECTOR_ASSIGNED', 'CANCELLED', 'REJECTED'],
    'COLLECTOR_ASSIGNED' => ['PICKUP_ACCEPTED', 'CANCELLED', 'REJECTED', 'NO_SHOW', 'PENDING_ASSIGNMENT'],
    'PICKUP_ACCEPTED' => ['COLLECTOR_EN_ROUTE', 'CANCELLED', 'NO_SHOW'],
    'COLLECTOR_EN_ROUTE' => ['PICKUP_COMPLETED', 'NO_SHOW', 'CANCELLED'],
    'PICKUP_COMPLETED' => ['IN_COLLECTOR_CUSTODY'],
    'IN_COLLECTOR_CUSTODY' => ['TRANSFER_SCHEDULED'],
    'TRANSFER_SCHEDULED' => ['IN_TRANSIT_TO_RECYCLER', 'TRANSFER_FAILED', 'CANCELLED'],
    'IN_TRANSIT_TO_RECYCLER' => ['RECEIVED_BY_RECYCLER', 'TRANSFER_FAILED'],
    'RECEIVED_BY_RECYCLER' => ['RECYCLER_VALIDATED', 'RECYCLER_REJECTED'],
    'RECYCLER_VALIDATED' => ['PROCESS_COMPLETED'],
    'RECYCLER_REJECTED' => ['TRANSFER_SCHEDULED', 'IN_COLLECTOR_CUSTODY'],
    'TRANSFER_FAILED' => ['TRANSFER_SCHEDULED', 'IN_COLLECTOR_CUSTODY'],
];

function pickup_row(int $id): ?array
{
    $st = db()->prepare('SELECT p.*, u.name AS citizen_name, u.phone AS citizen_phone,
        a.assignment_id, a.collector_id, a.accepted_at, c.name AS collector_name, c.phone AS collector_phone, c.vehicle,
        t.transfer_id, t.recycler_id, t.status AS transfer_status, r.company_name AS recycler_name
        FROM pickup_requests p
        JOIN users u ON u.user_id = p.user_id
        LEFT JOIN assignments a ON a.request_id = p.request_id
        LEFT JOIN collectors c ON c.collector_id = a.collector_id
        LEFT JOIN custody_transfers t ON t.transfer_id = (
            SELECT transfer_id FROM custody_transfers WHERE request_id = p.request_id ORDER BY transfer_id DESC LIMIT 1
        )
        LEFT JOIN recyclers r ON r.recycler_id = t.recycler_id
        WHERE p.request_id = ?');
    $st->execute([$id]);
    $row = $st->fetch();
    if (!$row) {
        return null;
    }
    $h = db()->prepare('SELECT h.*, u.name AS actor_name FROM status_history h LEFT JOIN users u ON u.user_id=h.updated_by WHERE request_id=? ORDER BY history_id');
    $h->execute([$id]);
    $row['timeline'] = $h->fetchAll();
    $u = db()->prepare('SELECT * FROM uploads WHERE request_id=? ORDER BY upload_id');
    $u->execute([$id]);
    $row['uploads'] = $u->fetchAll();
    $row['nav_link'] = null;
    if ($row['latitude'] && $row['longitude']) {
        $row['nav_link'] = 'https://www.openstreetmap.org/directions?to=' . $row['latitude'] . '%2C' . $row['longitude'];
        $row['google_nav'] = 'https://www.google.com/maps/dir/?api=1&destination=' . $row['latitude'] . ',' . $row['longitude'];
    }
    return $row;
}

function set_status(int $requestId, string $new, array $actor, string $note = '', bool $override = false): array
{
    $pdo = db();
    $st = $pdo->prepare('SELECT * FROM pickup_requests WHERE request_id=?');
    $st->execute([$requestId]);
    $row = $st->fetch();
    if (!$row) {
        respond(404, ['error' => 'Request not found']);
    }
    $old = $row['status'];
    if ($old === $new) {
        return pickup_row($requestId);
    }
    if (!$override) {
        $ok = ALLOWED[$old] ?? [];
        if (!in_array($new, $ok, true)) {
            respond(409, ['error' => "Illegal transition $old → $new", 'allowed' => $ok]);
        }
    }
    $pdo->prepare('UPDATE pickup_requests SET status=?, updated_at=? WHERE request_id=?')->execute([$new, now_iso(), $requestId]);
    $pdo->prepare('INSERT INTO status_history(request_id, old_status, new_status, updated_by, updated_time, note) VALUES (?,?,?,?,?,?)')
        ->execute([$requestId, $old, $new, (int) $actor['user_id'], now_iso(), $note]);
    audit('STATUS_CHANGE', (int) $actor['user_id'], 'pickup_requests', (string) $requestId, ['from' => $old, 'to' => $new, 'note' => $note, 'override' => $override]);

    $owner = $pdo->prepare('SELECT * FROM users WHERE user_id=?');
    $owner->execute([(int) $row['user_id']]);
    $citizen = $owner->fetch();
    $msg = "VoltRescue: request #$requestId is now $new.";
    if ($citizen) {
        notify_user((int) $citizen['user_id'], $citizen['phone'], $msg);
    }
    $as = $pdo->prepare('SELECT c.phone, c.user_id FROM assignments a JOIN collectors c ON c.collector_id=a.collector_id WHERE a.request_id=?');
    $as->execute([$requestId]);
    $col = $as->fetch();
    if ($col) {
        notify_user((int) $col['user_id'], $col['phone'], $msg);
    }
    return pickup_row($requestId) ?: $row;
}
