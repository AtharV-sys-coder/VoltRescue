# Keeps VoltRescue reachable from other devices while this PC is awake.
#
# ROOT CAUSE (proven in cloudflared logs):
# Cloudflare Quick Tunnels are deleted server-side once the connector has
# been disconnected for ~5 minutes, and they are also revoked after several
# hours even if the process is still running. After that the hostname no
# longer resolves and the connector logs "Unauthorized: Tunnel not found"
# forever. The previous keeper only checked whether cloudflared.exe existed,
# so it kept advertising a dead URL.
#
# This keeper probes the public hostname every cycle. If DNS fails, HTTP
# is not 200, or the log says "Tunnel not found", the connector is recycled.
# Windows sleep is inhibited for the life of this process so a 3-hour AC
# standby cannot trigger the 5-minute abandonment window.
#
# A hostname that never changes still needs NGROK_AUTHTOKEN in .env.

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

$mutex = New-Object System.Threading.Mutex($false, 'Global\VoltRescueKeepShared')
if (-not $mutex.WaitOne(0)) { exit 0 }

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class VrPower {
  [DllImport("kernel32.dll")]
  public static extern uint SetThreadExecutionState(uint esFlags);
}
"@
# ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_AWAYMODE_REQUIRED
# PowerShell parses 0x80000000 as a signed Int32, so the combined flag must
# be built as UInt32 from a hex string rather than -bor on literals.
$script:StayAwake = [Convert]::ToUInt32('80000041', 16)
$script:ClearAwake = [Convert]::ToUInt32('80000000', 16)
[VrPower]::SetThreadExecutionState($script:StayAwake) | Out-Null

$port = 8811
$ngrokToken = ''
$envFile = Join-Path $root '.env'
if (-not (Test-Path $envFile)) { $envFile = Join-Path $root '.env.example' }
foreach ($line in Get-Content $envFile) {
  if ($line -match '^\s*APP_PORT\s*=\s*(\d+)') { $port = [int]$Matches[1] }
  if ($line -match '^\s*NGROK_AUTHTOKEN\s*=\s*(\S+)') { $ngrokToken = $Matches[1].Trim() }
}
$local = "http://127.0.0.1:$port/"
$urlFile = Join-Path $root 'share-url.txt'
$cfBin = Join-Path $root 'tools\cloudflared.exe'
$ngrokBin = Join-Path $root 'tools\ngrok.exe'
$cfErr = Join-Path $env:TEMP 'vr-keep-cf.err.log'
$cfOut = Join-Path $env:TEMP 'vr-keep-cf.out.log'
$stateLog = Join-Path $root 'share-keeper.log'

function Write-State($msg) {
  $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $msg"
  Add-Content -Path $stateLog -Value $line -Encoding ascii
}

function Test-LocalHealth {
  try { Invoke-WebRequest -UseBasicParsing "$($local)api/health" -TimeoutSec 5 | Out-Null; return $true }
  catch { return $false }
}

function Test-PublicHealth([string]$url) {
  if (-not $url) { return $false }
  try {
    $r = Invoke-WebRequest -UseBasicParsing $url -TimeoutSec 15
    return ($r.StatusCode -ge 200 -and $r.StatusCode -lt 400)
  } catch { return $false }
}

function Test-TunnelRevoked {
  foreach ($path in @($cfErr, $cfOut)) {
    if (-not (Test-Path $path)) { continue }
    $tail = Get-Content $path -Tail 40 -ErrorAction SilentlyContinue
    if ($tail -match 'Tunnel not found|no such host|Unregistered tunnel') { return $true }
  }
  return $false
}

