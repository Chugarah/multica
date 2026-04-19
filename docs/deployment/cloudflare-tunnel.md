# Cloudflare Tunnel — `multica-home`

A single named tunnel fronts all three of Multica's surfaces: public app, browser RDP, and (optional) SSH. Ingress rules and Access policies live in the Cloudflare dashboard. The only thing the server needs is the tunnel **token**, pasted into `.env.production`.

## 1. Create the tunnel

1. Log in to https://one.dash.cloudflare.com.
2. **Networks → Tunnels → Create a tunnel**.
3. Connector type: **Cloudflared**.
4. Name: `multica-home`. Click **Save tunnel**.
5. On the next screen, **copy the long token string after `--token`**. This is `CLOUDFLARE_TUNNEL_TOKEN`. Do not copy the full `cloudflared service install` command — only the token.
6. Skip the "Install and run a connector" instructions — the sidecar container runs it for you.
7. Click **Next** to reach the **Public Hostnames** page.

## 2. Add three public hostname rules

Still inside the `multica-home` tunnel, **Public Hostnames** tab:

| # | Subdomain | Domain | Type | URL |
|---|---|---|---|---|
| 1 | `multica` | `chugarah.com` | `HTTP` | `frontend:3000` |
| 2 | `rdp.multica` | `chugarah.com` | `RDP` | `host.docker.internal:3389` |
| 3 | `ssh.multica` | `chugarah.com` | `SSH` | `host.docker.internal:22` (optional — skip if you only want RDP) |

Notes:
- The target for rule 1 is the compose service name `frontend`, resolved inside the Docker network the cloudflared sidecar is attached to.
- Rules 2 and 3 target `host.docker.internal`, which resolves to the Windows host from inside the cloudflared container (the compose file maps this via `extra_hosts: host-gateway`).
- Rule 2 (`rdp.multica`) enables **browser-based RDP** — no client install on the operator's laptop.

Cloudflare auto-creates CNAME DNS records under `chugarah.com` pointing each hostname at the tunnel. No DNS edits needed.

## 3. Create Cloudflare Access applications (one per hostname)

For each of the three hostnames:

1. **Zero Trust → Access → Applications → Add an application**.
2. Type: **Self-hosted**.
3. Application name: e.g. `Multica`, `Multica Admin RDP`, `Multica Admin SSH`.
4. Session duration: `24h` (or your preference).
5. Application domain: the hostname from §2.
6. **Next → Add a policy**.
7. Policy name: `operator`. Action: `Allow`.
8. Include rule: `Emails` → list the operator email(s).
9. Save.

Repeat for each hostname.

This mirrors the pattern used for `code.chugarah.com` and `term.chugarah.com`.

## 4. Paste the token into `.env.production`

On the server:

```powershell
notepad D:\Apps\Multica\.env.production    # adjust path to wherever your repo lives
```

Set `CLOUDFLARE_TUNNEL_TOKEN=` to the string copied in §1. Save.

## 5. Start the stack

```powershell
.\scripts\windows\Start-Multica.ps1
```

Within ~30 seconds, the Cloudflare dashboard should show `multica-home` as **HEALTHY**.

## 6. Verify each hostname

From a browser (incognito) on any network:

- `https://multica.chugarah.com` → Access email prompt → Multica login.
- `https://rdp.multica.chugarah.com` → Access email prompt → browser RDP session on the Windows host.
- `ssh` path: see [`admin-access.md`](admin-access.md).

## Troubleshooting

| Symptom | First thing to check |
|---|---|
| Tunnel shows `DOWN` in dashboard | `docker compose logs cloudflared` for a handshake error. Bad token → regenerate and re-paste. |
| Tunnel `HEALTHY` but `502 Bad Gateway` on `multica.chugarah.com` | `docker compose ps` — is `frontend` running and healthy? `Logs-Multica.ps1 frontend` for boot errors. |
| RDP hostname shows "cannot reach host" | Verify RDP is enabled on the Windows host: `Get-NetTCPConnection -LocalPort 3389 -State Listen`. |
| Access prompt doesn't appear (page just loads) | Access application not wired to that hostname. Re-check §3 — the Application domain must match exactly. |
