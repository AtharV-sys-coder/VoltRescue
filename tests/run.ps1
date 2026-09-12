# VoltRescue end-to-end API suite. The server must already be running.
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$sqlite = Join-Path $root 'tools\sqlite3.exe'
$db = Join-Path $root 'data\voltrescue.sqlite'

# Read the port from .env so the suite follows the server automatically.
$port = 8811
$envFile = Join-Path $root '.env'
if (-not (Test-Path $envFile)) { $envFile = Join-Path $root '.env.example' }
foreach ($line in Get-Content $envFile) {
  if ($line -match '^\s*APP_PORT\s*=\s*(\d+)') { $port = [int]$Matches[1] }
}
$base = "http://127.0.0.1:$port/api"

$failed = 0; $passed = 0

function First-Int($v) {
  $x = @($v) | Select-Object -First 1
  return [int]$x
}
function Req($method, $path, $body, $token) {
  $h = @{ Accept = "application/json" }
  if ($token) { $h.Authorization = "Bearer $token" }
  $p = @{ Uri = "$base$path"; Method = $method; Headers = $h; UseBasicParsing = $true }
  if ($null -ne $body) {
    $p.ContentType = "application/json; charset=utf-8"
    Add-Type -AssemblyName System.Web.Extensions -ErrorAction SilentlyContinue
    $ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $p.Body = $ser.Serialize($body)
  }
  try {
    $r = Invoke-WebRequest @p
    $j = $null
    try { $j = $r.Content | ConvertFrom-Json } catch {}
    return @{ code = [int]$r.StatusCode; json = $j; raw = $r.Content; headers = $r.Headers }
  } catch {
    $resp = $_.Exception.Response
    $code = if ($resp) { [int]$resp.StatusCode } else { 0 }
    $txt = ""
    if ($resp) {
      $sr = New-Object IO.StreamReader($resp.GetResponseStream())
      $txt = $sr.ReadToEnd()
    }
    $j = $null; try { $j = $txt | ConvertFrom-Json } catch {}
    return @{ code = $code; json = $j; raw = $txt }
  }
}
function Check($name, $ok, $detail) {
  if ($ok) { $script:passed++; Write-Host "PASS  $name" } else { $script:failed++; Write-Host "FAIL  $name  $detail" }
}
function Status-Of($r) { return (@($r.json.request.status) | Select-Object -Last 1) -as [string] }
# The API rate limiter is deliberately strict (120/min). Clear the counters between
# phases so a thorough suite does not trip the protection it is meant to verify.
function Reset-RateLimit { "DELETE FROM rate_limits;" | & $sqlite $db | Out-Null }
function Sql($q) { return ("$($q)" | & $sqlite $db | Out-String).Trim() }

Write-Host "=== A. Smoke and authentication"
$health = Req GET /health $null $null
Check "health endpoint responds" ($health.code -eq 200 -and $health.json.ok) $health.code
Check "health reports sqlite store" ($health.json.store -eq 'sqlite') $health.json.store
$life = Req GET /meta/lifecycle $null $null
Check "lifecycle metadata is public" ($life.code -eq 200 -and @($life.json.success).Count -eq 12) $life.code
Check "lifecycle exposes 5 failure states" (@($life.json.failures).Count -eq 5) (@($life.json.failures).Count)

$bad = Req POST /auth/login @{ identifier = "admin@voltrescue.local"; password = "wrong-password" } $null
Check "wrong password rejected" ($bad.code -eq 401) $bad.code
Check "rejection does not leak account existence" ($bad.json.error -eq 'Invalid credentials') $bad.json.error
$nouser = Req POST /auth/login @{ identifier = "nobody@voltrescue.local"; password = "VoltRescue!23" } $null
Check "unknown user gives identical error" ($nouser.code -eq 401 -and $nouser.json.error -eq 'Invalid credentials') $nouser.json.error

