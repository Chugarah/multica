# Disaster recovery — the box is gone

If the Windows Server dies (hardware failure, drive loss, ransomware), the recovery path assumes you have **three things offsite**:

1. The latest `multica-*.dump` from `backups\`.
2. The `.env.production` file (secrets live only here — not in git).
3. The Cloudflare account (tunnel config + Access policies survive independently).

If you have all three, full recovery time is ~30 minutes on a new host.

## Offsite strategy

On the live host, schedule a one-line copy of `backups\` and `.env.production` to wherever you keep cold storage (Google Drive sync, an external NAS, `rclone` to S3, etc.). Options:

- Simplest: copy `backups\` into the `Apps` SMB share onto a second drive at home (a snapshot-aware NAS is ideal).
- Cloud: `rclone sync D:\Apps\Multica\backups remote:multica-backups` on a daily scheduled task.
- Both: redundancy is cheap at this data size.

**Do not** commit `.env.production` to any git repo. Store a copy in a password manager (1Password/Bitwarden secure note) — only the secrets, not the whole file, if you prefer.

## Step-by-step recovery

### 1. Stand up a new Windows host

Any Windows box with Docker Desktop + WSL2 works. Follow [`windows-server-setup.md`](windows-server-setup.md) steps 1–5.

### 2. Re-clone the repo

```powershell
cd D:\Apps       # or wherever
git clone https://github.com/<your-fork>/multica.git Multica
cd Multica
```

### 3. Restore `.env.production`

Copy the saved file into the repo root. Do NOT rerun `Install-Multica.ps1` first — if it finds no `.env.production`, it seeds a blank one which would then merge-append and make a mess. Instead:

```powershell
Copy-Item path\to\saved\.env.production .\.env.production
.\scripts\windows\Install-Multica.ps1   # now harmless — .env exists, only verifies
```

### 4. Bring up the empty stack

```powershell
.\scripts\windows\Start-Multica.ps1
```

At this point the stack runs with an empty database. Schema migrations have already run on backend startup. The frontend serves the login page, but no users or workspaces exist yet.

### 5. Restore the database

```powershell
Copy-Item path\to\saved\multica-*.dump .\backups\
.\scripts\windows\Restore-Multica.ps1 -File multica-<stamp>.dump -Confirm $true
```

This:
- Stops the backend (releases connections).
- Streams the dump into `pg_restore --clean --if-exists`.
- Restarts the backend.

After the restart, `Logs-Multica.ps1 backend` should show no errors, and visiting `https://multica.chugarah.com` should land on a login page that accepts your existing accounts.

### 6. Reconnect the tunnel

If you recreated the Windows host on a new network but kept the same `CLOUDFLARE_TUNNEL_TOKEN`, the `cloudflared` sidecar will re-register automatically. If you had to generate a new tunnel token (because the old was lost), update the token in `.env.production`, recreate the three Public Hostname rules in the Cloudflare dashboard, and re-issue `Stop-Multica.ps1` + `Start-Multica.ps1`.

### 7. Re-register Scheduled Tasks

```powershell
.\scripts\windows\Register-Tasks.ps1
```

### 8. Verify

Run through `runbook.md`'s **Health checks** section. Smoke-test the app: log in, open an issue, reload, confirm persistence.

## RTO / RPO targets

- **RTO**: ~30 min on a prepared host with Docker Desktop already installed, ~2 h from scratch.
- **RPO**: ≤ 24 h with nightly backups. Drop the backup task to `Hourly` if you want tighter.

## What you lose vs. what survives

| Asset | Where it lives | Survives host loss? |
|---|---|---|
| Database content | `pgdata` Docker volume | ❌ Need `.dump` from backup |
| Uploaded files | `backend_uploads` volume (or S3 if configured) | ❌ (local) / ✅ (S3) |
| Source code | git | ✅ |
| Tunnel config + ingress rules | Cloudflare dashboard | ✅ |
| Access policies | Cloudflare dashboard | ✅ |
| `.env.production` secrets | Only the server | ❌ unless you back them up separately |

If the uploads volume losing is unacceptable, configure S3 in `.env.production` — backend will use CloudFront signed URLs instead of the local volume.
