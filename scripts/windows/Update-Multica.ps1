<#
.SYNOPSIS
    Pull the latest Multica code, rebuild images, and restart the stack.

.DESCRIPTION
    Workflow:
      1. Take a pre-update DB snapshot (calls Backup-Multica.ps1).
      2. git fetch and checkout -Ref (default origin/main).
      3. docker compose build.
      4. docker compose up -d (migrations run automatically in the backend
         entrypoint before the server starts).
      5. Poll /health until ready.

    If any step fails, the script stops and prints how to roll back from the
    snapshot.

.PARAMETER Ref
    Git ref to check out. Default: origin/main.

.PARAMETER SkipBackup
    Skip the pre-update snapshot. Dangerous; use only if the DB is trivial.
#>

[CmdletBinding()]
param(
    [string]$Ref = 'origin/main',
    [switch]$SkipBackup
)

. "$PSScriptRoot\_common.ps1"

Assert-Docker
Assert-EnvFile

$mutex = Acquire-Mutex -Name 'MulticaUpdate-v1'
try {
    # 1. Pre-update backup
    if (-not $SkipBackup) {
        Write-Info 'Taking pre-update DB snapshot.'
        & "$PSScriptRoot\Backup-Multica.ps1"
        if ($LASTEXITCODE -ne 0) {
            Write-Err 'Pre-update backup failed. Aborting to avoid updating on top of an un-backed-up DB.'
            exit 2
        }
    } else {
        Write-Warn2 'Skipping pre-update backup (-SkipBackup).'
    }

    # 2. Git pull
    if (-not (Test-Path (Join-Path $RepoRoot '.git'))) {
        Write-Err 'No .git at repo root. Cannot update via git. Aborting.'
        exit 1
    }

    Push-Location $RepoRoot
    try {
        Write-Info 'git fetch --prune'
        git fetch --prune
        if ($LASTEXITCODE -ne 0) { throw "git fetch failed" }

        Write-Info "git checkout $Ref"
        git checkout $Ref
        if ($LASTEXITCODE -ne 0) { throw "git checkout $Ref failed" }
    }
    finally {
        Pop-Location
    }

    # 3 + 4. Rebuild and restart
    Write-Info 'docker compose build'
    Invoke-Compose build

    Write-Info 'docker compose up -d'
    Invoke-Compose up -d

    # 5. Wait for health
    & "$PSScriptRoot\Start-Multica.ps1" -NoBuild -WaitSeconds 180
}
finally {
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}

Write-Ok 'Update complete.'
