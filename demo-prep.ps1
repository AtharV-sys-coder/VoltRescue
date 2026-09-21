# VoltRescue — one-command demonstration pre-flight.
#
# Run this 30 minutes before the meeting, with the server already running.
# It verifies the system, proves it with the test suites, then loads clean
# demo data — in that order, because the tests create records of their own
# and must never run after the reset.

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

$port = 8811
$envFile = Join-Path $root '.env'
if (-not (Test-Path $envFile)) { $envFile = Join-Path $root '.env.example' }
foreach ($line in Get-Content $envFile) {
  if ($line -match '^\s*APP_PORT\s*=\s*(\d+)') { $port = [int]$Matches[1] }
}
$url = "http://127.0.0.1:$port/"

function Head($t) { Write-Host ""; Write-Host "  $t" -ForegroundColor Cyan; Write-Host ("  " + ("-" * 58)) -ForegroundColor DarkGray }
function Good($t) { Write-Host "  [ OK ]  $t" -ForegroundColor Green }
function Bad($t)  { Write-Host "  [FAIL]  $t" -ForegroundColor Red }

Write-Host ""
Write-Host "  VOLTRESCUE  -  DEMONSTRATION PRE-FLIGHT" -ForegroundColor White
Write-Host "  $(Get-Date -Format 'dddd d MMMM yyyy, HH:mm')" -ForegroundColor DarkGray

$failures = 0

# --- 1. Is the server answering? -------------------------------------------
# The host does not survive a reboot, a sleep, or the console window that
# launched it being closed, so finding it down on the morning of a demo is
# normal rather than a fault. Start it instead of stopping the pre-flight.
Head "1. Server"

function Test-Health {
  try { Invoke-WebRequest -UseBasicParsing "$($url)api/health" -TimeoutSec 5 | Out-Null; return $true }
  catch { return $false }
}

if (Test-Health) {
  Good "Responding at $url"
}
else {
  Write-Host "  [ .. ]  Not running - starting it" -ForegroundColor Yellow
  Start-Process -FilePath 'powershell' -WindowStyle Hidden -WorkingDirectory $root `
    -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $root 'server.ps1')

  $up = $false
  for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Seconds 1
    if (Test-Health) { $up = $true; break }
  }

  if ($up) {
    Good "Started and responding at $url"
  }
  else {
    Bad "Could not bring the server up at $url"
    Write-Host ""
    Write-Host "  Start it by hand and watch for the error:" -ForegroundColor Yellow
    Write-Host "    right-click start.ps1  ->  Run with PowerShell" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  If it says it cannot bind the port, open .env, change APP_PORT" -ForegroundColor Yellow
    Write-Host "  to the next number, save, and start it again." -ForegroundColor Yellow
    Write-Host ""
    exit 1
  }
}

# --- 2. Prove it works ------------------------------------------------------
Head "2. Unit tests"
$u = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tests\unit.ps1')
$uLine = $u | Select-String 'Unit tests:'
if ($LASTEXITCODE -eq 0) { Good "$uLine" } else { Bad "$uLine"; $failures++; $u | Select-String '^FAIL' }

Head "3. End-to-end API tests"
$a = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tests\run.ps1')
$aLine = $a | Select-String 'API tests:'
if ($LASTEXITCODE -eq 0) { Good "$aLine" } else { Bad "$aLine"; $failures++; $a | Select-String '^FAIL' }

# --- 3. Clean demo data (must come after the tests) -------------------------
Head "4. Loading demonstration data"
$d = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'demo-reset.ps1')
if ($LASTEXITCODE -eq 0) {
  Good "Caseload rebuilt"
  # Only the counter lines here; the cheat sheet is printed separately below.
  $d | Select-String '^\s{2}[\w/ ]+:\s+\d+\s*$' | ForEach-Object { Write-Host "        $($_.ToString().Trim())" -ForegroundColor Gray }
  $sheet = Join-Path $root 'demo-cheatsheet.txt'
  if (Test-Path $sheet) {
    Get-Content $sheet | ForEach-Object { Write-Host $_ -ForegroundColor Cyan }
  }
} else {
  Bad "Demo data reset failed"; $failures++
  $d | Select-Object -Last 8 | ForEach-Object { Write-Host "        $_" -ForegroundColor DarkYellow }
}

# --- 4. Verdict -------------------------------------------------------------
Write-Host ""
Write-Host ("  " + ("=" * 58)) -ForegroundColor DarkGray
if ($failures -eq 0) {
  Write-Host "  READY FOR DEMONSTRATION" -ForegroundColor Green
} else {
  Write-Host "  $failures CHECK(S) FAILED - review the output above" -ForegroundColor Red
}
Write-Host ("  " + ("=" * 58)) -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Open       : $url"
Write-Host "  Password   : VoltRescue!23   (all four accounts)"
Write-Host ""
Write-Host "  citizen@voltrescue.local     Amina Hassan              (submits the request)"
Write-Host "  collector@voltrescue.local   Juma Mwangi               (collects and hands over)"
Write-Host "  recycler@voltrescue.local    GreenCycle Recycling Ltd  (receives and validates)"
Write-Host "  admin@voltrescue.local       Menelick Erick            (oversees everything)"
Write-Host ""
Write-Host "  Demo script: 05_VoltRescue_Demo_Briefing.md, section 2" -ForegroundColor DarkGray
Write-Host ""