$admin = Req POST /auth/login @{ identifier = "admin@voltrescue.local"; password = "VoltRescue!23" } $null
Check "admin login" ($admin.code -eq 200 -and $admin.json.token) ("code=$($admin.code) err=$($admin.json.error)")
$at = $admin.json.token
$cit = Req POST /auth/login @{ identifier = "citizen@voltrescue.local"; password = "VoltRescue!23" } $null
Check "citizen login" ($cit.code -eq 200) $cit.code
$ct = $cit.json.token
$col = Req POST /auth/login @{ identifier = "collector@voltrescue.local"; password = "VoltRescue!23" } $null
Check "collector login" ($col.code -eq 200) $col.code
$colt = $col.json.token
$col2 = Req POST /auth/login @{ identifier = "neema.collector@voltrescue.local"; password = "VoltRescue!23" } $null
Check "second collector login" ($col2.code -eq 200) $col2.code
$col2t = $col2.json.token
$rec = Req POST /auth/login @{ identifier = "recycler@voltrescue.local"; password = "VoltRescue!23" } $null
Check "recycler login" ($rec.code -eq 200) $rec.code
$rt = $rec.json.token
$byPhone = Req POST /auth/login @{ identifier = "255755555555"; password = "VoltRescue!23" } $null
Check "login by phone number works" ($byPhone.code -eq 200) $byPhone.code
$me = Req GET /auth/me $null $at
Check "auth me returns the signed-in admin" ($me.code -eq 200 -and $me.json.user.role -eq 'admin') $me.code
Check "auth me never returns a password hash" ($null -eq $me.json.user.password_hash) 'hash leaked'
$badTok = Req GET /auth/me $null "not.a.real.token"
Check "forged token rejected" ($badTok.code -eq 401) $badTok.code

Write-Host "=== B. Input validation"
Reset-RateLimit
$v1 = Req POST /auth/register @{ name = "Bad Phone"; phone = "0712345678"; email = "bad1@test.local"; password = "VoltRescue!23" } $null
Check "register rejects non-255 phone" ($v1.code -eq 422) $v1.code
$v2 = Req POST /auth/register @{ name = "Short Pass"; phone = "255700000001"; email = "bad2@test.local"; password = "short" } $null
Check "register rejects short password" ($v2.code -eq 422) $v2.code
$v3 = Req POST /auth/register @{ name = "No Email"; phone = "255700000002" } $null
Check "register rejects missing fields" ($v3.code -eq 422) $v3.code
$v4 = Req POST /auth/register @{ name = "Dup"; phone = "255755555555"; email = "admin@voltrescue.local"; password = "VoltRescue!23" } $null
Check "register rejects duplicate identity" ($v4.code -eq 409) $v4.code
$v5 = Req POST /pickup/create @{ location = ""; battery_type = ""; quantity = 0 } $ct
Check "pickup rejects empty required fields" ($v5.code -eq 422) $v5.code
$v6 = Req POST /pickup/create @{ location = "Somewhere"; battery_type = "Lead-acid"; quantity = 0 } $ct
Check "pickup rejects zero quantity" ($v6.code -eq 422) $v6.code
$v7 = Req PUT /pickup/status @{ status = "PICKUP_ACCEPTED" } $colt
Check "status update rejects missing request id" ($v7.code -eq 422) $v7.code

Write-Host "=== C. Role based access control"
Reset-RateLimit
$anon = Req GET /pickup $null $null
Check "anonymous cannot list pickups" ($anon.code -eq 401) $anon.code
$anon2 = Req GET /admin/dashboard $null $null
Check "anonymous cannot open admin dashboard" ($anon2.code -eq 401) $anon2.code
$f1 = Req GET /admin/dashboard $null $ct
Check "citizen blocked from admin dashboard" ($f1.code -eq 403) $f1.code
$f2 = Req GET /audit/logs $null $ct
Check "citizen blocked from audit logs" ($f2.code -eq 403) $f2.code
$f3 = Req POST /admin/assign @{ request_id = 1; collector_id = 1 } $ct
Check "citizen cannot assign collectors" ($f3.code -eq 403) $f3.code
$f4 = Req POST /pickup/create @{ location = "X"; battery_type = "Lead-acid"; quantity = 1 } $colt
Check "collector cannot create pickups" ($f4.code -eq 403) $f4.code
$f5 = Req GET /collector/tasks $null $ct
Check "citizen cannot read collector tasks" ($f5.code -eq 403) $f5.code
$f6 = Req POST /recycler/confirm @{ request_id = 1; action = "receive" } $colt
Check "collector cannot confirm as recycler" ($f6.code -eq 403) $f6.code
$f7 = Req POST /collector/accept @{ request_id = 1 } $rt
Check "recycler cannot accept assignments" ($f7.code -eq 403) $f7.code
$f8 = Req GET /admin/users $null $rt
Check "recycler blocked from user management" ($f8.code -eq 403) $f8.code
$f9 = Req GET /admin/export $null $colt
Check "collector blocked from CSV export" ($f9.code -eq 403) $f9.code
$f10 = Req POST /notifications/process $null $ct
Check "citizen cannot drain the notification queue" ($f10.code -eq 403) $f10.code
$f11 = Req GET /recyclers $null $ct
Check "citizen cannot enumerate recyclers" ($f11.code -eq 403) $f11.code

