# VoltRescue — demo data reset.
#
# Clears all transactional data and rebuilds a realistic Dar es Salaam pilot
# picture: completed history for the KPI counters, live jobs at every stage of
# the custody chain, and one failure that was recovered.
#
# Every record is created THROUGH THE REST API, so each one carries a genuine
# status history, audit trail and notification set. Nothing is faked into the
# tables directly except the backdating of historical timestamps.
#
# Run this shortly before a demonstration, with the server already running.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$sqlite = Join-Path $root 'tools\sqlite3.exe'
$db = Join-Path $root 'data\voltrescue.sqlite'

$port = 8811
$envFile = Join-Path $root '.env'
if (-not (Test-Path $envFile)) { $envFile = Join-Path $root '.env.example' }
foreach ($line in Get-Content $envFile) {
  if ($line -match '^\s*APP_PORT\s*=\s*(\d+)') { $port = [int]$Matches[1] }
}
$base = "http://127.0.0.1:$port/api"

Add-Type -AssemblyName System.Web.Extensions
$ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer

function Sql($q) { return ("$q" | & $sqlite $db | Out-String).Trim() }
function Api($method, $path, $body, $token) {
  $h = @{ Accept = 'application/json' }
  if ($token) { $h.Authorization = "Bearer $token" }
  $p = @{ Uri = "$base$path"; Method = $method; Headers = $h; UseBasicParsing = $true }
  if ($null -ne $body) { $p.ContentType = 'application/json; charset=utf-8'; $p.Body = $ser.Serialize($body) }
  try { return (Invoke-WebRequest @p).Content | ConvertFrom-Json }
  catch {
    $r = $_.Exception.Response
    if ($r) { $t = (New-Object IO.StreamReader($r.GetResponseStream())).ReadToEnd(); throw "$method $path failed: $t" }
    throw
  }
}
function NoLimit { Sql "DELETE FROM rate_limits;" | Out-Null }

Write-Host "VoltRescue demo reset -> $base"
try { $null = Api GET /health $null $null } catch { Write-Host "Server is not responding. Start it first with start.ps1." -ForegroundColor Red; exit 1 }

# --- 1. Clear transactional data and any leftover test accounts -------------
Write-Host "Clearing previous data..."
Sql @"
DELETE FROM status_history;
DELETE FROM custody_transfers;
DELETE FROM assignments;
DELETE FROM uploads;
DELETE FROM notifications;
DELETE FROM notification_queue;
DELETE FROM audit_logs;
DELETE FROM mpesa_sandbox_tx;
DELETE FROM rate_limits;
DELETE FROM pickup_requests;
DELETE FROM collectors WHERE user_id IN (SELECT user_id FROM users WHERE email NOT LIKE '%@voltrescue.local');
DELETE FROM recyclers  WHERE user_id IN (SELECT user_id FROM users WHERE email NOT LIKE '%@voltrescue.local');
DELETE FROM users WHERE email NOT LIKE '%@voltrescue.local';
UPDATE users SET name='Amina Hassan'             WHERE email='citizen@voltrescue.local';
UPDATE users SET name='Juma Mwangi'              WHERE email='collector@voltrescue.local';
UPDATE users SET name='Neema Kileo'              WHERE email='neema.collector@voltrescue.local';
UPDATE users SET name='GreenCycle Recycling Ltd' WHERE email='recycler@voltrescue.local';
UPDATE users SET name='Menelick Erick'           WHERE email='admin@voltrescue.local';
UPDATE collectors SET name='Juma Mwangi' WHERE phone='255722222222';
UPDATE collectors SET name='Neema Kileo' WHERE phone='255733333333';
"@ | Out-Null

# --- 2. Sign in -------------------------------------------------------------
$admin = (Api POST /auth/login @{ identifier = 'admin@voltrescue.local'; password = 'VoltRescue!23' } $null).token
$citizen = (Api POST /auth/login @{ identifier = 'citizen@voltrescue.local'; password = 'VoltRescue!23' } $null).token
$juma = (Api POST /auth/login @{ identifier = 'collector@voltrescue.local'; password = 'VoltRescue!23' } $null).token
$neema = (Api POST /auth/login @{ identifier = 'neema.collector@voltrescue.local'; password = 'VoltRescue!23' } $null).token
$recycler = (Api POST /auth/login @{ identifier = 'recycler@voltrescue.local'; password = 'VoltRescue!23' } $null).token

$users = Api GET /admin/users $null $admin
$cJuma = [int](@($users.collectors | Where-Object { $_.phone -eq '255722222222' })[0].collector_id)
$cNeema = [int](@($users.collectors | Where-Object { $_.phone -eq '255733333333' })[0].collector_id)
$recId = [int](@($users.recyclers)[0].recycler_id)

