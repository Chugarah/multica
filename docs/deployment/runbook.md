# Runbook — day-to-day Multica ops

All commands run from the repo root on the Windows host (`D:\Apps\Multica\` or wherever your `Apps` share backs) in an elevated PowerShell. Scripts also work over the `V:\Multica\` SMB mapping from the dev machine — they're `$PSScriptRoot`-relative.

## Start / stop

```powershell
.\scripts\windows\Start-Multica.ps1            # builds if needed, then `up -d`, waits for /health
.\scripts\windows\Stop-Multica.ps1             # `down` (volumes preserved)
.\scripts\windows\Stop-Multica.ps1 -Purge -Confirm $true   # destroys DB + uploads; needs confirmation
```

## Logs

```powershell
.\scripts\windows\Logs-Multica.ps1                 # all services, last 200 lines, tailing
.\scripts\windows\Logs-Multica.ps1 backend         # one service
.\scripts\windows\Logs-Multica.ps1 cloudflared -Tail 1000
```

Tail with `Ctrl+C` to exit.

## Update

```powershell
.\scripts\windows\Update-Multica.ps1               # pre-update DB snapshot, git pull origin/main, rebuild, restart
.\scripts\windows\Update-Multica.ps1 -Ref v0.3.0   # pin to a tag
.\scripts\windows\Update-Multica.ps1 -SkipBackup   # only for non-DB changes; dangerous
```

Migrations run automatically in the backend's entrypoint before `./server` starts.

## Backup

```powershell
.\scripts\windows\Backup-Multica.ps1               # dump → backups\multica-yyyyMMdd-HHmm.dump, prune > 14d
.\scripts\windows\Backup-Multica.ps1 -RetentionDays 30
```

The scheduled task `Multica-NightlyBackup` runs this at 03:00. Check via:

```powershell
Get-ScheduledTask -TaskName Multica-NightlyBackup | Get-ScheduledTaskInfo
Get-ChildItem .\backups\
```

## Restore

```powershell
.\scripts\windows\Restore-Multica.ps1 -File multica-20260420-0300.dump -Confirm $true
```

Stops the backend, pipes the dump into `pg_restore --clean --if-exists`, restarts the backend. For disaster recovery see [`dr.md`](dr.md).

## Health checks

```powershell
docker compose -f docker-compose.prod.yml ps
docker stats --no-stream
```

Healthy steady-state:
- all four containers `running`, backend `(healthy)`, postgres `(healthy)`, frontend `(healthy)`
- total memory usage around ~1 GB under no load, < 1.5 GB under light use
- `netstat -an | findstr LISTEN` does NOT show 3000 / 8080 / 5432 bound externally

## Scheduled tasks

```powershell
Get-ScheduledTask -TaskName Multica-*
Start-ScheduledTask -TaskName Multica-AutoStart       # manual trigger
Start-ScheduledTask -TaskName Multica-NightlyBackup
Unregister-ScheduledTask -TaskName Multica-* -Confirm:$false   # to re-run Register-Tasks.ps1 from scratch
```

## Rotating secrets

**JWT_SECRET** — edit `.env.production`, then `Stop-Multica.ps1 && Start-Multica.ps1`. All logged-in users are signed out.

**POSTGRES_PASSWORD** — harder: you need to update both the env file AND the live Postgres user. Easiest is `docker compose exec postgres psql -U <user> -c "ALTER USER <user> WITH PASSWORD '<new>';"`, then update `.env.production`, then restart.

**CLOUDFLARE_TUNNEL_TOKEN** — regenerate in the Cloudflare dashboard (Networks → Tunnels → multica-home → Configure → refresh token), paste new value into `.env.production`, `Stop-Multica.ps1 && Start-Multica.ps1`. Public URLs stay valid (tunnel ID is unchanged).

## Common troubleshooting

| Symptom | First thing to check |
|---|---|
| `multica.chugarah.com` returns `502` | `Logs-Multica.ps1 frontend` — Next.js crash? Then `backend` — is `/health` returning ok? |
| `multica.chugarah.com` returns Cloudflare origin-unreachable | `docker compose ps` — is `cloudflared` running? `Logs-Multica.ps1 cloudflared` |
| `rdp.multica.chugarah.com` times out | RDP service down on host. `Get-Service TermService` must be `Running`. |
| Backup task reports "Last Run Result: 0x1" | Task ran as SYSTEM; SYSTEM can reach Docker Desktop only if Docker Desktop's engine is running. Confirm Docker Desktop starts at boot. |
| `Update-Multica.ps1` fails at `git checkout` | Local commits on the server — `git status` at the repo. Usually the fix is `git stash` or resetting. |
| Containers exit with `JWT_SECRET must be set` | `.env.production` missing or the key is blank. Re-run `Install-Multica.ps1`. |
