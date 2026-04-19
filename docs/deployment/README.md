# Multica Production Deployment

This folder documents the production deployment of Multica on a home Windows Server 2019 host (`192.168.1.162`), exposed to the Internet via Cloudflare Tunnel at `multica.chugarah.com`, with browser-based RDP admin at `rdp.multica.chugarah.com`. AirVPN Eddie continues to run on the host; no Tailscale.

## Architecture at a glance

```
Internet
  └─ Cloudflare (Access SSO, 3 hostnames)
       └─ cloudflared container (named tunnel "multica-home")
            ├─ multica.chugarah.com → frontend:3000  (Next.js)
            │                        └─ backend:8080 (Go, /api, /ws)
            │                             └─ postgres:5432 (pgvector)
            ├─ rdp.multica.chugarah.com → host.docker.internal:3389
            └─ ssh.multica.chugarah.com → host.docker.internal:22 (optional)
```

- No host ports bound for postgres / backend / frontend — only `cloudflared` egresses.
- Migrations auto-run on backend startup.
- Nightly `pg_dump` to `backups/` with 14-day retention.
- Scheduled Task `Multica-AutoStart` brings the stack up at boot.

## Docs index

| File | Purpose |
|---|---|
| [windows-server-setup.md](windows-server-setup.md) | One-time Windows host prep: WSL2, Docker Desktop, RDP, optional OpenSSH. |
| [cloudflare-tunnel.md](cloudflare-tunnel.md) | Create the `multica-home` tunnel, its three ingress rules, and three Access apps. |
| [admin-access.md](admin-access.md) | How to RDP/SSH into the server via Cloudflare Access. |
| [eddie-coexistence.md](eddie-coexistence.md) | Why Tailscale was rejected; how `cloudflared` coexists with AirVPN Eddie. |
| [runbook.md](runbook.md) | Day-to-day ops: start / stop / update / logs / backup / restore. |
| [dr.md](dr.md) | Disaster recovery when the host is lost. |
| [docker-desktop-to-engine.md](docker-desktop-to-engine.md) | Future cutover from Docker Desktop to native Docker Engine. |
| [assets/wslconfig.sample](assets/wslconfig.sample) | Drop-in `%USERPROFILE%\.wslconfig` to cap WSL2 memory on a 7 GB host. |

## Related files in the repo

- `docker-compose.prod.yml` — production stack definition.
- `.env.production.example` — env template (copy to `.env.production` on the server).
- `Dockerfile`, `Dockerfile.web` — backend and frontend images (with healthchecks, non-root user on backend).
- `scripts/windows/*.ps1` — lifecycle scripts invoked on the host.
- `scripts/windows/deploy.cmd` — self-elevating wrapper for first-time setup.