# --- 3. Additional citizens, so the dashboard shows a real community --------
Write-Host "Creating pilot residents..."
$people = @(
  @{ name = 'Joseph Mramba'; phone = '255766100201'; email = 'joseph.mramba@example.co.tz' },
  @{ name = 'Fatuma Said';   phone = '255766100202'; email = 'fatuma.said@example.co.tz' },
  @{ name = 'Baraka Nyerere';phone = '255766100203'; email = 'baraka.nyerere@example.co.tz' },
  @{ name = 'Grace Mollel';  phone = '255766100204'; email = 'grace.mollel@example.co.tz' }
)
$tokens = @{ 'Amina Hassan' = $citizen }
foreach ($p in $people) {
  NoLimit
  $r = Api POST /auth/register @{ name = $p.name; phone = $p.phone; email = $p.email; password = 'VoltRescue!23'; role = 'citizen' } $null
  $tokens[$p.name] = $r.token
}

# --- 4. The pilot caseload --------------------------------------------------
# stage: how far down the custody chain each request should be driven.
$caseload = @(
  # Completed history - drives the KPI counters and the CSV export
  @{ who='Amina Hassan';  loc='Msimbazi Street, Kariakoo';    area='Kariakoo';  type='Lead-acid (automotive)'; qty=4; lat=-6.8161; lon=39.2803; col='juma';  stage='complete'; age=9;  note='Four car batteries from a garage clear-out' },
  @{ who='Joseph Mramba'; loc='Mwenge Bus Terminal, Kinondoni';area='Kinondoni';type='Lead-acid (automotive)'; qty=6; lat=-6.7691; lon=39.2312; col='neema'; stage='complete'; age=7;  note='Depot batteries, forklift access available' },
  @{ who='Fatuma Said';   loc='Uhuru Street, Ilala';           area='Ilala';    type='Motorcycle / Bajaji';    qty=9; lat=-6.8235; lon=39.2695; col='juma';  stage='complete'; age=5;  note='Boda boda cooperative collection' },
  @{ who='Baraka Nyerere';loc='Sinza Mori, Ubungo';            area='Ubungo';   type='UPS / Inverter';         qty=3; lat=-6.7845; lon=39.2201; col='neema'; stage='complete'; age=4;  note='Office UPS replacement' },
  @{ who='Grace Mollel';  loc='Mikocheni B, Kinondoni';        area='Kinondoni';type='Solar storage';          qty=2; lat=-6.7602; lon=39.2588; col='neema'; stage='complete'; age=3;  note='Solar home system upgrade' },
  @{ who='Amina Hassan';  loc='Upanga West, Ilala';            area='Ilala';    type='Lithium-ion';            qty=5; lat=-6.8090; lon=39.2856; col='juma';  stage='complete'; age=2;  note='Laptop and power bank cells' },

  # A failure that was handled - proves the exception path is real
  @{ who='Joseph Mramba'; loc='Kigamboni Ferry, Temeke';       area='Temeke';   type='Lead-acid (automotive)'; qty=2; lat=-6.8412; lon=39.3011; col='juma';  stage='noshow';   age=1;  note='Resident asked for an evening slot' },

  # Live caseload - the operational picture on the day
  @{ who='Fatuma Said';   loc='Tandale Market, Kinondoni';     area='Kinondoni';type='Motorcycle / Bajaji';    qty=7; lat=-6.7938; lon=39.2447; col=$null;   stage='pending';  age=0;  note='Market traders collective' },
  @{ who='Grace Mollel';  loc='Buguruni Malapa, Ilala';        area='Ilala';    type='Lead-acid (automotive)'; qty=3; lat=-6.8339; lon=39.2662; col=$null;   stage='pending';  age=0;  note='Behind the fuel station' },
  @{ who='Baraka Nyerere';loc='Vingunguti, Ilala';             area='Ilala';    type='Lithium-ion';            qty=8; lat=-6.8271; lon=39.2519; col=$null;   stage='pending';  age=0;  note='Small workshop, morning preferred' },
  @{ who='Amina Hassan';  loc='Magomeni Mapipa, Kinondoni';    area='Kinondoni';type='UPS / Inverter';         qty=4; lat=-6.7995; lon=39.2492; col='neema'; stage='assigned'; age=0;  note='Internet cafe equipment' },
  @{ who='Joseph Mramba'; loc='Mbagala Rangi Tatu, Temeke';    area='Temeke';   type='Lead-acid (automotive)'; qty=5; lat=-6.9021; lon=39.2673; col='juma';  stage='assigned'; age=0;  note='Transport yard, gate closes at 17:00' },
  @{ who='Fatuma Said';   loc='Masaki Peninsula, Kinondoni';   area='Kinondoni';type='Solar storage';          qty=2; lat=-6.7431; lon=39.2789; col='neema'; stage='accepted'; age=0;  note='Residential compound, guard on duty' },
  @{ who='Grace Mollel';  loc='Ubungo Maziwa, Ubungo';         area='Ubungo';   type='Motorcycle / Bajaji';    qty=6; lat=-6.7873; lon=39.2103; col='juma';  stage='enroute';  age=0;  note='Collector on the way now' },
  @{ who='Baraka Nyerere';loc='Kariakoo Market, Ilala';        area='Kariakoo'; type='Lead-acid (automotive)'; qty=4; lat=-6.8188; lon=39.2761; col='juma';  stage='custody';  age=0;  note='Loaded, awaiting transfer run' },
  @{ who='Amina Hassan';  loc='Kinondoni Shamba, Kinondoni';   area='Kinondoni';type='Lithium-ion';            qty=3; lat=-6.7752; lon=39.2634; col='neema'; stage='transit';  age=0;  note='In transit to GreenCycle' },
  @{ who='Joseph Mramba'; loc='Ilala Boma, Ilala';             area='Ilala';    type='Lead-acid (automotive)'; qty=7; lat=-6.8144; lon=39.2801; col='neema'; stage='received'; age=0;  note='Delivered, awaiting validation' }
)

