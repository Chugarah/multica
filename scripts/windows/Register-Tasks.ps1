<#
.SYNOPSIS
    Register Windows Scheduled Tasks for Multica auto-start and nightly backup.

.DESCRIPTION
    Creates (or replaces) two tasks owned by the SYSTEM account:
      Multica-AutoStart    — runs Start-Multica.ps1 at boot.
      Multica-NightlyBackup — runs Backup-Multica.ps1 daily at 03:00.

    Both tasks reference the PowerShell scripts by absolute path, so moving
    the install folder requires re-running this script.

    Requires elevated PowerShell. The deploy.cmd wrapper handles UAC.

.PARAMETER BackupTime
    Daily time to run the backup task (24h, HH:mm). Default 03:00.
#>

[CmdletBinding()]
param(
    [string]$BackupTime = '03:00'
)

. "$PSScriptRoot\_common.ps1"

# Require elevation — Scheduled Tasks running as SYSTEM need admin to register.
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Write-Err 'Register-Tasks.ps1 must run elevated. Launch via deploy.cmd or an Admin PowerShell.'
    exit 1
}

$pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $pwsh) { $pwsh = (Get-Command powershell).Source }

$startScript  = Join-Path $PSScriptRoot 'Start-Multica.ps1'
$backupScript = Join-Path $PSScriptRoot 'Backup-Multica.ps1'

function Register-OneTask {
    param(
        [string]$Name,
        [string]$ScriptPath,
        [Microsoft.Management.Infrastructure.CimInstance[]]$Triggers
    )
    $action = New-ScheduledTaskAction -Execute $pwsh `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                                              -StartWhenAvailable -MultipleInstances IgnoreNew `
                                              -ExecutionTimeLimit (New-TimeSpan -Hours 1)

    if (Get-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $Name -Confirm:$false
    }
    Register-ScheduledTask -TaskName $Name -Action $action -Trigger $Triggers `
        -Principal $principal -Settings $settings | Out-Null
    Write-Ok "Registered task: $Name"
}

Register-OneTask -Name 'Multica-AutoStart' -ScriptPath $startScript `
    -Triggers (New-ScheduledTaskTrigger -AtStartup)

Register-OneTask -Name 'Multica-NightlyBackup' -ScriptPath $backupScript `
    -Triggers (New-ScheduledTaskTrigger -Daily -At $BackupTime)

Write-Ok 'Scheduled tasks installed.'
Write-Info 'Inspect with: Get-ScheduledTask -TaskName Multica-*'