function Ensure-Server {
  if (Test-LocalHealth) { return }
  Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*server.ps1*' -and $_.CommandLine -notlike '*LibraryOnly*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  Start-Process -FilePath 'powershell' -WindowStyle Hidden -WorkingDirectory $root `
    -ArgumentList '-NoProfile', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $root 'server.ps1')
  for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Seconds 1
    if (Test-LocalHealth) { Write-State 'server up'; return }
  }
  Write-State 'server failed to start'
}

function Read-CfUrl {
  $found = $null
  foreach ($path in @($cfErr, $cfOut)) {
    if (-not (Test-Path $path)) { continue }
    $text = Get-Content $path -Raw -ErrorAction SilentlyContinue
    if (-not $text) { continue }
    foreach ($m in [regex]::Matches($text, 'https://[a-z0-9-]+\.trycloudflare\.com')) {
      $found = $m.Value
    }
  }
  return $found
}

function Read-NgrokUrl {
  try {
    $t = Invoke-RestMethod 'http://127.0.0.1:4040/api/tunnels' -TimeoutSec 3
    $https = @($t.tunnels | Where-Object { $_.public_url -like 'https://*' } | Select-Object -First 1)
    if ($https) { return $https.public_url }
  } catch { }
  return $null
}

function Stop-Cloudflare {
  Get-Process cloudflared -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 1
  Remove-Item $cfErr, $cfOut -Force -ErrorAction SilentlyContinue
}

function Start-Cloudflare {
  if (-not (Test-Path $cfBin)) { return $null }
  Stop-Cloudflare
  Start-Process -FilePath $cfBin -WindowStyle Hidden -RedirectStandardOutput $cfOut -RedirectStandardError $cfErr `
    -ArgumentList @(
      'tunnel', '--url', $local, '--no-autoupdate',
      '--protocol', 'http2', '--edge-ip-version', '4',
      '--http-host-header', "127.0.0.1:$port"
    )
  for ($i = 0; $i -lt 45; $i++) {
    Start-Sleep -Seconds 1
    $url = Read-CfUrl
    if ($url -and (Test-PublicHealth $url)) { return $url }
  }
  return (Read-CfUrl)
}

function Ensure-Cloudflare {
  if (-not (Test-Path $cfBin)) { return $null }
  $url = $null
  if (Get-Process cloudflared -ErrorAction SilentlyContinue) { $url = Read-CfUrl }
  $dead = (-not (Get-Process cloudflared -ErrorAction SilentlyContinue)) -or
          (Test-TunnelRevoked) -or
          (-not $url) -or
          (-not (Test-PublicHealth $url))
  if ($dead) {
    Write-State "recycling cloudflare tunnel (was $url)"
    $url = Start-Cloudflare
    Write-State "cloudflare url $url"
  }
  return $url
}

function Ensure-Ngrok {
  if (-not $ngrokToken -or -not (Test-Path $ngrokBin)) { return $null }
  $url = $null
  if (Get-Process ngrok -ErrorAction SilentlyContinue) { $url = Read-NgrokUrl }
  if ($url -and (Test-PublicHealth $url)) { return $url }
  Get-Process ngrok -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  & $ngrokBin config add-authtoken $ngrokToken 2>$null | Out-Null
  Start-Process -FilePath $ngrokBin -WindowStyle Hidden -ArgumentList @('http', "127.0.0.1:$port", '--log', 'stdout')
  for ($i = 0; $i -lt 25; $i++) {
    Start-Sleep -Seconds 1
    $url = Read-NgrokUrl
    if ($url -and (Test-PublicHealth $url)) { return $url }
  }
  return $url
}

try {
  Write-State 'keeper started'
  while ($true) {
    try {
      [VrPower]::SetThreadExecutionState($script:StayAwake) | Out-Null
      Ensure-Server
      $public = Ensure-Ngrok
      if (-not $public) { $public = Ensure-Cloudflare }
      if ($public) {
        Set-Content -Path $urlFile -Value $public -Encoding ascii
        [void](Test-PublicHealth $public)
      }
    } catch {
      Write-State ("loop error: " + $_.Exception.Message)
    }
    Start-Sleep -Seconds 20
  }
} catch {
  Write-State ("fatal: " + $_.Exception.Message)
  throw
} finally {
  [VrPower]::SetThreadExecutionState($script:ClearAwake) | Out-Null
  try { $mutex.ReleaseMutex() | Out-Null } catch { }
  Write-State 'keeper stopped'
}
