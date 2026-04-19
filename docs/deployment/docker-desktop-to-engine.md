# Docker Desktop → native Docker Engine cutover

When and how to stop using Docker Desktop on the Windows Server and switch to a real server-grade container runtime. Nothing in `docker-compose.prod.yml` or the PowerShell scripts needs to change — they both talk to the Docker CLI. Only the runtime underneath changes.

## When to cut over

Considerations:
- **Licensing** — Docker Desktop is free for personal use and small business (≤ 250 employees, ≤ $10M revenue). If you grow past that or start running this commercially, read the current subscription terms.
- **Startup dependency** — Docker Desktop on Windows Server 2019 has been rough in practice (Hyper-V + WSL2 interactions). Once the server is genuinely always-on and hosting real workloads, you want the stack to come up without a user logged in. Docker Desktop requires an interactive session for some features.
- **Resource overhead** — the Docker Desktop VM pays ~800 MB of RAM in overhead even with nothing running. On a 7 GB host that matters.

## Option A — native Docker Engine on Windows Server (Mirantis)

Microsoft's Windows Server container story now routes through Mirantis Container Runtime (formerly Docker EE). **Still Windows-native** — no Linux VM required. This is the closest "drop-in" replacement.

1. Uninstall Docker Desktop (`appwiz.cpl` → Docker Desktop → Uninstall).
2. Reboot.
3. Install Mirantis Container Runtime per their docs (free tier for evaluation; pricing tiers above that). It runs as a Windows service, no WSL2 required.
4. Re-run `.\scripts\windows\Install-Multica.ps1` + `Start-Multica.ps1`. Everything else is unchanged.

Caveat: Windows Server 2019 Linux containers require LCOW or WSL2; check Mirantis docs for current story.

## Option B — migrate to a Linux host (recommended long-term)

The app is entirely Linux containers. Running them on a Linux host removes Windows from the equation and is the cleanest production footprint.

Upgrade path:
1. Stand up Ubuntu LTS (physical, VM, or your existing Hetzner-style VPS pattern).
2. Install Docker Engine + Compose plugin: https://docs.docker.com/engine/install/ubuntu/.
3. Copy `.env.production` and the latest `multica-*.dump` to the new host.
4. `git clone` the repo there.
5. `docker compose -f docker-compose.prod.yml --env-file .env.production up -d`.
6. Restore the DB: use the same `Restore-Multica.ps1` logic but invoked as bash (or just run `pg_restore` via `docker compose exec`).
7. Flip the Cloudflare tunnel to the new host — either move the tunnel token (simplest — just paste into new host's `.env.production`) or create a fresh tunnel and update the DNS.

The PowerShell scripts don't run on Linux. You lose the `.ps1` lifecycle tooling; write equivalent `bash` scripts (it's a ~50 LOC exercise — the scripts are thin wrappers over `docker compose`).

## Option C — keep Docker Desktop

Valid. Many small deployments run Docker Desktop happily for years. Tradeoffs:
- Reboot the server → Docker Desktop must start → your `Multica-AutoStart` Scheduled Task waits for the Docker daemon to be reachable (the `Assert-Docker` check). Works, but adds ~60 s to cold boot.
- License: review periodically.

## Migrating persistent data

Docker volumes (`pgdata`, `backend_uploads`) live in Docker's internal storage — not portable across runtimes. Always use the backup/restore flow, not volume copy:

```powershell
# On old host:
.\scripts\windows\Backup-Multica.ps1

# Copy the dump to new host, then:
# On new host:
.\scripts\windows\Restore-Multica.ps1 -File multica-<stamp>.dump -Confirm $true
```

For `backend_uploads`: if small, `docker compose cp backend:/app/data/uploads ./uploads-export` on old host, reverse on new. For large upload volumes, configure S3 in `.env.production` *before* the cutover — then the volume is empty and migration is trivial.
