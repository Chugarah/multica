# Local prod-stack dry run

Smoke-test `docker-compose.prod.yml` on your dev machine **before** shipping to the Windows Server. Catches Dockerfile regressions, env-var contract changes, healthcheck tuning issues, and migration breaks locally — where iteration is fast — instead of on the server where the Cloudflare Tunnel adds another layer to debug.

## When to run this

- Before the very first production deploy (right now, before touching `192.168.1.162`).
- After any change to `Dockerfile`, `Dockerfile.web`, `docker-compose.prod.yml`, or `.env.production.example`.
- Before tagging a production release.

## What's under test — and what isn't

| Component | Dry-run behavior | Why |
|---|---|---|
| postgres | ✅ Full run | Regular Postgres image; nothing cloud-specific. |
| backend | ✅ Full run | Migrations execute against the local volume; `/health` reachable. |
| frontend | ✅ Full run | Next.js standalone boots; Node-based healthcheck passes. |
| cloudflared | ❌ Fails to auth | Fake tunnel token can't authenticate with Cloudflare — expected. Other containers don't depend on it. |

This is a deliberate choice: the first three prove the *app* works end-to-end. cloudflared is just a TLS pipe — if postgres + backend + frontend are healthy on localhost, the server rollout is about networking, not code.

## Prereqs

1. Docker Desktop running (or Docker Engine on Linux).
2. WSL2 memory cap ≥ 3 GB (the stack itself uses ~1 GB; headroom helps).
3. Ports `3000`, `8080` free on `localhost`:
   ```powershell
   make selfhost-stop      # if the selfhost quickstart was running
   Get-NetTCPConnection -LocalPort 3000,8080 -State Listen 2>$null
   ```

## The port-exposure problem

Production compose binds **no** host ports — `cloudflared` is the only surface. For the dry run we need browser access to validate the app, so we layer a tiny override file on top that only exists during testing.

Create `docker-compose.prod.override.yml` at the repo root:

```yaml
# TEST-ONLY: publishes frontend and backend to localhost so we can hit them
# from a browser. Never ship this to the server; never commit it.
services:
  frontend:
    ports:
      - "3000:3000"
  backend:
    ports:
      - "8080:8080"
```

This filename is gitignored (see `.gitignore`), so it stays on your machine only.

## Setup

```powershell
# 1. Clean env file with dummies-but-valid values
Copy-Item .env.production.example .env.production
notepad .env.production
#   JWT_SECRET=replace-with-openssl-rand-base64-48
#   POSTGRES_PASSWORD=local-test-pw
#   CLOUDFLARE_TUNNEL_TOKEN=fake-token-will-fail-that-is-fine
#   FRONTEND_ORIGIN=http://localhost:3000
#   MULTICA_APP_URL=http://localhost:3000
#   ALLOWED_ORIGINS=http://localhost:3000
#   CORS_ALLOWED_ORIGINS=http://localhost:3000
#   COOKIE_DOMAIN=   (leave blank for localhost)

# 2. Author docker-compose.prod.override.yml from the YAML above (10 lines).

# 3. Bring up the stack (manual compose — bypassing Start-Multica.ps1 so we
#    can layer the override file)
docker compose -f docker-compose.prod.yml -f docker-compose.prod.override.yml `
               --env-file .env.production up -d --build
```

## Verification checklist

Run through these in order. Each one teaches you something specific about what's working.

**Containers running and healthy:**

```powershell
docker compose -f docker-compose.prod.yml -f docker-compose.prod.override.yml ps
# Expect: 4 services up. backend + postgres + frontend (healthy). cloudflared restarting (fine).
```

**Backend `/health` reachable:**

```powershell
curl http://localhost:8080/health
# Expect: {"status":"ok"}
```

**Migrations completed:**

```powershell
docker compose logs backend | Select-String -Pattern "migration|Running database"
# Expect: "Running database migrations..." then "Starting server..."
```

**Frontend serves the login page:**

Open `http://localhost:3000` in a browser. Expect Multica's login screen.

**Full app smoke test:**

1. On the login page, enter any email.
2. Use the master code `888888` (works when `RESEND_API_KEY` is empty).
3. Create a workspace. Create an issue. Reload the page — data should persist.
4. Check that uploads work (drop a file into an issue comment).

**Resource budget:**

```powershell
docker stats --no-stream
# Expect: total memory < 1.5 GB steady-state. Each container well under its mem_limit.
```

**Healthcheck tuning:**

Watch the containers come up — if `frontend` or `backend` cycle between `starting` and `healthy` during boot, the healthcheck `start_period` may be too short. Typical first boot after a clean build:
- postgres `healthy` in ~10 s
- backend `healthy` in ~15 s (after migrations)
- frontend `healthy` in ~20 s (Next.js cold start)

If you see flapping, that's the signal to bump `start_period` in `docker-compose.prod.yml`.

**cloudflared — expected failure:**

```powershell
docker compose logs cloudflared | Select-Object -Last 20
# Expect: errors like "failed to create tunnel" or "invalid token". That's fine.
# The container restarts forever under restart: unless-stopped — harmless.
```

**Backup + restore drill** (tests the PowerShell scripts end-to-end):

```powershell
.\scripts\windows\Backup-Multica.ps1
Get-ChildItem .\backups\
# Expect: multica-<stamp>.dump exists and is non-zero.

# Prove restore works. First break things:
.\scripts\windows\Stop-Multica.ps1 -Purge -Confirm $true    # destroys the DB
.\scripts\windows\Start-Multica.ps1                          # empty DB, migrations re-run
# Visit http://localhost:3000 — you should see no workspaces (fresh DB).
.\scripts\windows\Restore-Multica.ps1 -File multica-<stamp>.dump -Confirm $true
# Visit again — your workspace + issue should be back.
```

## Cleanup

```powershell
# Stop everything and destroy local state
docker compose -f docker-compose.prod.yml -f docker-compose.prod.override.yml `
               --env-file .env.production down -v

# Remove test-only artifacts (keep the .example file)
Remove-Item .env.production
Remove-Item docker-compose.prod.override.yml
```

## If something fails

| Symptom | Likely cause |
|---|---|
| Compose refuses to start with `JWT_SECRET must be set` | `.env.production` missing the key or it's blank. The `:?` guards are doing their job. |
| `frontend` healthcheck flaps between starting/unhealthy | Cold-boot of Next.js exceeded `start_period`. Bump to `30s` in `docker-compose.prod.yml`. |
| `backend` fails with `failed to connect to postgres` | postgres wasn't fully up; check `depends_on: service_healthy` on the backend is intact. |
| Login page never loads | Look at frontend logs: `docker compose logs frontend`. Usually a missing `NEXT_PUBLIC_*` var at build time. |
| Container runs as root (`docker exec whoami` returns `root`) | The `USER multica` directive in `Dockerfile` was reverted or the image wasn't rebuilt. `--build` flag on `up` fixes the latter. |
| Uploads fail with permission denied inside container | `/app/data/uploads` isn't writable by the `multica` user. Should be chowned in the Dockerfile runtime stage — verify the edit landed. |

## After a successful dry run

- You've proved the prod stack runs end-to-end.
- You know roughly what memory it uses.
- You've exercised the backup/restore flow.
- The only remaining unknowns on the real server are: Cloudflare Tunnel token validity, Access policy binding, and RDP reachability. Those are addressed in [`cloudflare-tunnel.md`](cloudflare-tunnel.md) and [`admin-access.md`](admin-access.md).

Move to [`windows-server-setup.md`](windows-server-setup.md) for the server-side provisioning.
