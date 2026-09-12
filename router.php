<?php
declare(strict_types=1);

$uri = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';

if (str_starts_with($uri, '/api')) {
    require __DIR__ . '/api/index.php';
    exit;
}

if (str_starts_with($uri, '/uploads/')) {
    $file = __DIR__ . $uri;
    $real = realpath($file);
    $root = realpath(__DIR__ . '/uploads');
    if ($real && $root && str_starts_with($real, $root) && is_file($real)) {
        $mime = mime_content_type($real) ?: 'application/octet-stream';
        header('Content-Type: ' . $mime);
        readfile($real);
        exit;
    }
    http_response_code(404);
    exit;
}

$file = __DIR__ . '/public' . $uri;
if ($uri !== '/' && is_file($file)) {
    $ext = strtolower(pathinfo($file, PATHINFO_EXTENSION));
    $types = [
        'css' => 'text/css',
        'js' => 'application/javascript',
        'html' => 'text/html',
        'svg' => 'image/svg+xml',
        'png' => 'image/png',
        'jpg' => 'image/jpeg',
        'webp' => 'image/webp',
    ];
    header('Content-Type: ' . ($types[$ext] ?? 'application/octet-stream'));
    readfile($file);
    exit;
}

require __DIR__ . '/public/index.html';
