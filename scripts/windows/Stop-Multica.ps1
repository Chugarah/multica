<#
.SYNOPSIS
    Stop the Multica production stack.

.DESCRIPTION
    Runs `docker compose down`. By default preserves the pgdata and
    backend_uploads volumes. Use -Purge to also remove volumes (DESTRUCTIVE —
    drops the database).

.PARAMETER Purge
    Also remove named volumes. Destroys the database. Requires -Confirm $true.

.EXAMPLE
    .\scripts\windows\Stop-Multica.ps1
    .\scripts\windows\Stop-Multica.ps1 -Purge -Confirm $true
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$Purge
)

. "$PSScriptRoot\_common.ps1"

Assert-Docker
Assert-EnvFile

if ($Purge) {
    if (-not $PSCmdlet.ShouldProcess('pgdata + backend_uploads volumes', 'destroy')) {
        Write-Warn2 'Purge cancelled.'
        exit 0
    }
    Write-Warn2 'Purging volumes. Database and uploads will be destroyed.'
    Invoke-Compose down -v
} else {
    Invoke-Compose down
}

Write-Ok 'Stack stopped.'
