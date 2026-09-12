# VoltRescue unit tests.
# Dot-sources server.ps1 with -LibraryOnly so the functions load without binding a port.
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. (Join-Path $root 'server.ps1') -LibraryOnly

$passed = 0; $failed = 0
function Check($name, $ok, $detail) {
  if ($ok) { $script:passed++; Write-Host "PASS  $name" }
  else { $script:failed++; Write-Host "FAIL  $name  $detail" }
}

Write-Host "--- unit: SQL quoting and CSV encoding"
Check "Q escapes single quotes" ((Q "O'Brien") -eq "O''Brien") (Q "O'Brien")
Check "Q handles null" ((Q $null) -eq '') 'expected empty string'
Check "Csv-Cell leaves plain text alone" ((Csv-Cell 'Kariakoo') -eq 'Kariakoo') (Csv-Cell 'Kariakoo')
Check "Csv-Cell quotes embedded comma" ((Csv-Cell 'Msimbazi, Kariakoo') -eq '"Msimbazi, Kariakoo"') (Csv-Cell 'Msimbazi, Kariakoo')
Check "Csv-Cell doubles embedded quote" ((Csv-Cell 'the "blue" gate') -eq '"the ""blue"" gate"') (Csv-Cell 'the "blue" gate')
Check "Csv-Cell quotes newline" ((Csv-Cell "line1`nline2").StartsWith('"')) 'expected quoting'

Write-Host "--- unit: password hashing"
$h = Hash-Password 'VoltRescue!23'
Check "hash has salted envelope" ($h -match '^pbkdf2:[0-9a-f]{32}:[0-9a-f]{64}$') $h
Check "correct password verifies" (Test-Password $h 'VoltRescue!23') 'expected true'
Check "wrong password rejected" (-not (Test-Password $h 'VoltRescue!24')) 'expected false'
Check "empty password rejected" (-not (Test-Password $h '')) 'expected false'
Check "salt differs per hash" ($h -ne (Hash-Password 'VoltRescue!23')) 'salts collided'
Check "malformed hash rejected" (-not (Test-Password 'not-a-hash' 'VoltRescue!23')) 'expected false'
# Flip the final hex digit to something it definitely is not, so the tampering
# is guaranteed. Substituting a fixed character is a 1-in-16 no-op.
$lastChar = $h[$h.Length - 1]
$flipped = if ($lastChar -eq 'f') { '0' } else { 'f' }
$tampered = $h.Substring(0, $h.Length - 1) + $flipped
Check "tampered digest rejected" (($tampered -ne $h) -and -not (Test-Password $tampered 'VoltRescue!23')) "tampered=$tampered"

Write-Host "--- unit: JWT issue and verify"
$u = [pscustomobject]@{ user_id = 42; role = 'admin'; name = 'Menelick Admin' }
$tok = Issue-Jwt $u
Check "token has three segments" (($tok.Split('.')).Count -eq 3) $tok
$claims = Parse-Jwt $tok
Check "subject round-trips" ([int]$claims.sub -eq 42) "$($claims.sub)"
Check "role round-trips" ($claims.role -eq 'admin') "$($claims.role)"
Check "expiry is in the future" ([int64]$claims.exp -gt [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) "$($claims.exp)"
$parts = $tok.Split('.')
Check "tampered signature rejected" ($null -eq (Parse-Jwt "$($parts[0]).$($parts[1]).AAAAdeadbeef")) 'expected null'
Check "tampered payload rejected" ($null -eq (Parse-Jwt "$($parts[0]).$(B64UrlStr '{"sub":1,"role":"admin","exp":9999999999}').$($parts[2])")) 'expected null'
Check "garbage token rejected" ($null -eq (Parse-Jwt 'not.a.token')) 'expected null'
Check "empty token rejected" ($null -eq (Parse-Jwt '')) 'expected null'
# Forge a correctly signed but expired token to prove expiry is enforced, not just the signature.
$expH = B64UrlStr '{"typ":"JWT","alg":"HS256"}'
$expP = B64UrlStr ('{"sub":42,"role":"admin","exp":' + ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - 60) + '}')
$hm = New-Object Security.Cryptography.HMACSHA256
$hm.Key = [Text.Encoding]::UTF8.GetBytes($JwtSecret)
$expS = B64Url ($hm.ComputeHash([Text.Encoding]::UTF8.GetBytes("$expH.$expP")))
Check "expired token rejected" ($null -eq (Parse-Jwt "$expH.$expP.$expS")) 'expected null'

