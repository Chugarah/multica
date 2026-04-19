<#
.SYNOPSIS
    Tail Multica container logs.

.DESCRIPTION
    Wraps `docker compose logs -f --tail N $Service`. No mutex (read-only).

.PARAMETER Service
    postgres | backend | frontend | cloudflared. Omit for all services.

.PARAMETER Tail
    Number of historical lines to show before tailing. Default 200.

.EXAMPLE
    .\scripts\windows\Logs-Multica.ps1
    .\scripts\windows\Logs-Multica.ps1 backend
    .\scripts\windows\Logs-Multica.ps1 cloudflared -Tail 1000
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$Service,
    [int]$Tail = 200
)

. "$PSScriptRoot\_common.ps1"

Assert-Docker
Assert-EnvFile

# $args is a PowerShell automatic variable; use a different name.
$composeArgs = @('logs', '-f', '--tail', $Tail)
if ($Service) { $composeArgs += $Service }

Invoke-Compose @composeArgs