Write-Host "=== D. Happy path lifecycle"
Reset-RateLimit
$create = Req POST /pickup/create @{ location = "Kariakoo test stand"; area = "Kariakoo"; battery_type = "Lead-acid"; quantity = 3; latitude = -6.82; longitude = 39.28; remarks = "workflow test" } $ct
Check "citizen creates pickup" ($create.code -eq 201) $create.json.error
$rid = First-Int $create.json.request.request_id
Check "created pickup has a real database id" ($rid -gt 0) "id=$rid"
Check "pickup auto-advances to PENDING_ASSIGNMENT" ((Status-Of $create) -eq "PENDING_ASSIGNMENT") (Status-Of $create)
Check "creation writes two timeline rows" (@($create.json.request.timeline).Count -eq 2) (@($create.json.request.timeline).Count)
Check "GPS coordinates persisted" ([double]$create.json.request.latitude -eq -6.82) "$($create.json.request.latitude)"
Check "navigation link generated from GPS" ([string]$create.json.request.google_nav -match 'google\.com/maps') "$($create.json.request.google_nav)"

$users = Req GET /admin/users $null $at
$cid = First-Int $users.json.collectors[0].collector_id
$cid2 = First-Int $users.json.collectors[1].collector_id
$reid = First-Int $users.json.recyclers[0].recycler_id
Check "admin can list users, collectors and recyclers" ($users.code -eq 200 -and $cid -gt 0 -and $reid -gt 0) "c=$cid r=$reid"

$asg = Req POST /admin/assign @{ request_id = $rid; collector_id = $cid } $at
Check "admin assigns collector" ($asg.code -eq 200 -and (Status-Of $asg) -eq "COLLECTOR_ASSIGNED") $asg.json.error
$wrongCol = Req POST /collector/accept @{ request_id = $rid } $col2t
Check "unassigned collector cannot accept the job" ($wrongCol.code -eq 403) $wrongCol.code
$acc = Req POST /collector/accept @{ request_id = $rid } $colt
Check "assigned collector accepts" ($acc.code -eq 200 -and (Status-Of $acc) -eq "PICKUP_ACCEPTED") $acc.json.error
$illegal = Req PUT /pickup/status @{ request_id = $rid; status = "PROCESS_COMPLETED" } $colt
Check "illegal lifecycle skip blocked" ($illegal.code -eq 409) $illegal.code
Check "conflict response lists legal transitions" (@($illegal.json.allowed).Count -gt 0) "$($illegal.json.allowed)"
foreach ($st in @("COLLECTOR_EN_ROUTE","PICKUP_COMPLETED","IN_COLLECTOR_CUSTODY")) {
  $r = Req PUT /pickup/status @{ request_id = $rid; status = $st } $colt
  Check "collector sets $st" ($r.code -eq 200 -and (Status-Of $r) -eq $st) $r.json.error
}
$hand = Req POST /collector/handover @{ request_id = $rid; recycler_id = $reid } $colt
Check "collector hands over to recycler" ($hand.code -eq 200 -and (Status-Of $hand) -eq "IN_TRANSIT_TO_RECYCLER") $hand.json.error
Check "custody transfer record created" ((Sql "SELECT COUNT(*) FROM custody_transfers WHERE request_id=$rid;") -eq '1') (Sql "SELECT COUNT(*) FROM custody_transfers WHERE request_id=$rid;")
$recv = Req POST /recycler/confirm @{ request_id = $rid; action = "receive" } $rt
Check "recycler confirms receipt" ($recv.code -eq 200 -and (Status-Of $recv) -eq "RECEIVED_BY_RECYCLER") $recv.json.error
$val = Req POST /recycler/confirm @{ request_id = $rid; action = "validate" } $rt
Check "recycler validates materials" ($val.code -eq 200 -and (Status-Of $val) -eq "RECYCLER_VALIDATED") $val.json.error
$done = Req POST /recycler/confirm @{ request_id = $rid; action = "complete" } $rt
Check "recycler completes processing" ($done.code -eq 200 -and (Status-Of $done) -eq "PROCESS_COMPLETED") (Status-Of $done)
Check "timeline recorded all 12 stages" (@($done.json.request.timeline).Count -eq 12) (@($done.json.request.timeline).Count)
Check "every timeline entry names an actor" ((@($done.json.request.timeline) | Where-Object { -not $_.updated_by }).Count -eq 0) 'missing actor'

