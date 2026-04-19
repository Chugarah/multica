<#
.SYNOPSIS
    First-time / re-run setup for Multica production on a Windows host.

.DESCRIPTION
    Verifies prerequisites, creates required folders, seeds .env.production
    from the example template (preserves existing values, appends only missing
    keys on re-run), and prompts the operator to fill in secrets. Idempotent.
    Does NOT start the stack — run Start-Multica.ps1 next.

.EXAMPLE
    .\scripts\windows\Install-Multica.ps1
#>

[CmdletBinding()]
param()

. "$PSScriptRoot\_common.ps1"

Write-Info "Repo root: $RepoRoot"

# --- 1. Verify prerequisites -------------------------------------------------
Assert-Docker
Write-Ok "Docker reachable: $(docker version --format '{{.Server.Version}}')"

if (-not (Test-Path (Join-Path $RepoRoot '.git'))) {
    Write-Warn2 'No .git directory at the repo root. Update-Multica.ps1 will not work without a clone.'
}

# --- 2. Create runtime folders ----------------------------------------------
foreach ($dir in @($BackupsDir, $LogsDir)) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir | Out-Null
        Write-Ok "Created $dir"
    }
}

# --- 3. Seed .env.production -------------------------------------------------
if (-not (Test-Path $EnvExample)) {
    Write-Err ".env.production.example missing at $EnvExample. Aborting."
    exit 1
}

if (-not (Test-Path $EnvFile)) {
    Copy-Item $EnvExample $EnvFile
    Write-Ok "Created $EnvFile from template."
} else {
    # Append any keys present in the template but missing from the live file.
    # Preserves operator-set values; never overwrites.
    $existing = Get-Content $EnvFile | ForEach-Object {
        if ($_ -match '^\s*([A-Z_][A-Z0-9_]*)\s*=') { $matches[1] }
    }
    $appended = @()
    Get-Content $EnvExample | ForEach-Object {
        if ($_ -match '^\s*([A-Z_][A-Z0-9_]*)\s*=') {
            if ($existing -notcontains $matches[1]) {
                Add-Content -Path $EnvFile -Value $_
                $appended += $matches[1]
            }
        }
    }
    if ($appended.Count -gt 0) {
        Write-Ok "Appended new keys to .env.production: $($appended -join ', ')"
    } else {
        Write-Info '.env.production is up to date with the template.'
    }
}

# --- 4. Sanity-check required secrets ---------------------------------------
$required = @('JWT_SECRET','POSTGRES_PASSWORD','CLOUDFLARE_TUNNEL_TOKEN','FRONTEND_ORIGIN','MULTICA_APP_URL','ALLOWED_ORIGINS','CORS_ALLOWED_ORIGINS')
$missing = @()
foreach ($key in $required) {
    $val = Read-EnvValue $key
    if ([string]::IsNullOrWhiteSpace($val)) { $missing += $key }
}

if ($missing.Count -gt 0) {
    Write-Warn2 'The following required values are still empty in .env.production:'
    foreach ($k in $missing) { Write-Host "    - $k" -ForegroundColor Yellow }
    Write-Host ''
    Write-Info 'Opening .env.production in notepad for editing. Save and close to continue.'
    Start-Process notepad.exe -ArgumentList $EnvFile -Wait

    # Re-check after editing
    $stillMissing = @()
    foreach ($key in $required) {
        $val = Read-EnvValue $key
        if ([string]::IsNullOrWhiteSpace($val)) { $stillMissing += $key }
    }
    if ($stillMissing.Count -gt 0) {
        Write-Err "Still missing values: $($stillMissing -join ', '). Re-run Install-Multica.ps1 when ready."
        exit 1
    }
    Write-Ok 'All required values present.'
} else {
    Write-Ok 'All required values present in .env.production.'
}

Write-Host ''
Write-Ok 'Install complete. Next steps:'
Write-Host '    1. .\scripts\windows\Start-Multica.ps1            # bring the stack up'
Write-Host '    2. .\scripts\windows\Register-Tasks.ps1           # auto-start on boot + nightly backup'
Write-Host '    3. Verify https://multica.chugarah.com is reachable.'
