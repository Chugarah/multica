<#
.SYNOPSIS
    Restore Multica Postgres from a .dump file produced by Backup-Multica.ps1.

.DESCRIPTION
    Destructive. Stops the backend (so no connections hold open), runs
    pg_restore --clean --if-exists into the live database, then restarts the
    backend. Requires explicit -Confirm $true to proceed.

.PARAMETER File
    Path to the .dump file. Can be relative (resolved against backups/) or absolute.

.EXAMPLE
    .\scripts\windows\Restore-Multica.ps1 -File multica-20260420-0300.dump -Confirm $true
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string]$File
)

. "$PSScriptRoot\_common.ps1"

Assert-Docker
Assert-EnvFile

$dumpPath = if ([System.IO.Path]::IsPathRooted($File)) { $File } else { Join-Path $BackupsDir $File }
if (-not (Test-Path $dumpPath)) {
    Write-Err "Dump file not found: $dumpPath"
    exit 1
}

if (-not $PSCmdlet.ShouldProcess("database from $dumpPath", 'restore (destructive)')) {
    Write-Warn2 'Restore cancelled.'
    exit 0
}

$pgUser = Read-EnvValue 'POSTGRES_USER'
$pgDb   = Read-EnvValue 'POSTGRES_DB'

$mutex = Acquire-Mutex -Name 'MulticaRestore-v1'
try {
    Write-Info 'Stopping backend so it releases DB connections.'
    Invoke-Compose stop backend

    # Binary-safe across PS 5.1 and PS 7: copy the dump into the postgres
    # container, run pg_restore against the in-container path, then clean up.
    # Avoids the Get-Content -Encoding Byte / -AsByteStream shell-version split.
    $containerPath = '/tmp/multica-restore.dump'
    Write-Info "Copying dump into postgres container at $containerPath"
    Invoke-Compose cp $dumpPath "postgres:$containerPath"

    Write-Info 'Running pg_restore.'
    Invoke-Compose exec -T postgres pg_restore --clean --if-exists -U $pgUser -d $pgDb $containerPath

    $restoreExit = $LASTEXITCODE

    # Clean up the temp file regardless of outcome.
    Invoke-Compose exec -T postgres rm -f $containerPath

    if ($restoreExit -ne 0) {
        Write-Err "pg_restore reported errors (exit $restoreExit). Inspect output and decide whether to re-try."
    } else {
        Write-Ok 'Restore complete.'
    }

    Write-Info 'Restarting backend.'
    Invoke-Compose start backend
}
finally {
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
