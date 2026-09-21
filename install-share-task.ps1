# Registers a per-user task that starts at logon AND retries every 5 minutes
# so a killed keeper is brought back without waiting for the next reboot.
#
#   powershell -ExecutionPolicy Bypass -File install-share-task.ps1

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$keeper = Join-Path $root 'keep-shared.ps1'
$name = 'VoltRescueShare'

$action = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
  -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$keeper`"" `
  -WorkingDirectory $root

$logon = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$repeat = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(1)) `
  -RepetitionInterval (New-TimeSpan -Minutes 5) `
  -RepetitionDuration (New-TimeSpan -Days 3650)

$settings = New-ScheduledTaskSettingsSet `
  -AllowStartIfOnBatteries `
  -DontStopIfGoingOnBatteries `
  -StartWhenAvailable `
  -RestartCount 5 `
  -RestartInterval (New-TimeSpan -Minutes 1) `
  -ExecutionTimeLimit (New-TimeSpan -Days 365) `
  -MultipleInstances IgnoreNew

Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName $name -Action $action -Trigger @($logon, $repeat) -Settings $settings `
  -Description 'Keeps the VoltRescue POC reachable. Restarts the keeper if it dies.' -Force | Out-Null
Start-ScheduledTask -TaskName $name

Write-Host "Registered and started scheduled task '$name'."
Write-Host "Triggers: at logon, and every 5 minutes thereafter."