Write-Host "=== E. Evidence uploads and ownership"
Reset-RateLimit
$png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
$u1 = Req POST /uploads @{ request_id = $rid; kind = "pickup"; mime = "image/png"; data = $png } $ct
Check "citizen cannot upload evidence" ($u1.code -eq 403) $u1.code
$u2 = Req POST /uploads @{ request_id = $rid; kind = "pickup"; mime = "image/png"; data = $png } $colt
Check "assigned collector can upload evidence" ($u2.code -eq 201) $u2.json.error
Check "upload stored under the request folder" ([string]$u2.json.file_path -match "uploads/$rid/pickup_") $u2.json.file_path
$u3 = Req POST /uploads @{ request_id = $rid; kind = "handover"; mime = "image/png"; data = $png } $col2t
Check "unrelated collector cannot upload to this request" ($u3.code -eq 403) $u3.code
$u4 = Req POST /uploads @{ request_id = $rid; kind = "receipt"; mime = "image/png"; data = $png } $rt
Check "receiving recycler can upload receipt proof" ($u4.code -eq 201) $u4.json.error
$u5 = Req POST /uploads @{ request_id = 999999; kind = "pickup"; mime = "image/png"; data = $png } $colt
Check "upload to a missing request is rejected" ($u5.code -eq 404) $u5.code
$u6 = Req POST /uploads @{ request_id = $rid; kind = "pickup" } $colt
Check "upload without file data is rejected" ($u6.code -eq 422) $u6.code
$detail = Req GET "/pickup/$rid" $null $at
Check "uploads visible on the request detail" (@($detail.json.request.uploads).Count -ge 2) (@($detail.json.request.uploads).Count)

Write-Host "=== F. Failure paths and recovery"
Reset-RateLimit
$r2 = Req POST /pickup/create @{ location = "Temeke no-show test"; area = "Temeke"; battery_type = "Li-ion"; quantity = 2 } $ct
$rid2 = First-Int $r2.json.request.request_id
Req POST /admin/assign @{ request_id = $rid2; collector_id = $cid } $at | Out-Null
Req POST /collector/accept @{ request_id = $rid2 } $colt | Out-Null
$noshow = Req PUT /pickup/status @{ request_id = $rid2; status = "NO_SHOW"; note = "Nobody at the gate" } $colt
Check "collector can report NO_SHOW" ($noshow.code -eq 200 -and (Status-Of $noshow) -eq "NO_SHOW") $noshow.json.error
$stuck = Req PUT /pickup/status @{ request_id = $rid2; status = "PICKUP_ACCEPTED" } $colt
Check "NO_SHOW cannot be undone without an override" ($stuck.code -eq 409) $stuck.code
$ovr = Req PUT /pickup/status @{ request_id = $rid2; status = "PENDING_ASSIGNMENT"; override = $true; note = "Admin re-queued" } $at
Check "admin override rescues a NO_SHOW" ($ovr.code -eq 200 -and (Status-Of $ovr) -eq "PENDING_ASSIGNMENT") $ovr.json.error
$ovrDenied = Req PUT /pickup/status @{ request_id = $rid2; status = "PROCESS_COMPLETED"; override = $true } $colt
Check "collector cannot use the override flag" ($ovrDenied.code -eq 409) $ovrDenied.code
$ovrCount = [int](Sql ("SELECT COUNT(*) FROM audit_logs WHERE action='STATUS_CHANGE' AND entity_id='$rid2' AND detail LIKE '%override%true%';"))
Check "override recorded as an override in the audit log" ($ovrCount -ge 1) "count=$ovrCount"

