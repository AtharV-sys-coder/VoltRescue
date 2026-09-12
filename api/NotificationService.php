<?php
declare(strict_types=1);

interface NotificationProvider
{
    public function channel(): string;
    public function send(string $recipient, string $message, array $meta = []): array;
}

class SmsAdapter implements NotificationProvider
{
    public function channel(): string
    {
        return 'sms';
    }

    public function send(string $recipient, string $message, array $meta = []): array
    {
        $key = envv('AFRICAS_TALKING_API_KEY');
        $user = envv('AFRICAS_TALKING_USERNAME', 'sandbox');
        if ($key === '') {
            return [
                'ok' => true,
                'sandbox' => true,
                'provider' => 'africas_talking',
                'status' => 'queued_sandbox',
                'id' => 'sms_sim_' . bin2hex(random_bytes(4)),
            ];
        }
        $payload = http_build_query([
            'username' => $user,
            'to' => $recipient,
            'message' => $message,
            'from' => envv('AFRICAS_TALKING_SENDER_ID', 'VoltRescue'),
        ]);
        $ch = curl_init('https://api.sandbox.africastalking.com/version1/messaging');
        curl_setopt_array($ch, [
            CURLOPT_POST => true,
            CURLOPT_POSTFIELDS => $payload,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_HTTPHEADER => [
                'apiKey: ' . $key,
                'Content-Type: application/x-www-form-urlencoded',
                'Accept: application/json',
            ],
            CURLOPT_TIMEOUT => 15,
        ]);
        $body = curl_exec($ch);
        $err = curl_error($ch);
        $code = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        if ($body === false) {
            return ['ok' => false, 'status' => 'failed', 'error' => $err];
        }
        return ['ok' => $code >= 200 && $code < 300, 'status' => $code < 300 ? 'sent' : 'failed', 'id' => null, 'raw' => $body];
    }
}

class WhatsAppAdapter implements NotificationProvider
{
    public function channel(): string
    {
        return 'whatsapp';
    }

    public function send(string $recipient, string $message, array $meta = []): array
    {
        $key = envv('AFRICAS_TALKING_API_KEY');
        if ($key === '') {
            return [
                'ok' => true,
                'sandbox' => true,
                'provider' => 'africas_talking_whatsapp',
                'status' => 'queued_sandbox',
                'id' => 'wa_sim_' . bin2hex(random_bytes(4)),
            ];
        }
        return [
            'ok' => true,
            'sandbox' => true,
            'provider' => 'africas_talking_whatsapp',
            'status' => 'accepted',
            'id' => 'wa_' . bin2hex(random_bytes(4)),
            'note' => 'WhatsApp Cloud/AT sandbox endpoint reserved; live send disabled in POC.',
        ];
    }
}

class NotificationService
{
    /** @var NotificationProvider[] */
    private array $providers;

    public function __construct()
    {
        $this->providers = [
            'sms' => new SmsAdapter(),
            'whatsapp' => new WhatsAppAdapter(),
        ];
    }

    public function notify(?int $userId, string $recipient, string $message, array $channels = ['sms', 'whatsapp']): array
    {
        $results = [];
        foreach ($channels as $channel) {
            $provider = $this->providers[$channel] ?? $this->providers['sms'];
            $row = $this->persist($userId, $recipient, $channel, $message, 'queued', $provider->channel());
            $attempt = $this->attempt($row, $provider, $recipient, $message);
            $results[] = $attempt;
        }
        $this->processQueue();
        return $results;
    }

    private function persist(?int $userId, string $recipient, string $channel, string $message, string $status, string $provider): array
    {
        db()->prepare('INSERT INTO notifications(recipient, user_id, channel, status, message, provider, attempts, created_at) VALUES (?,?,?,?,?,?,0,?)')
            ->execute([$recipient, $userId, $channel, $status, $message, $provider, now_iso()]);
        $id = (int) db()->lastInsertId();
        return ['notification_id' => $id];
    }

    private function attempt(array $row, NotificationProvider $provider, string $recipient, string $message): array
    {
        $id = (int) $row['notification_id'];
        try {
            $res = $provider->send($recipient, $message);
            $ok = !empty($res['ok']);
            db()->prepare('UPDATE notifications SET status=?, delivery_status=?, provider_message_id=?, attempts=attempts+1, last_error=? WHERE notification_id=?')
                ->execute([
                    $ok ? ($res['status'] ?? 'sent') : 'failed',
                    $res['status'] ?? null,
                    $res['id'] ?? null,
                    $ok ? null : ($res['error'] ?? 'send failed'),
                    $id,
                ]);
            if (!$ok) {
                db()->prepare('INSERT INTO notification_queue(notification_id, payload, next_attempt_at, done) VALUES (?,?,?,0)')
                    ->execute([$id, json_encode(['recipient' => $recipient, 'message' => $message, 'channel' => $provider->channel()]), gmdate('c', time() + 120)]);
            }
            return $res + ['notification_id' => $id];
        } catch (Throwable $e) {
            db()->prepare('UPDATE notifications SET status=?, last_error=?, attempts=attempts+1 WHERE notification_id=?')
                ->execute(['failed', $e->getMessage(), $id]);
            return ['ok' => false, 'error' => $e->getMessage(), 'notification_id' => $id];
        }
    }

    public function processQueue(int $limit = 10): int
    {
        $rows = db()->query("SELECT * FROM notification_queue WHERE done=0 AND next_attempt_at <= datetime('now') LIMIT $limit")->fetchAll();
        $n = 0;
        foreach ($rows as $q) {
            $payload = json_decode($q['payload'], true) ?: [];
            $channel = $payload['channel'] ?? 'sms';
            $provider = $this->providers[$channel] ?? $this->providers['sms'];
            $res = $provider->send($payload['recipient'] ?? '', $payload['message'] ?? '');
            $done = !empty($res['ok']) ? 1 : 0;
            db()->prepare('UPDATE notification_queue SET done=? WHERE queue_id=?')->execute([$done, $q['queue_id']]);
            $n++;
        }
        return $n;
    }
}

function notify_user(?int $userId, string $phone, string $message): void
{
    (new NotificationService())->notify($userId, $phone, $message);
}
