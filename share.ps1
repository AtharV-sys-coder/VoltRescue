# VoltRescue — share the running POC with someone on another device.
#
# 127.0.0.1 only works on this computer. This script keeps the app local
# and opens a Cloudflare HTTPS tunnel so a supervisor can open the same
# interface from a phone or laptop anywhere, without being on this Wi-Fi.
#
# Leave this window open while they are using it. Closing it, sleeping the
# PC, or stopping the server takes the public link down.
#
#   powershell -ExecutionPolicy Bypass -File share.ps1

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

$port = 8811
$envFile = Join-Path $root '.env'
if (-not (Test-Path $envFile)) { $envFile = Join-Path $root '.env.example' }
foreach ($line in Get-Content $envFile) {
  if ($line -match '^\s*APP_PORT\s*=\s*(\d+)') { $port = [int]$Matches[1] }
}
$local = "http://127.0.0.1:$port/"
$bin = Join-Path $root 'tools\cloudflared.exe'
$outLog = Join-Path $env:TEMP ("vr-tunnel-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + ".out.log")
$errLog = Join-Path $env:TEMP ("vr-tunnel-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + ".err.log")
$urlFile = Join-Path $root 'share-url.txt'

function Test-Health {
  try { Invoke-WebRequest -UseBasicParsing "$($local)api/health" -TimeoutSec 5 | Out-Null; return $true }
  catch { return $false }
}

Write-Host ""
Write-Host "  VOLTRESCUE  -  SHARE WITH ANOTHER DEVICE" -ForegroundColor White
Write-Host "  $(Get-Date -Format 'dddd d MMMM yyyy, HH:mm')" -ForegroundColor DarkGray
Write-Host ""

if (Test-Health) {
  Write-Host "  [ OK ]  App is running at $local" -ForegroundColor Green
} else {
  Write-Host "  [ .. ]  Starting the app" -ForegroundColor Yellow
  Start-Process -FilePath 'powershell' -WindowStyle Hidden -WorkingDirectory $root `
    -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $root 'server.ps1')
  $up = $false
  for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Seconds 1
    if (Test-Health) { $up = $true; break }
  }
  if (-not $up) { throw "Could not start the app at $local. Run start.ps1 and try again." }
  Write-Host "  [ OK ]  App started at $local" -ForegroundColor Green
}

# Official Cloudflare tunnel client. Kept out of git because it is ~50 MB.
if (-not (Test-Path $bin)) {
  Write-Host "  [ .. ]  Downloading the Cloudflare tunnel client" -ForegroundColor Yellow
  $uri = 'https://github.com/cloudflare/cloudflared/releases/download/2026.9.1/cloudflared-windows-amd64.exe'
  $expect = '2837888CC0F5D58F15B6DC478376DE90B4D3BA5241C7947455D1E0A0DF429712'
  Invoke-WebRequest -Uri $uri -OutFile $bin -UseBasicParsing
  $hash = (Get-FileHash $bin -Algorithm SHA256).Hash
  if ($hash -ne $expect) {
    Remove-Item $bin -Force
    throw "cloudflared checksum mismatch. Expected $expect, got $hash."
  }
  Write-Host "  [ OK ]  Tunnel client saved" -ForegroundColor Green
}

Get-CimInstance Win32_Process -Filter "Name='cloudflared.exe'" -ErrorAction SilentlyContinue |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

$proc = Start-Process -FilePath $bin -PassThru -WindowStyle Hidden -RedirectStandardOutput $outLog -RedirectStandardError $errLog `
  -ArgumentList @(
    'tunnel', '--url', $local, '--no-autoupdate', '--protocol', 'http2',
    '--http-host-header', "127.0.0.1:$port"
  )

$public = $null
for ($i = 0; $i -lt 40; $i++) {
  Start-Sleep -Seconds 1
  foreach ($path in @($errLog, $outLog)) {
    if (-not (Test-Path $path)) { continue }
    $text = Get-Content $path -Raw -ErrorAction SilentlyContinue
    if ($text -match 'https://[a-z0-9-]+\.trycloudflare\.com') {
      $public = $Matches[0]
      break
    }
  }
  if ($public) { break }
  if ($proc.HasExited) { break }
}

if (-not $public) {
  $tail = @()
  foreach ($path in @($errLog, $outLog)) {
    if (Test-Path $path) { $tail += Get-Content $path -Tail 20 }
  }
  throw @"
The public tunnel did not come up. The local app is still running at $local.

Last tunnel output:
$($tail -join "`n")
"@
}

Set-Content -Path $urlFile -Value $public -Encoding ascii
try { Invoke-WebRequest -UseBasicParsing $public -TimeoutSec 20 | Out-Null } catch { }

Write-Host ""
Write-Host ("  " + ("=" * 58)) -ForegroundColor DarkGray
Write-Host "  SEND THIS LINK TO YOUR SUPERVISOR" -ForegroundColor Green
Write-Host ("  " + ("=" * 58)) -ForegroundColor DarkGray
Write-Host ""
Write-Host "  $public" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Suggested message to copy:" -ForegroundColor DarkGray
Write-Host ""
Write-Host @"
  VoltRescue POC is open at:

  $public

  Sign in with any of these (password for all four: VoltRescue!23)

  citizen@voltrescue.local     resident requesting a pickup
  collector@voltrescue.local   collector on an assignment
  recycler@voltrescue.local    recycling partner receiving a load
  admin@voltrescue.local       operations dashboard

  Use the four role chips on the login screen to switch. Please keep
  the tab open on HTTPS; the address is temporary and only works while
  the demonstration machine is awake.
"@
Write-Host ""
Write-Host "  Leave this window open. Press Ctrl+C when the session should end." -ForegroundColor Yellow
Write-Host ""

try {
  Wait-Process -Id $proc.Id
} finally {
  if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
  Remove-Item $outLog, $errLog -Force -ErrorAction SilentlyContinue
  if (Test-Path $urlFile) { Remove-Item $urlFile -Force -ErrorAction SilentlyContinue }
  Write-Host "  Public link closed. The local app is still running at $local"
}