$r3 = Req POST /pickup/create @{ location = "Ilala rejection test"; area = "Ilala"; battery_type = "Automotive"; quantity = 5 } $ct
$rid3 = First-Int $r3.json.request.request_id
Req POST /admin/assign @{ request_id = $rid3; collector_id = $cid2 } $at | Out-Null
Req POST /collector/accept @{ request_id = $rid3 } $col2t | Out-Null
foreach ($st in @("COLLECTOR_EN_ROUTE","PICKUP_COMPLETED","IN_COLLECTOR_CUSTODY")) {
  Req PUT /pickup/status @{ request_id = $rid3; status = $st } $col2t | Out-Null
}
Req POST /collector/handover @{ request_id = $rid3; recycler_id = $reid } $col2t | Out-Null
$rej = Req POST /recycler/confirm @{ request_id = $rid3; action = "reject"; note = "Chemistry mismatch" } $rt
Check "recycler can reject a delivered load" ($rej.code -eq 200 -and (Status-Of $rej) -eq "RECYCLER_REJECTED") $rej.json.error
$back = Req PUT /pickup/status @{ request_id = $rid3; status = "IN_COLLECTOR_CUSTODY"; note = "Returned to collector" } $col2t
Check "rejected load returns to collector custody" ($back.code -eq 200 -and (Status-Of $back) -eq "IN_COLLECTOR_CUSTODY") $back.json.error
$resend = Req POST /collector/handover @{ request_id = $rid3; recycler_id = $reid } $col2t
Check "load can be re-dispatched after rejection" ($resend.code -eq 200 -and (Status-Of $resend) -eq "IN_TRANSIT_TO_RECYCLER") $resend.json.error
Check "second custody transfer recorded" ((Sql "SELECT COUNT(*) FROM custody_transfers WHERE request_id=$rid3;") -eq '2') (Sql "SELECT COUNT(*) FROM custody_transfers WHERE request_id=$rid3;")

Write-Host "=== G. Status transition rules"
Reset-RateLimit
$allowed = $life.json.allowed
Check "PICKUP_COMPLETED only leads to custody" ((@($allowed.PICKUP_COMPLETED) -join ',') -eq 'IN_COLLECTOR_CUSTODY') ((@($allowed.PICKUP_COMPLETED) -join ','))
Check "map forbids custody to completion" (@($allowed.IN_COLLECTOR_CUSTODY) -notcontains 'PROCESS_COMPLETED') "$($allowed.IN_COLLECTOR_CUSTODY)"
$t1 = Req PUT /pickup/status @{ request_id = $rid; status = "COLLECTOR_EN_ROUTE" } $at
Check "completed request cannot move backwards" ($t1.code -eq 409) $t1.code
$t2 = Req PUT /pickup/status @{ request_id = $rid; status = "PROCESS_COMPLETED" } $at
Check "re-applying the current status is idempotent" ($t2.code -eq 200) $t2.code
Check "idempotent re-apply adds no timeline row" (@($t2.json.request.timeline).Count -eq 12) (@($t2.json.request.timeline).Count)
$t3 = Req PUT /pickup/status @{ request_id = 999999; status = "PENDING_ASSIGNMENT" } $at
Check "status update on a missing request returns 404" ($t3.code -eq 404) $t3.code

