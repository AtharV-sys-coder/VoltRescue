# VoltRescue POC API + static server (SQLite via tools\sqlite3.exe)
# Windows Application Control blocks unsigned PHP; this host is the runnable POC.
# -LibraryOnly loads the functions without binding a port, so unit tests can dot-source this file.
# -Lan additionally answers on the machine's network address so another device can
# reach the POC. It is deliberately opt-in: the default stays loopback-only,
# because this build has no HTTPS and sends credentials in clear text.
param([switch]$LibraryOnly, [switch]$Lan)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Sqlite = Join-Path $Root "tools\sqlite3.exe"
$DbDir = Join-Path $Root "data"
$Db = Join-Path $DbDir "voltrescue.sqlite"
$Public = Join-Path $Root "public"
$Uploads = Join-Path $Root "uploads"
New-Item -ItemType Directory -Force -Path $DbDir, $Uploads | Out-Null

function Load-Env {
  $map = @{}
  $path = Join-Path $Root ".env"
  if (-not (Test-Path $path)) { $path = Join-Path $Root ".env.example" }
  Get-Content $path | ForEach-Object {
    if ($_ -match '^\s*#' -or $_ -notmatch '=') { return }
    $k, $v = $_.Split('=', 2)
    $map[$k.Trim()] = $v.Trim()
  }
  return $map
}
$EnvMap = Load-Env
$JwtSecret = $(if ($EnvMap['JWT_SECRET']) { $EnvMap['JWT_SECRET'] } else { 'voltrescue-poc-dev-secret-change-in-production' })
$JwtTtl = 28800
# Single source of truth for the listen port. Windows HTTP.sys can keep a prefix
# reserved after a hard kill, so this must be changeable in exactly one place.
$Port = $(
  if ($env:PORT) { [int]$env:PORT }
  elseif ($EnvMap['APP_PORT']) { [int]$EnvMap['APP_PORT'] }
  else { 8811 }
)
# Linux containers (Fly.io) ship sqlite3 on PATH; Windows POC uses the bundled exe.
$sqliteCmd = Get-Command sqlite3 -ErrorAction SilentlyContinue
$Sqlite = if ($sqliteCmd) { $sqliteCmd.Source } else { Join-Path $Root "tools\sqlite3.exe" }

