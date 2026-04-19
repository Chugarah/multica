<#
.SYNOPSIS
    Dump the Multica Postgres database to backups/.

.DESCRIPTION
    Runs pg_dump in custom format (-Fc) via docker compose exec and writes
    the dump to backups/multica-yyyyMMdd-HHmm.dump (next to the compose file,
    not a hardcoded drive). Prunes dumps older than -RetentionDays (default 14).

    Exits non-zero if the database container is not running or if pg_dump fails.

.PARAMETER RetentionDays
    Delete dumps older than this many days. Default 14.
#>

[CmdletBinding()]
param(
    [int]$RetentionDays = 14
)

. "$PSScriptRoot\_common.ps1"

Assert-Docker
Assert-EnvFile

if (-not (Test-Path $BackupsDir)) {
    New-Item -ItemType Directory -Path $BackupsDir | Out-Null
}

$mutex = Acquire-Mutex -Name 'MulticaBackup-v1'
try {
    $pgUser = Read-EnvValue 'POSTGRES_USER'
    $pgDb   = Read-EnvValue 'POSTGRES_DB'
    if (-not $pgUser -or -not $pgDb) {
        Write-Err 'POSTGRES_USER or POSTGRES_DB missing from .env.production. Cannot back up.'
        exit 1
    }

    $stamp  = Get-Date -Format 'yyyyMMdd-HHmm'
    $outFile = Join-Path $BackupsDir "multica-$stamp.dump"

    Write-Info "Dumping $pgDb as $pgUser to $outFile"

    # -T disables TTY; binary pg_dump output streams to the file.
    & docker compose --project-name $ProjectName -f $ComposeFile --env-file $EnvFile `
        exec -T postgres pg_dump -Fc -U $pgUser $pgDb > $outFile

    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $outFile) -or (Get-Item $outFile).Length -eq 0) {
        Write-Err "pg_dump failed or produced an empty file. Removing $outFile."
        if (Test-Path $outFile) { Remove-Item $outFile -Force }
        exit 2
    }

    $size = [math]::Round((Get-Item $outFile).Length / 1MB, 2)
    Write-Ok "Backup OK: $outFile ($size MB)"

    # Retention prune
    $cutoff = (Get-Date).AddDays(-$RetentionDays)
    $old = Get-ChildItem -Path $BackupsDir -Filter 'multica-*.dump' |
           Where-Object { $_.LastWriteTime -lt $cutoff }
    foreach ($f in $old) {
        Remove-Item $f.FullName -Force
        Write-Info "Pruned old dump: $($f.Name)"
    }
}
finally {
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