Write-Host "=== H. Notification framework"
Reset-RateLimit
$notes = Req GET /notifications $null $ct
Check "citizen can read their notifications" ($notes.code -eq 200 -and @($notes.json.items).Count -gt 0) (@($notes.json.items).Count)
Check "SMS channel rows written" ((@($notes.json.items) | Where-Object { $_.channel -eq 'sms' }).Count -gt 0) 'no sms rows'
Check "WhatsApp channel rows written" ((@($notes.json.items) | Where-Object { $_.channel -eq 'whatsapp' }).Count -gt 0) 'no whatsapp rows'
Check "provider recorded on every notification" ((@($notes.json.items) | Where-Object { -not $_.provider }).Count -eq 0) 'missing provider'
Check "delivery status recorded" ((@($notes.json.items) | Where-Object { -not $_.delivery_status }).Count -eq 0) 'missing delivery status'
Check "attempt counter incremented" ((@($notes.json.items) | Where-Object { [int]$_.attempts -lt 1 }).Count -eq 0) 'attempts not counted'
$colNotes = Req GET /notifications $null $colt
Check "assigned collector was notified" ($colNotes.code -eq 200 -and @($colNotes.json.items).Count -gt 0) (@($colNotes.json.items).Count)
$recNotes = Req GET /notifications $null $rt
Check "recycler notified of inbound transfer" ((@($recNotes.json.items) | Where-Object { $_.message -match 'incoming transfer' }).Count -gt 0) 'no inbound alert'
$stats = Req GET /notifications/stats $null $at
Check "admin can read notification statistics" ($stats.code -eq 200 -and $null -ne $stats.json.queue_pending) $stats.code
Check "stats report sandbox provider mode" ($stats.json.live_provider -eq $false) "live_provider=$($stats.json.live_provider)"
$drain = Req POST /notifications/process $null $at
Check "admin can drain the retry queue" ($drain.code -eq 200 -and $null -ne $drain.json.processed) $drain.code
$mid = Sql "SELECT provider_message_id FROM notifications WHERE provider_message_id IS NOT NULL ORDER BY notification_id DESC LIMIT 1;"
$dlr = Req POST /notifications/delivery @{ id = $mid; status = "Delivered" } $null
Check "provider delivery report accepted" ($dlr.code -eq 200) $dlr.code
Check "delivery report updates the stored status" ((Sql "SELECT delivery_status FROM notifications WHERE provider_message_id='$mid';") -match 'Delivered') (Sql "SELECT delivery_status FROM notifications WHERE provider_message_id='$mid';")

Write-Host "=== I. Admin oversight and reporting"
Reset-RateLimit
$dash = Req GET /admin/dashboard $null $at
Check "dashboard returns KPI counters" ($dash.code -eq 200 -and $dash.json.kpis) $dash.code
Check "dashboard counts completed work" ([int]$dash.json.kpis.completed -ge 1) "$($dash.json.kpis.completed)"
Check "dashboard reports collector workload" ($null -ne $dash.json.workload) 'missing workload'
Check "dashboard paginates" ([int]$dash.json.size -eq 10 -and [int]$dash.json.total -ge 3) "size=$($dash.json.size) total=$($dash.json.total)"
$search = Req GET "/admin/dashboard?q=Kariakoo" $null $at
Check "dashboard search filters rows" ($search.code -eq 200 -and @($search.json.items).Count -ge 1) (@($search.json.items).Count)
$filter = Req GET "/admin/dashboard?status=PROCESS_COMPLETED" $null $at
Check "dashboard filters by status" ((@($filter.json.items) | Where-Object { $_.status -ne 'PROCESS_COMPLETED' }).Count -eq 0) 'filter leaked other statuses'
$export = Req GET /admin/export $null $at
Check "CSV export succeeds" ($export.code -eq 200) $export.code
Check "CSV has the expected header" ([string]$export.raw -match 'request_id,citizen,location') 'header missing'
$logs = Req GET /audit/logs $null $at
Check "audit log readable by admin" ($logs.code -eq 200 -and @($logs.json.items).Count -gt 0) $logs.code
Check "status changes are audited" ((@($logs.json.items) | Where-Object { $_.action -eq 'STATUS_CHANGE' }).Count -gt 0) 'no status audit'
Check "logins are audited" ((Sql "SELECT COUNT(*) FROM audit_logs WHERE action='LOGIN';") -ge '1') 'no login audit'
Check "failed logins are audited" ((Sql "SELECT COUNT(*) FROM audit_logs WHERE action='LOGIN_FAILED';") -ge '1') 'no failed-login audit'
Check "uploads are audited" ((Sql "SELECT COUNT(*) FROM audit_logs WHERE action='UPLOAD';") -ge '1') 'no upload audit'
$newUser = Req POST /admin/users @{ name = "Test Collector"; phone = "2557$((Get-Random -Minimum 10000000 -Maximum 99999999))"; email = "tc$(Get-Random)@voltrescue.test"; role = "collector"; vehicle = "Test TR-99"; area = "Ubungo" } $at
Check "admin creates a collector account" ($newUser.code -eq 201 -and $newUser.json.user_id) $newUser.json.error
Check "collector profile auto-created" ((Sql "SELECT COUNT(*) FROM collectors WHERE user_id=$($newUser.json.user_id);") -eq '1') 'profile missing'