$colToken = @{ juma = $juma; neema = $neema }
$colId    = @{ juma = $cJuma; neema = $cNeema }
$created  = @()

Write-Host "Building $($caseload.Count) pickup requests through the live API..."
foreach ($c in $caseload) {
  NoLimit
  $tok = $tokens[$c.who]
  $r = Api POST /pickup/create @{
    location = $c.loc; area = $c.area; battery_type = $c.type; quantity = $c.qty
    latitude = $c.lat; longitude = $c.lon; remarks = $c.note
  } $tok
  $rid = [int](@($r.request.request_id) | Select-Object -First 1)
  $created += @{ id = $rid; age = $c.age; stage = $c.stage }

  if ($c.stage -eq 'pending') { continue }

  $ct = $colToken[$c.col]
  Api POST /admin/assign @{ request_id = $rid; collector_id = $colId[$c.col] } $admin | Out-Null
  if ($c.stage -eq 'assigned') { continue }

  Api POST /collector/accept @{ request_id = $rid } $ct | Out-Null
  if ($c.stage -eq 'accepted') { continue }

  Api PUT /pickup/status @{ request_id = $rid; status = 'COLLECTOR_EN_ROUTE' } $ct | Out-Null
  if ($c.stage -eq 'enroute') { continue }

  if ($c.stage -eq 'noshow') {
    Api PUT /pickup/status @{ request_id = $rid; status = 'NO_SHOW'; note = 'Nobody present at the address' } $ct | Out-Null
    continue
  }

  Api PUT /pickup/status @{ request_id = $rid; status = 'PICKUP_COMPLETED'; note = 'Load verified and counted' } $ct | Out-Null
  Api PUT /pickup/status @{ request_id = $rid; status = 'IN_COLLECTOR_CUSTODY' } $ct | Out-Null
  if ($c.stage -eq 'custody') { continue }

  Api POST /collector/handover @{ request_id = $rid; recycler_id = $recId } $ct | Out-Null
  if ($c.stage -eq 'transit') { continue }

  Api POST /recycler/confirm @{ request_id = $rid; action = 'receive' } $recycler | Out-Null
  if ($c.stage -eq 'received') { continue }

  Api POST /recycler/confirm @{ request_id = $rid; action = 'validate'; note = 'Weighed and sorted' } $recycler | Out-Null
  Api POST /recycler/confirm @{ request_id = $rid; action = 'complete' } $recycler | Out-Null
}

# --- 5. Backdate the history so "today" means today -------------------------
Write-Host "Backdating historical records..."
foreach ($c in $created) {
  if ([int]$c.age -le 0) { continue }
  $d = [DateTime]::UtcNow.AddDays(-[int]$c.age)
  $stamp = $d.ToString('yyyy-MM-ddTHH:mm:ssZ')
  Sql @"
UPDATE pickup_requests SET created_at='$stamp' WHERE request_id=$($c.id);
UPDATE status_history  SET updated_time='$stamp' WHERE request_id=$($c.id);
UPDATE assignments     SET assigned_at='$stamp' WHERE request_id=$($c.id);
UPDATE custody_transfers SET transfer_date='$stamp' WHERE request_id=$($c.id);
"@ | Out-Null
}

# --- 6. Report --------------------------------------------------------------
NoLimit
$dash = Api GET /admin/dashboard $null $admin
Write-Host ""
Write-Host "Demo data ready." -ForegroundColor Green
Write-Host ("  Total requests      : {0}" -f $dash.total)
Write-Host ("  Submitted today     : {0}" -f $dash.kpis.today)
Write-Host ("  Pending assignment  : {0}" -f $dash.kpis.pending_assignment)
Write-Host ("  Assigned / active   : {0}" -f $dash.kpis.assigned)
Write-Host ("  With recycler       : {0}" -f $dash.kpis.recycler_pending)
Write-Host ("  Completed           : {0}" -f $dash.kpis.completed)
Write-Host ("  Failed / exceptions : {0}" -f $dash.kpis.failed)
Write-Host ("  Notifications sent  : {0}" -f (Sql "SELECT COUNT(*) FROM notifications;"))
Write-Host ("  Audit records       : {0}" -f (Sql "SELECT COUNT(*) FROM audit_logs;"))
Write-Host ""
Write-Host "Open $($base -replace '/api$','/')   admin@voltrescue.local / VoltRescue!23"
