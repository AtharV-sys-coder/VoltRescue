# VoltRescue POC — SQLite API (PHP is blocked on this PC by Application Control)
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

# The port lives in .env (APP_PORT) so it only ever has to change in one place.
$port = 8811
$envFile = Join-Path $root '.env'
if (-not (Test-Path $envFile)) { $envFile = Join-Path $root '.env.example' }
foreach ($line in Get-Content $envFile) {
  if ($line -match '^\s*APP_PORT\s*=\s*(\d+)') { $port = [int]$Matches[1] }
}

Write-Host "Starting VoltRescue at http://127.0.0.1:$port/"
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "server.ps1")