Write-Host "=== J. Integration connectors"
Reset-RateLimit
$mp = Req GET /mpesa/sandbox/auth $null $at
Check "M-Pesa sandbox authenticates" ($mp.code -eq 200 -and $mp.json.ok) $mp.code
Check "M-Pesa reports sandbox mode" ($mp.json.sandbox -eq $true) "$($mp.json.sandbox)"
$stkBad = Req POST /mpesa/sandbox/stk @{ phone = "0712345678"; amount = 100 } $at
Check "M-Pesa validates phone format" ($stkBad.code -eq 422) $stkBad.code
$stkBad2 = Req POST /mpesa/sandbox/stk @{ phone = "255712345678"; amount = 0 } $at
Check "M-Pesa validates amount" ($stkBad2.code -eq 422) $stkBad2.code
$stk = Req POST /mpesa/sandbox/stk @{ phone = "255712345678"; amount = 1500; request_id = $rid } $at
Check "M-Pesa sandbox STK accepted" ($stk.code -eq 200 -and $stk.json.CheckoutRequestID) $stk.json.error
Check "M-Pesa never claims a live debit" ($stk.json.live -eq $false) "$($stk.json.live)"
Check "sandbox transaction persisted" ((Sql "SELECT COUNT(*) FROM mpesa_sandbox_tx WHERE checkout_id='$($stk.json.CheckoutRequestID)';") -eq '1') 'not stored'
$cb = Req POST /mpesa/callback @{ Body = @{ stkCallback = @{ ResultCode = 0 } } } $null
Check "M-Pesa callback endpoint answers" ($cb.code -eq 200) $cb.code

Write-Host "=== K. Database persistence"
Reset-RateLimit
$fetch = Req GET "/pickup/$rid" $null $ct
Check "request re-reads identically from the database" ($fetch.json.request.location -eq "Kariakoo test stand") $fetch.json.request.location
Check "final status durable across requests" ($fetch.json.request.status -eq "PROCESS_COMPLETED") $fetch.json.request.status
Check "row count matches API view" ((Sql "SELECT COUNT(*) FROM pickup_requests WHERE request_id=$rid;") -eq '1') 'row missing'
Check "status history durable in the database" ((Sql "SELECT COUNT(*) FROM status_history WHERE request_id=$rid;") -eq '12') (Sql "SELECT COUNT(*) FROM status_history WHERE request_id=$rid;")
Check "assignment durable in the database" ((Sql "SELECT COUNT(*) FROM assignments WHERE request_id=$rid;") -eq '1') 'assignment missing'
$other = Req GET "/pickup/$rid" $null $rt
Check "recycler can read a request in their chain" ($other.code -eq 200) $other.code
$crossRole = Req GET /pickup $null $ct
$citId = First-Int $cit.json.user.user_id
Check "citizen list is scoped to their own requests" ((@($crossRole.json.items) | Where-Object { (First-Int $_.user_id) -ne $citId }).Count -eq 0) 'saw other users rows'
Check "citizen list returns every own request" (@($crossRole.json.items).Count -ge 3) (@($crossRole.json.items).Count)
$colList = Req GET /collector/tasks $null $col2t
Check "collector list is scoped to their own assignments" ((@($colList.json.items) | Where-Object { [int]$_.collector_id -ne $cid2 }).Count -eq 0) 'saw other collector rows'

Write-Host ""
Write-Host "API tests: Passed=$passed Failed=$failed"
if ($failed -gt 0) { exit 1 }