function Now-Iso { [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ') }
function Q([string]$s) { if ($null -eq $s) { '' } else { $s.Replace("'", "''") } }

# SQLite JSON and JWT payloads can surface role as a string, a 1-item array, or
# with odd spacing. Compare only the normalised value so a collector is never
# refused as the wrong role because of a type quirk.
function Get-UserRole($user) {
  if ($null -eq $user) { return '' }
  $raw = $null
  if ($user -is [hashtable]) { $raw = $user['role'] }
  else {
    try { $raw = $user.role } catch { $raw = $null }
  }
  if ($raw -is [System.Array] -and $raw.Length) { $raw = $raw[0] }
  return ([string]$raw).Trim().ToLowerInvariant()
}
function Test-UserRole($user, [string[]]$allowed) {
  return $allowed -contains (Get-UserRole $user)
}

# RFC 4180: quote any cell containing a comma, quote, or newline.
function Csv-Cell($v) {
  $s = if ($null -eq $v) { '' } else { [string]$v }
  if ($s -match '[",\r\n]') { return '"' + $s.Replace('"', '""') + '"' }
  return $s
}

# sqlite3.exe reports failures on stderr; these patterns are how the CLI words them.
function Test-SqliteError([string]$text) {
  return ($text -match '(?m)^\s*(Runtime error|Parse error|Error)\b' -or $text -match 'constraint failed')
}

function Invoke-Exec([string]$sql) {
  $out = ($sql | & $Sqlite $Db 2>&1 | Out-String)
  if (Test-SqliteError $out) { throw ("sqlite: " + $out.Trim()) }
}

# Returns rows unrolled onto the pipeline. Call sites wrap in @() to get a real
# array for 0, 1 or many rows. Do NOT add a comma here: `return ,@(...)` combined
# with @() at the call site nests the result and collapses every list to one item.
function Invoke-Select([string]$sql) {
  $raw = ($sql | & $Sqlite -json $Db 2>&1 | Out-String).Trim()
  if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
  if (Test-SqliteError $raw) { Write-Host "SQL ERROR: $raw"; return @() }
  if (-not $raw.StartsWith('[')) { return @() }
  $parsed = $raw | ConvertFrom-Json
  if ($null -eq $parsed) { return @() }
  return @($parsed)
}

function Invoke-Scalar([string]$sql) {
  $out = ($sql | & $Sqlite $Db 2>&1 | Out-String)
  if (Test-SqliteError $out) { throw ("sqlite: " + $out.Trim()) }
  $lines = @($out -split "`r?`n" | Where-Object { $_.Trim() -ne '' })
  if (-not $lines.Count) { return '' }
  return $lines[-1].Trim()
}

function Invoke-InsertGetId([string]$insertSql) {
  $id = 0
  $value = Invoke-Scalar "$insertSql`nSELECT last_insert_rowid();"
  if (-not [int]::TryParse("$value", [ref]$id) -or $id -le 0) {
    throw "sqlite: insert did not return a row id"
  }
  return $id
}

function Sha256([string]$s) {
  $sha = [Security.Cryptography.SHA256]::Create()
  $bytes = [Text.Encoding]::UTF8.GetBytes($s)
  return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLower()
}
function Hash-Password([string]$p) {
  $salt = [guid]::NewGuid().ToString('N')
  return "pbkdf2:${salt}:" + (Sha256 ($salt + '|' + $p))
}
function Test-Password([string]$stored, [string]$p) {
  if ($stored -match '^pbkdf2:([^:]+):(.+)$') {
    return $Matches[2] -eq (Sha256 ($Matches[1] + '|' + $p))
  }
  return $false
}

function B64Url([byte[]]$bytes) {
  return [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}
function B64UrlStr([string]$s) { B64Url ([Text.Encoding]::UTF8.GetBytes($s)) }
function Issue-Jwt($user) {
  $h = B64UrlStr '{"typ":"JWT","alg":"HS256"}'
  $exp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + $JwtTtl
  $payloadObj = @{ sub = [int]$user.user_id; role = [string]$user.role; name = [string]$user.name; iat = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds(); exp = $exp }
  $payload = ($payloadObj | ConvertTo-Json -Compress)
  $p = B64UrlStr $payload
  $hmac = New-Object Security.Cryptography.HMACSHA256
  $hmac.Key = [Text.Encoding]::UTF8.GetBytes($JwtSecret)
  $sig = B64Url ($hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes("$h.$p")))
  return "$h.$p.$sig"
}
function Parse-Jwt([string]$token) {
  if (-not $token) { return $null }
  $parts = $token.Split('.')
  if ($parts.Count -ne 3) { return $null }
  $hmac = New-Object Security.Cryptography.HMACSHA256
  $hmac.Key = [Text.Encoding]::UTF8.GetBytes($JwtSecret)
  $check = B64Url ($hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes("$($parts[0]).$($parts[1])")))
  if ($check -ne $parts[2]) { return $null }
  $pad = $parts[1].Replace('-', '+').Replace('_', '/')
  while ($pad.Length % 4) { $pad += '=' }
  $json = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($pad))
  $obj = $json | ConvertFrom-Json
  if ([int64]$obj.exp -lt [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) { return $null }
  return $obj
}

$script:Allowed = @{
  REQUEST_SUBMITTED = @('PENDING_ASSIGNMENT','CANCELLED','REJECTED')
  PENDING_ASSIGNMENT = @('COLLECTOR_ASSIGNED','CANCELLED','REJECTED')
  COLLECTOR_ASSIGNED = @('PICKUP_ACCEPTED','CANCELLED','REJECTED','NO_SHOW','PENDING_ASSIGNMENT')
  PICKUP_ACCEPTED = @('COLLECTOR_EN_ROUTE','CANCELLED','NO_SHOW')
  COLLECTOR_EN_ROUTE = @('PICKUP_COMPLETED','NO_SHOW','CANCELLED')
  PICKUP_COMPLETED = @('IN_COLLECTOR_CUSTODY')
  IN_COLLECTOR_CUSTODY = @('TRANSFER_SCHEDULED')
  TRANSFER_SCHEDULED = @('IN_TRANSIT_TO_RECYCLER','TRANSFER_FAILED','CANCELLED')
  # A recycler may refuse a consignment at the gate, before booking it in.
  IN_TRANSIT_TO_RECYCLER = @('RECEIVED_BY_RECYCLER','TRANSFER_FAILED','RECYCLER_REJECTED')
  RECEIVED_BY_RECYCLER = @('RECYCLER_VALIDATED','RECYCLER_REJECTED')
  RECYCLER_VALIDATED = @('PROCESS_COMPLETED')
  RECYCLER_REJECTED = @('TRANSFER_SCHEDULED','IN_COLLECTOR_CUSTODY')
  TRANSFER_FAILED = @('TRANSFER_SCHEDULED','IN_COLLECTOR_CUSTODY')
}

function Init-Db {
  if (-not (Test-Path $Sqlite)) { throw "sqlite3 missing at $Sqlite" }
  $schemaFwd = (Join-Path $Root "api\schema.sql").Replace('\','/')
  & $Sqlite $Db ".read $schemaFwd" | Out-Null
  $n = Invoke-Scalar "SELECT COUNT(*) FROM users;"
  if ([int]$n -eq 0) {
    $hash = Hash-Password 'VoltRescue!23'
    $t = Now-Iso
    Invoke-Exec @"
INSERT INTO users(name,phone,email,role,password_hash,created_at) VALUES
('Amina Hassan','255711111111','citizen@voltrescue.local','citizen','$hash','$t'),
('Juma Mwangi','255722222222','collector@voltrescue.local','collector','$hash','$t'),
('Neema Kileo','255733333333','neema.collector@voltrescue.local','collector','$hash','$t'),
('GreenCycle Recycling Ltd','255744444444','recycler@voltrescue.local','recycler','$hash','$t'),
('Menelick Erick','255755555555','admin@voltrescue.local','admin','$hash','$t');
"@
    $juma = Invoke-Scalar "SELECT user_id FROM users WHERE email='collector@voltrescue.local';"
    $neema = Invoke-Scalar "SELECT user_id FROM users WHERE email='neema.collector@voltrescue.local';"
    $rec = Invoke-Scalar "SELECT user_id FROM users WHERE email='recycler@voltrescue.local';"
    Invoke-Exec "INSERT INTO collectors(user_id,name,phone,vehicle,area,active_flag) VALUES ($juma,'Juma Mwangi','255722222222','Bajaj TR-01','Kariakoo',1);"
    Invoke-Exec "INSERT INTO collectors(user_id,name,phone,vehicle,area,active_flag) VALUES ($neema,'Neema Kileo','255733333333','Van TM-19','Kinondoni',1);"
    Invoke-Exec "INSERT INTO recyclers(user_id,company_name,location,contact_person,phone) VALUES ($rec,'GreenCycle Dar','Vingunguti Industrial Area','Hassan Mtenga','255744444444');"
  }
  $demoHash = Hash-Password 'VoltRescue!23'
  Invoke-Exec "UPDATE users SET password_hash='$demoHash' WHERE email LIKE '%@voltrescue.local';"
}

function Audit($action, $actor, $entity, $entityId, $detail) {
  $d = Q (($detail | ConvertTo-Json -Compress -Depth 6))
  $a = if ($actor) { $actor } else { 'NULL' }
  Invoke-Exec "INSERT INTO audit_logs(action,actor,entity,entity_id,detail,timestamp) VALUES ('$(Q $action)',$a,'$(Q $entity)','$(Q "$entityId")','$d','$(Now-Iso)');"
}

# --- Notification framework -------------------------------------------------
# Provider abstraction: one adapter per channel behind a single send contract.
# Send-ViaProvider is the only place that talks to Africa's Talking.

$script:NotifyChannels   = @('sms', 'whatsapp')
$script:NotifyMaxAttempts = 4
$script:NotifyBaseDelay   = 120

function Get-NotificationProvider([string]$channel) {
  if ($channel -eq 'whatsapp') {
    return @{
      channel  = 'whatsapp'
      provider = 'africas_talking_whatsapp'
      endpoint = 'https://content.africastalking.com/whatsapp/message/send'
      sender   = $EnvMap['AFRICAS_TALKING_WHATSAPP_NUMBER']
    }
  }
  $username = if ($EnvMap['AFRICAS_TALKING_USERNAME']) { $EnvMap['AFRICAS_TALKING_USERNAME'] } else { 'sandbox' }
  $apiHost = if ($username -eq 'sandbox') { 'https://api.sandbox.africastalking.com' } else { 'https://api.africastalking.com' }
  return @{
    channel  = 'sms'
    provider = 'africas_talking'
    endpoint = "$apiHost/version1/messaging"
    sender   = $EnvMap['AFRICAS_TALKING_SENDER_ID']
  }
}

function Send-ViaProvider([string]$channel, [string]$recipient, [string]$message) {
  $p = Get-NotificationProvider $channel
  $key = $EnvMap['AFRICAS_TALKING_API_KEY']

  if ([string]::IsNullOrWhiteSpace($key)) {
    return @{ ok = $true; sandbox = $true; status = 'queued_sandbox'; provider = $p.provider
              id = "$($channel)_sim_" + [guid]::NewGuid().ToString('N').Substring(0, 8) }
  }
  if ($channel -eq 'whatsapp' -and [string]::IsNullOrWhiteSpace($p.sender)) {
    return @{ ok = $false; status = 'failed'; provider = $p.provider
              error = 'AFRICAS_TALKING_WHATSAPP_NUMBER not configured' }
  }

  try {
    $username = if ($EnvMap['AFRICAS_TALKING_USERNAME']) { $EnvMap['AFRICAS_TALKING_USERNAME'] } else { 'sandbox' }
    $form = @{ username = $username; to = $recipient; message = $message }
    if ($p.sender) { $form['from'] = $p.sender }
    $resp = Invoke-RestMethod -Uri $p.endpoint -Method Post -TimeoutSec 15 `
      -Headers @{ apiKey = $key; Accept = 'application/json' } `
      -ContentType 'application/x-www-form-urlencoded' -Body $form
    $rec = $null
    if ($resp.SMSMessageData -and $resp.SMSMessageData.Recipients) { $rec = @($resp.SMSMessageData.Recipients)[0] }
    $accepted = (-not $rec) -or ($rec.status -match 'Success')
    return @{ ok = $accepted; provider = $p.provider
              status = $(if ($accepted) { 'sent' } else { 'failed' })
              id = $(if ($rec) { [string]$rec.messageId } else { $null })
              error = $(if ($accepted) { $null } else { [string]$rec.status }) }
  } catch {
    return @{ ok = $false; status = 'failed'; provider = $p.provider; error = $_.Exception.Message }
  }
}

function Notify-Persist($userId, [string]$recipient, [string]$channel, [string]$message, [string]$provider) {
  $uid = if ($userId) { $userId } else { 'NULL' }
  return Invoke-InsertGetId ("INSERT INTO notifications(recipient,user_id,channel,status,message,provider,delivery_status,attempts,created_at) " +
    "VALUES ('$(Q $recipient)',$uid,'$(Q $channel)','queued','$(Q $message)','$(Q $provider)','pending',0,'$(Now-Iso)');")
}

function Notify-Enqueue([int]$nid, [string]$channel, [string]$recipient, [string]$message, [int]$attempts) {
  $delay = $script:NotifyBaseDelay * [Math]::Pow(2, [Math]::Max(0, $attempts - 1))
  $next = [DateTime]::UtcNow.AddSeconds($delay).ToString('yyyy-MM-ddTHH:mm:ssZ')
  $payload = Q ((@{ recipient = $recipient; message = $message; channel = $channel } | ConvertTo-Json -Compress))
  Invoke-Exec "INSERT INTO notification_queue(notification_id,payload,next_attempt_at,done) VALUES ($nid,'$payload','$next',0);"
}

function Notify-Attempt([int]$nid, [string]$channel, [string]$recipient, [string]$message) {
  $res = Send-ViaProvider $channel $recipient $message
  $mid = if ($res.id) { "'$(Q ([string]$res.id))'" } else { 'NULL' }
  $err = if ($res.error) { "'$(Q ([string]$res.error))'" } else { 'NULL' }
  Invoke-Exec ("UPDATE notifications SET status='$(Q ([string]$res.status))', delivery_status='$(Q ([string]$res.status))', " +
    "provider_message_id=$mid, attempts=attempts+1, last_error=$err WHERE notification_id=$nid;")
  if (-not $res.ok) { Notify-Enqueue $nid $channel $recipient $message 1 }
  return $res
}

function Invoke-NotificationQueue([int]$limit = 10) {
  $due = @(Invoke-Select "SELECT * FROM notification_queue WHERE done=0 AND next_attempt_at <= '$(Now-Iso)' ORDER BY queue_id LIMIT $limit;")
  $processed = 0
  foreach ($q in $due) {
    $payload = $null
    try { $payload = $q.payload | ConvertFrom-Json } catch {}
    if (-not $payload) { Invoke-Exec "UPDATE notification_queue SET done=1 WHERE queue_id=$($q.queue_id);"; continue }
    $nid = [int]$q.notification_id
    $res = Send-ViaProvider ([string]$payload.channel) ([string]$payload.recipient) ([string]$payload.message)
    $attempts = [int](Invoke-Scalar "SELECT attempts FROM notifications WHERE notification_id=$nid;") + 1
    if ($res.ok) {
      $mid = if ($res.id) { "'$(Q ([string]$res.id))'" } else { 'NULL' }
      Invoke-Exec ("UPDATE notifications SET status='sent', delivery_status='sent', provider_message_id=$mid, attempts=$attempts, last_error=NULL WHERE notification_id=$nid;" +
        "`nUPDATE notification_queue SET done=1 WHERE queue_id=$($q.queue_id);")
    } elseif ($attempts -ge $script:NotifyMaxAttempts) {
      Invoke-Exec ("UPDATE notifications SET status='failed_permanent', delivery_status='failed_permanent', attempts=$attempts, last_error='$(Q ([string]$res.error))' WHERE notification_id=$nid;" +
        "`nUPDATE notification_queue SET done=1 WHERE queue_id=$($q.queue_id);")
    } else {
      $delay = $script:NotifyBaseDelay * [Math]::Pow(2, $attempts - 1)
      $next = [DateTime]::UtcNow.AddSeconds($delay).ToString('yyyy-MM-ddTHH:mm:ssZ')
      Invoke-Exec ("UPDATE notifications SET attempts=$attempts, last_error='$(Q ([string]$res.error))' WHERE notification_id=$nid;" +
        "`nUPDATE notification_queue SET next_attempt_at='$next' WHERE queue_id=$($q.queue_id);")
    }
    $processed++
  }
  return $processed
}

function Notify($userId, $phone, $message) {
  if ([string]::IsNullOrWhiteSpace($phone)) { return }
  $anyDelivered = $false
  $anyFailed = $false
  foreach ($ch in $script:NotifyChannels) {
    $p = Get-NotificationProvider $ch
    $nid = Notify-Persist $userId $phone $ch $message $p.provider
    $res = Notify-Attempt $nid $ch $phone $message
    if ($res.ok) { $anyDelivered = $true } else { $anyFailed = $true }
  }
  # Fallback: if no channel got through, record it so operations can see the outage.
  if (-not $anyDelivered) { Audit 'NOTIFY_FAILED' $userId 'notifications' $phone @{ message = $message } }
  if ($anyFailed) { Invoke-NotificationQueue 5 | Out-Null }
}

function Pickup-Row([int]$id) {
  $rows = @(Invoke-Select @"
SELECT p.*, u.name AS citizen_name, u.phone AS citizen_phone,
 a.assignment_id, a.collector_id, a.accepted_at, c.name AS collector_name, c.phone AS collector_phone, c.vehicle,
 t.transfer_id, t.recycler_id, t.status AS transfer_status, r.company_name AS recycler_name
FROM pickup_requests p
JOIN users u ON u.user_id=p.user_id
LEFT JOIN assignments a ON a.request_id=p.request_id
LEFT JOIN collectors c ON c.collector_id=a.collector_id
LEFT JOIN custody_transfers t ON t.transfer_id=(SELECT transfer_id FROM custody_transfers WHERE request_id=p.request_id ORDER BY transfer_id DESC LIMIT 1)
LEFT JOIN recyclers r ON r.recycler_id=t.recycler_id
WHERE p.request_id=$id;
"@)
  if (-not $rows.Count) { return $null }
  $row = $rows[0]
  $row | Add-Member -NotePropertyName timeline -NotePropertyValue @(Invoke-Select "SELECT h.*, u.name AS actor_name FROM status_history h LEFT JOIN users u ON u.user_id=h.updated_by WHERE request_id=$id ORDER BY history_id;") -Force
  $row | Add-Member -NotePropertyName uploads -NotePropertyValue @(Invoke-Select "SELECT * FROM uploads WHERE request_id=$id ORDER BY upload_id;") -Force
  if ($row.latitude -and $row.longitude) {
    $row | Add-Member -NotePropertyName nav_link -NotePropertyValue "https://www.openstreetmap.org/directions?to=$($row.latitude)%2C$($row.longitude)" -Force
    $row | Add-Member -NotePropertyName google_nav -NotePropertyValue "https://www.google.com/maps/dir/?api=1&destination=$($row.latitude),$($row.longitude)" -Force
  }
  return $row
}

function Set-Status([int]$rid, [string]$new, $actor, [string]$note, [bool]$override) {
  $cur = @(Invoke-Select "SELECT * FROM pickup_requests WHERE request_id=$rid;")
  if (-not $cur.Count) { return @{ error = 'Request not found'; code = 404 } }
  $old = $cur[0].status
  if ($old -eq $new) { return @{ request = (Pickup-Row $rid); code = 200 } }
  if (-not $override) {
    $ok = $script:Allowed[$old]
    if (-not $ok -or ($ok -notcontains $new)) {
      return @{ error = "Illegal transition $old -> $new"; allowed = $ok; code = 409 }
    }
  }
  $t = Now-Iso
  Invoke-Exec "UPDATE pickup_requests SET status='$(Q $new)', updated_at='$t' WHERE request_id=$rid;"
  Invoke-Exec "INSERT INTO status_history(request_id,old_status,new_status,updated_by,updated_time,note) VALUES ($rid,'$(Q $old)','$(Q $new)',$($actor.user_id),'$t','$(Q $note)');"
  Audit 'STATUS_CHANGE' $actor.user_id 'pickup_requests' $rid @{ from = $old; to = $new; note = $note; override = $override }
  $owner = @(Invoke-Select "SELECT * FROM users WHERE user_id=$($cur[0].user_id);")
  $msg = "VoltRescue: request #$rid is now $new."
  if ($owner.Count) { Notify $owner[0].user_id $owner[0].phone $msg }
  $col = @(Invoke-Select "SELECT c.phone, c.user_id FROM assignments a JOIN collectors c ON c.collector_id=a.collector_id WHERE a.request_id=$rid;")
  if ($col.Count) { Notify $col[0].user_id $col[0].phone $msg }
  return @{ request = (Pickup-Row $rid); code = 200 }
}

# Evidence may only be attached by the admin, the assigned collector,
# or the recycler receiving the load. Citizens never upload.
function Test-UploadRight($actor, $request) {
  if ($actor.role -eq 'admin') { return $true }
  if ($actor.role -eq 'collector') {
    $col = @(Invoke-Select "SELECT collector_id FROM collectors WHERE user_id=$($actor.user_id);")
    return ($col.Count -gt 0) -and ($request.collector_id) -and ([int]$col[0].collector_id -eq [int]$request.collector_id)
  }
  if ($actor.role -eq 'recycler') {
    $rec = @(Invoke-Select "SELECT recycler_id FROM recyclers WHERE user_id=$($actor.user_id);")
    return ($rec.Count -gt 0) -and ($request.recycler_id) -and ([int]$rec[0].recycler_id -eq [int]$request.recycler_id)
  }
  return $false
}

function Get-UserFromReq($req) {
  $auth = $req.Headers['Authorization']
  $token = $null
  if ($auth -match 'Bearer\s+(\S+)') { $token = $Matches[1] }
  $payload = Parse-Jwt $token
  if (-not $payload) { return $null }
  $rows = @(Invoke-Select "SELECT * FROM users WHERE user_id=$([int]$payload.sub) AND active_flag=1;")
  if ($rows.Count) { return $rows[0] } else { return $null }
}

function Read-Body($req) {
  if ($req.ContentLength64 -eq 0) { return $null }
  $sr = New-Object IO.StreamReader($req.InputStream, [Text.Encoding]::UTF8)
  $text = $sr.ReadToEnd()
  $script:LastRaw = $text
  if ([string]::IsNullOrWhiteSpace($text)) { return $null }
  return $text | ConvertFrom-Json
}

function Send-Json($res, $code, $obj) {
  $json = $obj | ConvertTo-Json -Depth 16 -Compress
  $bytes = [Text.Encoding]::UTF8.GetBytes($json)
  $res.StatusCode = $code
  $res.ContentType = 'application/json; charset=utf-8'
  $res.Headers.Add('Access-Control-Allow-Origin', '*')
  $res.Headers.Add('Cache-Control', 'no-store')
  $res.OutputStream.Write($bytes, 0, $bytes.Length)
  $res.Close()
}

function Send-File($res, $path, $ctype) {
  $bytes = [IO.File]::ReadAllBytes($path)
  $res.StatusCode = 200
  $res.ContentType = $ctype
  $res.OutputStream.Write($bytes, 0, $bytes.Length)
  $res.Close()
}

function Rate-Limit($ip, $bucket, $max, $window) {
  $key = "${bucket}:${ip}"
  $now = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  $row = @(Invoke-Select "SELECT * FROM rate_limits WHERE key='$(Q $key)';")
  if (-not $row.Count -or ($now - [int]$row[0].window_start) -ge $window) {
    Invoke-Exec "INSERT OR REPLACE INTO rate_limits(key,hits,window_start) VALUES ('$(Q $key)',1,$now);"
    return $true
  }
  if ([int]$row[0].hits -ge $max) { return $false }
  Invoke-Exec "UPDATE rate_limits SET hits=hits+1 WHERE key='$(Q $key)';"
  return $true
}

if ($LibraryOnly) { return }

Init-Db

$listener = New-Object Net.HttpListener
# HTTP.sys matches on the Host header, not the socket, so a prefix bound only to
# 127.0.0.1 answers 400 to a browser that asked for localhost - and 'localhost'
# resolves to ::1 first on this machine. Bind all three spellings of loopback so
# whichever form gets typed or pasted reaches the app. Extra prefixes are
# best-effort: losing one must not stop the server coming up.
# Fly.io and other hosts set PORT and send traffic to 0.0.0.0 - loopback-only
# would make the public hostname fail even though the process is running.
$bound = @()
$wanted = @("http://127.0.0.1:$Port/", "http://localhost:$Port/", "http://[::1]:$Port/")
$publicBind = $Lan -or $env:PORT -or $env:FLY_APP_NAME
if ($publicBind) {
  $wanted = @("http://+:$Port/", "http://*:$Port/", "http://0.0.0.0:$Port/") + $wanted
}
foreach ($prefix in $wanted) {
  try { $listener.Prefixes.Add($prefix); $bound += $prefix } catch { }
}
try {
  $listener.Start()
} catch {
  # Retry on loopback alone: the extra spellings need a urlacl on some machines.
  Write-Host "Could not bind all loopback names; falling back to 127.0.0.1 only."
  $listener = New-Object Net.HttpListener
  $listener.Prefixes.Add("http://127.0.0.1:$Port/")
  $bound = @("http://127.0.0.1:$Port/")
  try {
    $listener.Start()
  } catch {
    Write-Host "Cannot bind port $Port. Windows may still hold the prefix (netstat shows PID 4)."
    Write-Host "Set APP_PORT to a free port in .env and start again."
    throw
  }
}
Write-Host "VoltRescue POC  http://127.0.0.1:$Port/"
if ($bound.Count -gt 1) { Write-Host "Also reachable  $($bound[1..($bound.Count-1)] -join '  ')" }
Write-Host 'Demo: admin@voltrescue.local / VoltRescue!23'

while ($listener.IsListening) {
  $ctx = $listener.GetContext()
  $req = $ctx.Request
  $res = $ctx.Response
  $method = $req.HttpMethod
  $path = $req.Url.AbsolutePath
  $ip = $req.RemoteEndPoint.Address.ToString()
  try {
    if ($method -eq 'OPTIONS') {
      $res.StatusCode = 204
      $res.Headers.Add('Access-Control-Allow-Origin', '*')
      $res.Headers.Add('Access-Control-Allow-Headers', 'Authorization, Content-Type')
      $res.Headers.Add('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE,OPTIONS')
      $res.Close(); continue
    }
    if ($path -eq '/' -or $path -eq '/index.html') {
      Send-File $res (Join-Path $Public 'index.html') 'text/html'; continue
    }
    if ($path.StartsWith('/assets/')) {
      $file = Join-Path $Public ($path.TrimStart('/').Replace('/','\'))
      if (Test-Path $file) {
        $ext = [IO.Path]::GetExtension($file)
        $ct = @{ '.js'='application/javascript'; '.css'='text/css' }[$ext]
        if (-not $ct) { $ct = 'application/octet-stream' }
        Send-File $res $file $ct; continue
      }
    }
    if ($path.StartsWith('/uploads/')) {
      $file = Join-Path $Root ($path.TrimStart('/').Replace('/','\'))
      $realRoot = (Resolve-Path $Uploads).Path
      if ((Test-Path $file) -and ((Resolve-Path $file).Path.StartsWith($realRoot))) {
        Send-File $res $file 'application/octet-stream'; continue
      }
      $res.StatusCode = 404; $res.Close(); continue
    }

    $api = $path
    if ($api.StartsWith('/api')) { $api = $api.Substring(4) }
    if (-not $api.StartsWith('/')) { $api = '/' + $api }
    $api = $api.TrimEnd('/')
    if ($api -eq '') { $api = '/' }

    if (-not (Rate-Limit $ip 'api' 120 60)) { Send-Json $res 429 @{ error = 'Too many requests. Retry shortly.' }; continue }

    $user = Get-UserFromReq $req
    $body = $null
    if ($method -in @('POST','PUT','PATCH') -and $req.ContentType -notmatch 'multipart') {
      $body = Read-Body $req
    }

    if ($method -eq 'GET' -and $api -eq '/health') {
      Send-Json $res 200 @{ ok = $true; service = 'VoltRescue POC'; time = (Now-Iso); store = 'sqlite'; users = [int](Invoke-Scalar 'SELECT COUNT(*) FROM users;'); probe = @(Invoke-Select "SELECT role FROM users LIMIT 1;").Count }; continue
    }
    if ($method -eq 'GET' -and $api -eq '/meta/lifecycle') {
      Send-Json $res 200 @{ success = @('REQUEST_SUBMITTED','PENDING_ASSIGNMENT','COLLECTOR_ASSIGNED','PICKUP_ACCEPTED','COLLECTOR_EN_ROUTE','PICKUP_COMPLETED','IN_COLLECTOR_CUSTODY','TRANSFER_SCHEDULED','IN_TRANSIT_TO_RECYCLER','RECEIVED_BY_RECYCLER','RECYCLER_VALIDATED','PROCESS_COMPLETED'); failures = @('CANCELLED','REJECTED','NO_SHOW','TRANSFER_FAILED','RECYCLER_REJECTED'); allowed = $script:Allowed }
      continue
    }

    if ($method -eq 'POST' -and $api -eq '/auth/register') {
      if (-not (Rate-Limit $ip 'register' 10 300)) { Send-Json $res 429 @{ error = 'Too many requests. Retry shortly.' }; continue }
      if (-not $body.name -or -not $body.phone -or -not $body.email -or -not $body.password) {
        Send-Json $res 422 @{ error = 'Missing name, phone, email or password' }; continue
      }
      if ($body.phone -notmatch '^255\d{9}$') { Send-Json $res 422 @{ error = 'Phone must be 255XXXXXXXXX' }; continue }
      if ($body.password.Length -lt 8) { Send-Json $res 422 @{ error = 'Password must be at least 8 characters' }; continue }
      $role = $body.role; if ($role -notin @('citizen','collector','recycler')) { $role = 'citizen' }
      $hash = Hash-Password $body.password
      $t = Now-Iso
      try {
        $id = Invoke-InsertGetId "INSERT INTO users(name,phone,email,role,password_hash,created_at) VALUES ('$(Q $body.name)','$(Q $body.phone)','$(Q $body.email.ToLower())','$role','$hash','$t');"
      } catch { Send-Json $res 409 @{ error = 'Phone or email already registered' }; continue }
      if ($role -eq 'collector') { Invoke-Exec "INSERT INTO collectors(user_id,name,phone,vehicle,area,active_flag) VALUES ($id,'$(Q $body.name)','$(Q $body.phone)','$(Q $body.vehicle)','$(Q $body.area)',1);" }
      $coName = if ($body.company_name) { $body.company_name } else { $body.name }
      if ($role -eq 'recycler') { Invoke-Exec "INSERT INTO recyclers(user_id,company_name,location,contact_person,phone) VALUES ($id,'$(Q $coName)','$(Q $body.location)','$(Q $body.name)','$(Q $body.phone)');" }
      $u = @(Invoke-Select "SELECT user_id,name,phone,email,role,created_at FROM users WHERE user_id=$id;")[0]
      Audit 'REGISTER' $id 'users' $id @{ role = $role }
      Notify $id $body.phone 'VoltRescue: account created. You can submit battery pickups.'
      Send-Json $res 201 @{ user = $u; token = (Issue-Jwt $u) }; continue
    }

    if ($method -eq 'POST' -and $api -eq '/auth/login') {
      if (-not (Rate-Limit $ip 'login' 200 60)) { Send-Json $res 429 @{ error = 'Too many requests. Retry shortly.' }; continue }
      $id = $null
      if ($body.identifier) { $id = [string]$body.identifier }
      elseif ($body.email) { $id = [string]$body.email }
      elseif ($body.phone) { $id = [string]$body.phone }
      $pass = [string]$body.password
      if (-not $pass -and $script:LastRaw -match '"password"\s*:\s*"([^"]*)"') { $pass = $Matches[1] }
      if (-not $id -and $script:LastRaw -match '"identifier"\s*:\s*"([^"]*)"') { $id = $Matches[1] }
      if (-not $id -or -not $pass) { Send-Json $res 422 @{ error = 'Identifier and password required' }; continue }
      $look = Q $id.ToLower()
      $rows = @(Invoke-Select "SELECT user_id, name, phone, email, role, created_at, active_flag, password_hash FROM users WHERE lower(email)='$look' OR phone='$(Q $id)';")
      $okPw = (@($rows).Count -gt 0) -and (Test-Password ([string]$rows[0].password_hash) $pass)
      if (-not $okPw) {
        Audit 'LOGIN_FAILED' $null 'users' $id @{}
        Send-Json $res 401 @{ error = 'Invalid credentials' }
        continue
      }
      $u = $rows[0]
      Audit 'LOGIN' $u.user_id 'users' $u.user_id @{}
      Send-Json $res 200 @{ user = @{ user_id = $u.user_id; name = $u.name; phone = $u.phone; email = $u.email; role = $u.role; created_at = $u.created_at }; token = (Issue-Jwt $u) }
      continue
    }

    if ($method -eq 'GET' -and $api -eq '/auth/me') {
      if (-not $user) { Send-Json $res 401 @{ error = 'Authentication required' }; continue }
      Send-Json $res 200 @{ user = @{ user_id = $user.user_id; name = $user.name; phone = $user.phone; email = $user.email; role = $user.role; created_at = $user.created_at } }; continue
    }
    if ($method -eq 'PUT' -and $api -eq '/auth/me') {
      if (-not $user) { Send-Json $res 401 @{ error = 'Authentication required' }; continue }
      $name = if ($body.name) { $body.name } else { $user.name }
      $email = if ($body.email) { $body.email.ToLower() } else { $user.email }
      Invoke-Exec "UPDATE users SET name='$(Q $name)', email='$(Q $email)' WHERE user_id=$($user.user_id);"
      Audit 'PROFILE_UPDATE' $user.user_id 'users' $user.user_id @{}
      Send-Json $res 200 @{ ok = $true }; continue
    }
    if ($method -eq 'POST' -and $api -eq '/auth/password-reset') {
      $phone = [string]$body.phone
      $rows = @(Invoke-Select "SELECT * FROM users WHERE phone='$(Q $phone)';")
      if ($rows.Count) {
        $tok = [guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N').Substring(0,8)
        $exp = [DateTime]::UtcNow.AddMinutes(30).ToString('yyyy-MM-ddTHH:mm:ssZ')
        Invoke-Exec "UPDATE users SET reset_token='$tok', reset_expires_at='$exp' WHERE user_id=$($rows[0].user_id);"
        Notify $rows[0].user_id $rows[0].phone "VoltRescue password reset code: $tok"
      }
      Send-Json $res 200 @{ ok = $true; message = 'If the phone exists, a reset code was sent.' }; continue
    }
    if ($method -eq 'POST' -and $api -eq '/auth/password-reset/confirm') {
      $rows = @(Invoke-Select "SELECT * FROM users WHERE reset_token='$(Q $body.token)' AND reset_expires_at > '$(Now-Iso)';")
      if (-not $rows.Count -or $body.password.Length -lt 8) { Send-Json $res 422 @{ error = 'Invalid token or password' }; continue }
      $hash = Hash-Password $body.password
      Invoke-Exec "UPDATE users SET password_hash='$hash', reset_token=NULL, reset_expires_at=NULL WHERE user_id=$($rows[0].user_id);"
      Audit 'PASSWORD_RESET' $rows[0].user_id 'users' $rows[0].user_id @{}
      Send-Json $res 200 @{ ok = $true }; continue
    }

    if ($method -eq 'POST' -and $api -eq '/pickup/create') {
      if (-not $user -or $user.role -notin @('citizen','admin')) { Send-Json $res $(if($user){403}else{401}) @{ error = $(if($user){'Insufficient role permission'}else{'Authentication required'}) }; continue }
      $loc = [string]$body.location; $qty = [int]$body.quantity; $type = [string]$body.battery_type
      if (-not $loc -or $qty -lt 1 -or -not $type) { Send-Json $res 422 @{ error = 'location, battery_type and quantity (>=1) are required' }; continue }
      $uid = $user.user_id
      if ($user.role -eq 'admin' -and $body.user_id) { $uid = [int]$body.user_id }
      $lat = if ($null -ne $body.latitude) { $body.latitude } else { 'NULL' }
      $lng = if ($null -ne $body.longitude) { $body.longitude } else { 'NULL' }
      $t = Now-Iso
      $rid = Invoke-InsertGetId "INSERT INTO pickup_requests(user_id,location,area,latitude,longitude,battery_type,quantity,remarks,status,created_at,updated_at) VALUES ($uid,'$(Q $loc)','$(Q $body.area)',$lat,$lng,'$(Q $type)',$qty,'$(Q $body.remarks)','REQUEST_SUBMITTED','$t','$t');"
      Invoke-Exec "INSERT INTO status_history(request_id,old_status,new_status,updated_by,updated_time,note) VALUES ($rid,NULL,'REQUEST_SUBMITTED',$($user.user_id),'$t','created');"
      Audit 'PICKUP_CREATE' $user.user_id 'pickup_requests' $rid $body
      $r = Set-Status $rid 'PENDING_ASSIGNMENT' $user 'Awaiting collector assignment' $false
      Notify $user.user_id $user.phone "VoltRescue: pickup #$rid submitted ($qty x $type)."
      foreach ($a in (Invoke-Select "SELECT user_id, phone FROM users WHERE role='admin' AND active_flag=1;")) {
        Notify $a.user_id $a.phone "VoltRescue: new pickup #$rid needs assignment."
      }
      Send-Json $res 201 @{ request = $r.request }; continue
    }

    if ($method -eq 'GET' -and $api -eq '/pickup') {
      if (-not $user) { Send-Json $res 401 @{ error = 'Authentication required' }; continue }
      $sql = "SELECT p.*, u.name AS citizen_name FROM pickup_requests p JOIN users u ON u.user_id=p.user_id"
      if ($user.role -eq 'citizen') { $sql += " WHERE p.user_id=$($user.user_id)" }
      elseif ($user.role -eq 'collector') { $sql += " JOIN assignments a ON a.request_id=p.request_id JOIN collectors c ON c.collector_id=a.collector_id WHERE c.user_id=$($user.user_id)" }
      elseif ($user.role -eq 'recycler') { $sql += " JOIN custody_transfers t ON t.request_id=p.request_id JOIN recyclers r ON r.recycler_id=t.recycler_id WHERE r.user_id=$($user.user_id)" }
      $sql += " ORDER BY p.request_id DESC;"
      Send-Json $res 200 @{ items = @(Invoke-Select $sql) }; continue
    }

    if ($method -eq 'GET' -and $api -match '^/pickup/(\d+)$') {
      if (-not $user) { Send-Json $res 401 @{ error = 'Authentication required' }; continue }
      $row = Pickup-Row ([int]$Matches[1])
      if (-not $row) { Send-Json $res 404 @{ error = 'Not found' }; continue }
      if ($user.role -eq 'citizen' -and [int]$row.user_id -ne [int]$user.user_id) { Send-Json $res 403 @{ error = 'Forbidden' }; continue }
      Send-Json $res 200 @{ request = $row }; continue
    }

    if ($method -eq 'PUT' -and $api -eq '/pickup/status') {
      if (-not $user) { Send-Json $res 401 @{ error = 'Authentication required' }; continue }
      $rid = [int]$body.request_id; $st = [string]$body.status
      if (-not $rid -or -not $st) { Send-Json $res 422 @{ error = 'request_id and status required' }; continue }
      $ov = ($user.role -eq 'admin' -and $body.override)
      $r = Set-Status $rid $st $user ([string]$body.note) $ov
      Send-Json $res $r.code $(if ($r.error) { $r } else { @{ request = $r.request } })
      continue
    }

    if ($method -eq 'GET' -and $api -eq '/recyclers') {
      if (-not $user -or $user.role -notin @('collector','admin','recycler')) { Send-Json $res $(if($user){403}else{401}) @{ error = 'Insufficient role permission' }; continue }
      Send-Json $res 200 @{ items = @(Invoke-Select 'SELECT recycler_id, company_name, location, contact_person, phone FROM recyclers;') }; continue
    }

    if ($method -eq 'GET' -and $api -eq '/collector/tasks') {
      if (-not $user -or $user.role -notin @('collector','admin')) { Send-Json $res $(if($user){403}else{401}) @{ error = 'Insufficient role permission' }; continue }
      $sql = "SELECT p.*, a.assignment_id, a.accepted_at, c.collector_id, c.name AS collector_name FROM pickup_requests p JOIN assignments a ON a.request_id=p.request_id JOIN collectors c ON c.collector_id=a.collector_id"
      if ($user.role -eq 'collector') { $sql += " WHERE c.user_id=$($user.user_id)" }
      $sql += " ORDER BY p.updated_at DESC;"
      Send-Json $res 200 @{ items = @(Invoke-Select $sql) }; continue
    }

    if ($method -eq 'POST' -and $api -eq '/collector/accept') {
      if (-not $user) { Send-Json $res 401 @{ error = 'Authentication required' }; continue }
      if (-not (Test-UserRole $user @('collector','admin'))) { Send-Json $res 403 @{ error = 'Insufficient role permission' }; continue }
      $rid = [int]$body.request_id
      if (-not $rid) { Send-Json $res 422 @{ error = 'request_id required' }; continue }
      if ((Get-UserRole $user) -eq 'collector') {
        $col = @(Invoke-Select "SELECT * FROM collectors WHERE user_id=$($user.user_id);")
        if (-not $col.Count) { Send-Json $res 403 @{ error = 'Collector profile missing' }; continue }
        $asg = @(Invoke-Select "SELECT * FROM assignments WHERE request_id=$rid AND collector_id=$($col[0].collector_id);")
        if (-not $asg.Count) { Send-Json $res 403 @{ error = 'Not assigned to this collector' }; continue }
      } else {
        $asg = @(Invoke-Select "SELECT * FROM assignments WHERE request_id=$rid;")
        if (-not $asg.Count) { Send-Json $res 403 @{ error = 'Request is not assigned' }; continue }
      }
      Invoke-Exec "UPDATE assignments SET accepted_at='$(Now-Iso)' WHERE request_id=$rid;"
      $r = Set-Status $rid 'PICKUP_ACCEPTED' $user 'Collector accepted assignment' $false
      Send-Json $res $r.code $(if ($r.error) { $r } else { @{ request = $r.request } }); continue
    }

    if ($method -eq 'POST' -and $api -eq '/collector/handover') {
      if (-not $user) { Send-Json $res 401 @{ error = 'Authentication required' }; continue }
      if (-not (Test-UserRole $user @('collector','admin'))) { Send-Json $res 403 @{ error = 'Insufficient role permission' }; continue }
      $rid = [int]$body.request_id; $reid = [int]$body.recycler_id
      if (-not $rid -or -not $reid) { Send-Json $res 422 @{ error = 'request_id and recycler_id required' }; continue }
      $current = Pickup-Row $rid
      if ((Get-UserRole $user) -eq 'collector') {
        $mine = @(Invoke-Select "SELECT * FROM collectors WHERE user_id=$($user.user_id);")
        $col = if ($mine.Count) { $mine[0] } else { $null }
        if (-not $current -or -not $col -or [int]$current.collector_id -ne [int]$col.collector_id) { Send-Json $res 403 @{ error = 'Collector does not hold this request' }; continue }
      } else {
        if (-not $current -or -not $current.collector_id) { Send-Json $res 403 @{ error = 'Request is not assigned' }; continue }
        $col = @(Invoke-Select "SELECT * FROM collectors WHERE collector_id=$([int]$current.collector_id);")[0]
        if (-not $col) { Send-Json $res 403 @{ error = 'Collector profile missing' }; continue }
      }
      if ($current.status -eq 'IN_COLLECTOR_CUSTODY') { Set-Status $rid 'TRANSFER_SCHEDULED' $user 'Handover scheduled' $false | Out-Null }
      Invoke-Exec "INSERT INTO custody_transfers(request_id,collector_id,recycler_id,status,transfer_date,notes) VALUES ($rid,$($col.collector_id),$reid,'IN_TRANSIT_TO_RECYCLER','$(Now-Iso)','$(Q $body.notes)');"
      $row = Pickup-Row $rid
      if ($row.status -eq 'TRANSFER_SCHEDULED') { $row = (Set-Status $rid 'IN_TRANSIT_TO_RECYCLER' $user 'In transit to recycler' $false).request }
      $ruser = @(Invoke-Select "SELECT r.*, u.user_id AS uid, u.phone AS uphone FROM recyclers r JOIN users u ON u.user_id=r.user_id WHERE r.recycler_id=$reid;")
      if ($ruser.Count) { Notify $ruser[0].uid $ruser[0].uphone "VoltRescue: incoming transfer for request #$rid." }
      Send-Json $res 200 @{ request = $row }; continue
    }

    if ($method -eq 'POST' -and $api -eq '/recycler/confirm') {
      if (-not $user -or $user.role -notin @('recycler','admin')) { Send-Json $res $(if($user){403}else{401}) @{ error = 'Insufficient role permission' }; continue }
      $rid = [int]$body.request_id
      $action = if ($body.action) { $body.action } else { 'receive' }
      $row = Pickup-Row $rid
      if (-not $row) { Send-Json $res 404 @{ error = 'Not found' }; continue }
      $map = @{ receive = 'RECEIVED_BY_RECYCLER'; validate = 'RECYCLER_VALIDATED'; reject = 'RECYCLER_REJECTED' }
      if ($action -eq 'complete') {
        if ($row.status -eq 'RECEIVED_BY_RECYCLER') { Set-Status $rid 'RECYCLER_VALIDATED' $user 'Validated on complete' $false | Out-Null }
        $r = Set-Status $rid 'PROCESS_COMPLETED' $user ([string]$body.note) $false
      } else {
        $r = Set-Status $rid $map[$action] $user ([string]$body.note) $false
      }
      if ($r.request) { Invoke-Exec "UPDATE custody_transfers SET status='$(Q $r.request.status)' WHERE request_id=$rid;" }
      Send-Json $res $r.code $(if ($r.error) { $r } else { @{ request = $r.request } }); continue
    }

    if ($method -eq 'GET' -and $api -eq '/admin/dashboard') {
      if (-not $user -or $user.role -ne 'admin') { Send-Json $res $(if($user){403}else{401}) @{ error = 'Insufficient role permission' }; continue }
      $today = [DateTime]::UtcNow.ToString('yyyy-MM-dd')
      $q = [string]$req.QueryString['q']
      $status = [string]$req.QueryString['status']
      $page = 1
      if ($req.QueryString['page']) { $page = [Math]::Max(1, [int]$req.QueryString['page']) }
      $size = 10
      $where = '1=1'; if ($status) { $where += " AND p.status='$(Q $status)'" }
      if ($q) { $where += " AND (p.location LIKE '%$(Q $q)%' OR u.name LIKE '%$(Q $q)%' OR p.battery_type LIKE '%$(Q $q)%')" }
      $total = [int](Invoke-Scalar "SELECT COUNT(*) FROM pickup_requests p JOIN users u ON u.user_id=p.user_id WHERE $where;")
      $off = ($page - 1) * $size
      $items = @(Invoke-Select "SELECT p.*, u.name AS citizen_name FROM pickup_requests p JOIN users u ON u.user_id=p.user_id WHERE $where ORDER BY p.request_id DESC LIMIT $size OFFSET $off;")
      $kpis = @{
        today = [int](Invoke-Scalar "SELECT COUNT(*) FROM pickup_requests WHERE substr(created_at,1,10)='$today';")
        pending_assignment = [int](Invoke-Scalar "SELECT COUNT(*) FROM pickup_requests WHERE status='PENDING_ASSIGNMENT';")
        assigned = [int](Invoke-Scalar "SELECT COUNT(*) FROM pickup_requests WHERE status IN ('COLLECTOR_ASSIGNED','PICKUP_ACCEPTED','COLLECTOR_EN_ROUTE');")
        recycler_pending = [int](Invoke-Scalar "SELECT COUNT(*) FROM pickup_requests WHERE status IN ('IN_TRANSIT_TO_RECYCLER','RECEIVED_BY_RECYCLER');")
        completed = [int](Invoke-Scalar "SELECT COUNT(*) FROM pickup_requests WHERE status='PROCESS_COMPLETED';")
        failed = [int](Invoke-Scalar "SELECT COUNT(*) FROM pickup_requests WHERE status IN ('CANCELLED','REJECTED','NO_SHOW','TRANSFER_FAILED','RECYCLER_REJECTED');")
      }
      $workload = @(Invoke-Select "SELECT c.name, COUNT(*) AS jobs FROM assignments a JOIN collectors c ON c.collector_id=a.collector_id JOIN pickup_requests p ON p.request_id=a.request_id WHERE p.status NOT IN ('PROCESS_COMPLETED','CANCELLED','REJECTED') GROUP BY c.collector_id;")
      Send-Json $res 200 @{ kpis = $kpis; workload = $workload; items = $items; page = $page; size = $size; total = $total }; continue
    }

    if ($method -eq 'GET' -and $api -eq '/admin/export') {
      if (-not $user -or $user.role -ne 'admin') { Send-Json $res 403 @{ error = 'Insufficient role permission' }; continue }
      $rows = @(Invoke-Select "SELECT p.request_id, u.name, p.location, p.battery_type, p.quantity, p.status, p.created_at FROM pickup_requests p JOIN users u ON u.user_id=p.user_id;")
      $sb = New-Object Text.StringBuilder
      [void]$sb.AppendLine('request_id,citizen,location,battery_type,quantity,status,created_at')
      foreach ($r in $rows) {
        $line = @($r.request_id, $r.name, $r.location, $r.battery_type, $r.quantity, $r.status, $r.created_at) |
          ForEach-Object { Csv-Cell $_ }
        [void]$sb.AppendLine(($line -join ','))
      }
      $bytes = [Text.Encoding]::UTF8.GetBytes($sb.ToString())
      $res.StatusCode = 200
      $res.ContentType = 'text/csv'
      $res.AddHeader('Content-Disposition', 'attachment; filename="voltrescue-requests.csv"')
      $res.OutputStream.Write($bytes, 0, $bytes.Length)
      $res.Close(); continue
    }

    if ($method -eq 'POST' -and $api -eq '/admin/assign') {
      if (-not $user -or $user.role -ne 'admin') { Send-Json $res 403 @{ error = 'Insufficient role permission' }; continue }
      $rid = [int]$body.request_id; $cid = [int]$body.collector_id
      $row = Pickup-Row $rid
      if (-not $row) { Send-Json $res 404 @{ error = 'Request not found' }; continue }
      $ex = @(Invoke-Select "SELECT assignment_id FROM assignments WHERE request_id=$rid;")
      if ($ex.Count) { Invoke-Exec "UPDATE assignments SET collector_id=$cid, assigned_at='$(Now-Iso)', assigned_by=$($user.user_id), accepted_at=NULL WHERE request_id=$rid;" }
      else { Invoke-Exec "INSERT INTO assignments(request_id,collector_id,assigned_at,assigned_by) VALUES ($rid,$cid,'$(Now-Iso)',$($user.user_id));" }
      if ($row.status -ne 'COLLECTOR_ASSIGNED') {
        $ov = ($row.status -notin @('PENDING_ASSIGNMENT','REQUEST_SUBMITTED'))
        $row = (Set-Status $rid 'COLLECTOR_ASSIGNED' $user 'Admin assigned collector' $ov).request
      } else { $row = Pickup-Row $rid }
      $c = @(Invoke-Select "SELECT * FROM collectors WHERE collector_id=$cid;")
      if ($c.Count) { Notify $c[0].user_id $c[0].phone "VoltRescue: you were assigned pickup #$rid at $($row.location)." }
      Send-Json $res 200 @{ request = $row }; continue
    }

    if ($method -eq 'GET' -and $api -eq '/admin/users') {
      if (-not $user -or $user.role -ne 'admin') { Send-Json $res 403 @{ error = 'Insufficient role permission' }; continue }
      Send-Json $res 200 @{ users = @(Invoke-Select 'SELECT user_id,name,phone,email,role,active_flag,created_at FROM users ORDER BY user_id;'); collectors = @(Invoke-Select 'SELECT * FROM collectors;'); recyclers = @(Invoke-Select 'SELECT * FROM recyclers;') }; continue
    }
    if ($method -eq 'POST' -and $api -eq '/admin/users') {
      if (-not $user -or $user.role -ne 'admin') { Send-Json $res 403 @{ error = 'Insufficient role permission' }; continue }
      $role = [string]$body.role
      $pass = if ($body.password) { $body.password } else { 'VoltRescue!23' }
      $hash = Hash-Password $pass
      $id = Invoke-InsertGetId "INSERT INTO users(name,phone,email,role,password_hash,created_at) VALUES ('$(Q $body.name)','$(Q $body.phone)','$(Q $body.email.ToLower())','$(Q $role)','$hash','$(Now-Iso)');"
      if ($role -eq 'collector') { Invoke-Exec "INSERT INTO collectors(user_id,name,phone,vehicle,area,active_flag) VALUES ($id,'$(Q $body.name)','$(Q $body.phone)','$(Q $body.vehicle)','$(Q $body.area)',1);" }
      if ($role -eq 'recycler') { Invoke-Exec "INSERT INTO recyclers(user_id,company_name,location,contact_person,phone) VALUES ($id,'$(Q $body.company_name)','$(Q $body.location)','$(Q $body.contact_person)','$(Q $body.phone)');" }
      Audit 'USER_CREATE' $user.user_id 'users' $id @{ role = $role }
      Send-Json $res 201 @{ user_id = $id }; continue
    }

    if ($method -eq 'GET' -and $api -eq '/audit/logs') {
      if (-not $user -or $user.role -ne 'admin') { Send-Json $res 403 @{ error = 'Insufficient role permission' }; continue }
      $page = [int]$req.QueryString['page']; if ($page -lt 1) { $page = 1 }
      $off = ($page - 1) * 25
      Send-Json $res 200 @{ items = @(Invoke-Select "SELECT a.*, u.name AS actor_name FROM audit_logs a LEFT JOIN users u ON u.user_id=a.actor ORDER BY log_id DESC LIMIT 25 OFFSET $off;"); page = $page }; continue
    }

    # Graceful shutdown. Killing the process leaves the prefix reserved in HTTP.sys,
    # which is why the pilot burned through several ports; stopping the listener avoids that.
    if ($method -eq 'POST' -and $api -eq '/admin/shutdown') {
      if (-not $user -or $user.role -ne 'admin') { Send-Json $res $(if($user){403}else{401}) @{ error = 'Insufficient role permission' }; continue }
      Audit 'SHUTDOWN' $user.user_id 'system' '' @{}
      Send-Json $res 200 @{ ok = $true; message = 'Listener stopping' }
      $listener.Stop()
      break
    }

    if ($method -eq 'POST' -and $api -eq '/notifications/process') {
      if (-not $user -or $user.role -ne 'admin') { Send-Json $res $(if($user){403}else{401}) @{ error = 'Insufficient role permission' }; continue }
      $n = Invoke-NotificationQueue 25
      Audit 'NOTIFY_QUEUE_RUN' $user.user_id 'notification_queue' '' @{ processed = $n }
      Send-Json $res 200 @{ processed = $n; pending = [int](Invoke-Scalar 'SELECT COUNT(*) FROM notification_queue WHERE done=0;') }; continue
    }
    if ($method -eq 'GET' -and $api -eq '/notifications/stats') {
      if (-not $user -or $user.role -ne 'admin') { Send-Json $res $(if($user){403}else{401}) @{ error = 'Insufficient role permission' }; continue }
      Send-Json $res 200 @{
        by_channel = @(Invoke-Select 'SELECT channel, status, COUNT(*) AS total FROM notifications GROUP BY channel, status;')
        queue_pending = [int](Invoke-Scalar 'SELECT COUNT(*) FROM notification_queue WHERE done=0;')
        max_attempts = $script:NotifyMaxAttempts
        live_provider = -not [string]::IsNullOrWhiteSpace($EnvMap['AFRICAS_TALKING_API_KEY'])
      }; continue
    }
    # Africa's Talking delivery report webhook. Public by provider design.
    if ($method -eq 'POST' -and $api -eq '/notifications/delivery') {
      $mid = [string]$body.id; if (-not $mid) { $mid = [string]$body.messageId }
      $st = [string]$body.status
      if ($mid -and $st) { Invoke-Exec "UPDATE notifications SET delivery_status='$(Q $st)' WHERE provider_message_id='$(Q $mid)';" }
      Audit 'NOTIFY_DELIVERY_REPORT' $null 'notifications' $mid @{ status = $st }
      Send-Json $res 200 @{ ok = $true }; continue
    }

    if ($method -eq 'GET' -and $api -eq '/notifications') {
      if (-not $user) { Send-Json $res 401 @{ error = 'Authentication required' }; continue }
      Send-Json $res 200 @{ items = @(Invoke-Select "SELECT * FROM notifications WHERE user_id=$($user.user_id) OR recipient='$(Q $user.phone)' ORDER BY notification_id DESC LIMIT 50;") }; continue
    }

    if ($method -eq 'POST' -and $api -eq '/uploads') {
      if (-not $user) { Send-Json $res 401 @{ error = 'Authentication required' }; continue }
      $rid = [int]$body.request_id; $kind = [string]$body.kind
      if (-not $rid -or -not $body.data) { Send-Json $res 422 @{ error = 'request_id and file required' }; continue }
      $target = Pickup-Row $rid
      if (-not $target) { Send-Json $res 404 @{ error = 'Request not found' }; continue }
      if (-not (Test-UploadRight $user $target)) { Send-Json $res 403 @{ error = 'Not permitted to attach evidence to this request' }; continue }
      $bytes = [Convert]::FromBase64String($body.data)
      if ($bytes.Length -gt 5MB) { Send-Json $res 422 @{ error = 'Max 5MB' }; continue }
      $dir = Join-Path $Uploads "$rid"
      New-Item -ItemType Directory -Force -Path $dir | Out-Null
      $ext = 'jpg'
      if ($body.mime -match 'png') { $ext = 'png' }
      if ($body.mime -match 'webp') { $ext = 'webp' }
      $name = "${kind}_$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())_$([guid]::NewGuid().ToString('N').Substring(0,6)).$ext"
      [IO.File]::WriteAllBytes((Join-Path $dir $name), $bytes)
      $rel = "uploads/$rid/$name"
      Invoke-Exec "INSERT INTO uploads(request_id,kind,file_path,mime_type,uploader,created_at) VALUES ($rid,'$(Q $kind)','$(Q $rel)','$(Q $body.mime)',$($user.user_id),'$(Now-Iso)');"
      Audit 'UPLOAD' $user.user_id 'uploads' $rid @{ kind = $kind }
      Send-Json $res 201 @{ file_path = $rel; kind = $kind; created_at = (Now-Iso) }; continue
    }

    if ($method -eq 'GET' -and $api -eq '/mpesa/sandbox/auth') {
      if (-not $user -or $user.role -ne 'admin') { Send-Json $res 403 @{ error = 'Insufficient role permission' }; continue }
      Send-Json $res 200 @{ ok = $true; sandbox = $true; token = 'sandbox-token-voltrescue'; note = 'No live credentials. Sandbox connector only.' }; continue
    }
    if ($method -eq 'POST' -and $api -eq '/mpesa/sandbox/stk') {
      if (-not $user) { Send-Json $res 401 @{ error = 'Authentication required' }; continue }
      if ($body.phone -notmatch '^255\d{9}$' -or [double]$body.amount -le 0) { Send-Json $res 422 @{ ok = $false; errors = @('phone must be 255XXXXXXXXX','amount must be > 0') }; continue }
      $co = 'ws_POC_' + [guid]::NewGuid().ToString('N').Substring(0,12)
      $rid = if ($body.request_id) { [int]$body.request_id } else { 'NULL' }
      Invoke-Exec "INSERT INTO mpesa_sandbox_tx(request_id,amount,phone,status,checkout_id,result,created_at) VALUES ($rid,$($body.amount),'$(Q $body.phone)','SANDBOX_ACCEPTED','$co','{""live"":false}','$(Now-Iso)');"
      Audit 'MPESA_SANDBOX' $user.user_id 'mpesa_sandbox_tx' $body.phone @{ checkout = $co }
      Send-Json $res 200 @{ ok = $true; live = $false; CheckoutRequestID = $co; CustomerMessage = 'Sandbox STK recorded. No live debit.' }; continue
    }
    if ($method -eq 'POST' -and $api -eq '/mpesa/callback') {
      Audit 'MPESA_CALLBACK' $null 'mpesa_sandbox_tx' '' $body
      Send-Json $res 200 @{ ResultCode = 0 }; continue
    }

    Send-Json $res 404 @{ error = 'Unknown API route'; path = $api; method = $method }
  } catch {
    try { Audit 'ERROR' $null 'system' '' @{ message = $_.Exception.Message } } catch {}
    try { Send-Json $res 500 @{ error = 'Server error'; detail = $_.Exception.Message } } catch { try { $res.Close() } catch {} }
  }
}
