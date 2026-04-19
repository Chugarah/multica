# Shared helpers dot-sourced by every Multica PowerShell lifecycle script.
# Lives in scripts/windows/. All paths are derived from $PSScriptRoot so the
# scripts work whether invoked from the physical server path or via the
# \\192.168.1.162\Apps\Multica share (V:\Multica\... on the dev machine).

$ErrorActionPreference = 'Stop'

$script:RepoRoot     = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$script:ComposeFile  = Join-Path $RepoRoot 'docker-compose.prod.yml'
$script:EnvFile      = Join-Path $RepoRoot '.env.production'
$script:EnvExample   = Join-Path $RepoRoot '.env.production.example'
$script:BackupsDir   = Join-Path $RepoRoot 'backups'
$script:LogsDir      = Join-Path $RepoRoot 'logs'
$script:ProjectName  = 'multica-prod'

function Write-Info  { param([string]$Message) Write-Host "[multica] $Message" -ForegroundColor Cyan }
function Write-Ok    { param([string]$Message) Write-Host "[multica] $Message" -ForegroundColor Green }
function Write-Warn2 { param([string]$Message) Write-Host "[multica] $Message" -ForegroundColor Yellow }
function Write-Err   { param([string]$Message) Write-Host "[multica] $Message" -ForegroundColor Red }

function Assert-Docker {
    try { docker version --format '{{.Server.Version}}' | Out-Null }
    catch {
        Write-Err 'Docker is not reachable. Start Docker Desktop and re-run.'
        exit 1
    }
}

function Assert-EnvFile {
    if (-not (Test-Path $script:EnvFile)) {
        Write-Err ".env.production not found at $script:EnvFile"
        Write-Err 'Run Install-Multica.ps1 first (it seeds the file from the example).'
        exit 1
    }
}

# Wraps `docker compose ...` with the prod compose file + env file.
function Invoke-Compose {
    param([Parameter(ValueFromRemainingArguments)] $Args)
    & docker compose --project-name $script:ProjectName -f $script:ComposeFile --env-file $script:EnvFile @Args
    if ($LASTEXITCODE -ne 0) { throw "docker compose exited with code $LASTEXITCODE" }
}

# Single-instance mutex helper. Returns the mutex; the caller MUST dispose it
# (use try/finally). Prevents duplicate Start/Update/Backup runs that would
# fight over the same docker compose project.
function Acquire-Mutex {
    param([string]$Name = 'MulticaLifecycle-v1')
    $mutex = New-Object System.Threading.Mutex($false, "Local\$Name")
    if (-not $mutex.WaitOne([TimeSpan]::FromSeconds(2))) {
        Write-Err "Another Multica lifecycle script is already running ($Name). Aborting."
        $mutex.Dispose()
        exit 1
    }
    return $mutex
}

function Read-EnvValue {
    param([string]$Key)
    if (-not (Test-Path $script:EnvFile)) { return $null }
    $line = Get-Content $script:EnvFile | Where-Object { $_ -match "^\s*${Key}\s*=" } | Select-Object -First 1
    if (-not $line) { return $null }
    return ($line -replace "^\s*${Key}\s*=\s*", '').Trim('"').Trim("'")
}