Write-Host "--- unit: status lifecycle map"
$success = @('REQUEST_SUBMITTED','PENDING_ASSIGNMENT','COLLECTOR_ASSIGNED','PICKUP_ACCEPTED','COLLECTOR_EN_ROUTE',
             'PICKUP_COMPLETED','IN_COLLECTOR_CUSTODY','TRANSFER_SCHEDULED','IN_TRANSIT_TO_RECYCLER',
             'RECEIVED_BY_RECYCLER','RECYCLER_VALIDATED','PROCESS_COMPLETED')
$failure = @('CANCELLED','REJECTED','NO_SHOW','TRANSFER_FAILED','RECYCLER_REJECTED')
$known = $success + $failure

$chainOk = $true; $chainDetail = ''
for ($i = 0; $i -lt $success.Count - 1; $i++) {
  if ($script:Allowed[$success[$i]] -notcontains $success[$i + 1]) {
    $chainOk = $false; $chainDetail = "$($success[$i]) cannot reach $($success[$i+1])"; break
  }
}
Check "happy path is fully connected" $chainOk $chainDetail

$unknown = @()
foreach ($from in $script:Allowed.Keys) {
  if ($known -notcontains $from) { $unknown += "from:$from" }
  foreach ($to in $script:Allowed[$from]) { if ($known -notcontains $to) { $unknown += "to:$to" } }
}
Check "map references only known statuses" ($unknown.Count -eq 0) ($unknown -join ', ')
Check "terminal success has no exit" ($null -eq $script:Allowed['PROCESS_COMPLETED']) 'PROCESS_COMPLETED should be terminal'
Check "CANCELLED is terminal" ($null -eq $script:Allowed['CANCELLED']) 'CANCELLED should be terminal'
Check "REJECTED is terminal" ($null -eq $script:Allowed['REJECTED']) 'REJECTED should be terminal'
Check "no lifecycle skip from custody to completion" ($script:Allowed['IN_COLLECTOR_CUSTODY'] -notcontains 'PROCESS_COMPLETED') 'illegal skip allowed'
Check "TRANSFER_FAILED can recover" ($script:Allowed['TRANSFER_FAILED'] -contains 'TRANSFER_SCHEDULED') 'no recovery path'
Check "RECYCLER_REJECTED can recover" ($script:Allowed['RECYCLER_REJECTED'] -contains 'IN_COLLECTOR_CUSTODY') 'no recovery path'
Check "NO_SHOW reachable while en route" ($script:Allowed['COLLECTOR_EN_ROUTE'] -contains 'NO_SHOW') 'missing NO_SHOW'
Check "load can be refused at the gate" ($script:Allowed['IN_TRANSIT_TO_RECYCLER'] -contains 'RECYCLER_REJECTED') 'no gate refusal'
$unreachable = @()
foreach ($state in $failure) {
  $reachable = $false
  foreach ($from in @($script:Allowed.Keys)) {
    if ($script:Allowed[$from] -contains $state) { $reachable = $true; break }
  }
  if (-not $reachable) { $unreachable += $state }
}
Check "every failure state is reachable" ($unreachable.Count -eq 0) ($unreachable -join ', ')

Write-Host "--- unit: notification provider abstraction"
$sms = Get-NotificationProvider 'sms'
$wa = Get-NotificationProvider 'whatsapp'
Check "sms adapter reports its channel" ($sms.channel -eq 'sms') "$($sms.channel)"
Check "sms adapter targets Africa's Talking" ($sms.provider -eq 'africas_talking' -and $sms.endpoint -match 'africastalking\.com') "$($sms.endpoint)"
Check "sandbox username selects sandbox host" ($sms.endpoint -match 'sandbox' -or $EnvMap['AFRICAS_TALKING_USERNAME'] -ne 'sandbox') "$($sms.endpoint)"
Check "whatsapp adapter reports its channel" ($wa.channel -eq 'whatsapp') "$($wa.channel)"
Check "whatsapp adapter is a distinct provider" ($wa.provider -ne $sms.provider) "$($wa.provider)"
Check "both channels are registered" ($script:NotifyChannels -contains 'sms' -and $script:NotifyChannels -contains 'whatsapp') ($script:NotifyChannels -join ',')
Check "retry ceiling is configured" ($script:NotifyMaxAttempts -ge 2) "$($script:NotifyMaxAttempts)"

if ([string]::IsNullOrWhiteSpace($EnvMap['AFRICAS_TALKING_API_KEY'])) {
  $sent = Send-ViaProvider 'sms' '255711111111' 'unit test'
  Check "no API key degrades to sandbox, not failure" ($sent.ok -and $sent.status -eq 'queued_sandbox') "$($sent.status)"
  Check "sandbox send returns a traceable id" ([string]$sent.id -match '^sms_sim_') "$($sent.id)"
} else {
  Write-Host "SKIP  sandbox degradation checks (live API key configured)"
}

Write-Host ""
Write-Host "Unit tests: Passed=$passed Failed=$failed"
if ($failed -gt 0) { exit 1 }
