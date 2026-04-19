<#
.SYNOPSIS
    Build (if needed) and start the Multica production stack.

.DESCRIPTION
    Runs `docker compose up -d` against docker-compose.prod.yml. Builds images
    only when missing or stale (compose decides). Polls the backend /health
    endpoint inside the container until it returns ok or the timeout elapses.

.PARAMETER NoBuild
    Skip image build; only start containers from existing images.

.PARAMETER WaitSeconds
    Seconds to wait for backend to report healthy. Default 120.
#>

[CmdletBinding()]
param(
    [switch]$NoBuild,
    [int]$WaitSeconds = 120
)

. "$PSScriptRoot\_common.ps1"

Assert-Docker
Assert-EnvFile

$mutex = Acquire-Mutex
try {
    if (-not $NoBuild) {
        Write-Info 'Building images (cached layers reused).'
        Invoke-Compose build
    }

    Write-Info 'Starting containers in detached mode.'
    Invoke-Compose up -d

    Write-Info "Waiting up to $WaitSeconds s for backend to report healthy."
    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    do {
        Start-Sleep -Seconds 3
        $status = & docker inspect --format '{{.State.Health.Status}}' "${ProjectName}-backend-1" 2>$null
        if ($status -eq 'healthy') {
            Write-Ok 'Backend is healthy.'
            break
        }
        Write-Host '.' -NoNewline
    } while ((Get-Date) -lt $deadline)
    Write-Host ''
    if ($status -ne 'healthy') {
        Write-Warn2 "Backend did not report healthy within $WaitSeconds s. Last status: $status"
        Write-Warn2 'Check logs: .\scripts\windows\Logs-Multica.ps1 backend'
        exit 2
    }

    Write-Info 'Container status:'
    Invoke-Compose ps
}
finally {
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
