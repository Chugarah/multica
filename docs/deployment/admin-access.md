# Admin access — RDP and SSH via Cloudflare

No Tailscale. Both admin paths go through the same `cloudflared` sidecar that serves the public site. Cloudflare Access enforces SSO before any TCP reaches the server.

## Browser RDP (recommended)

From **any** machine, any browser:

1. Open `https://rdp.multica.chugarah.com`.
2. Sign in via Cloudflare Access (email + magic link, or your configured IdP).
3. A browser-native RDP session opens. No client install.

Use cases: fixing the server from a phone, another operator's laptop, a public computer in a pinch.

Behind the scenes: cloudflared ingress rule `rdp.multica.chugarah.com` → `rdp://host.docker.internal:3389`. The container reaches the Windows host via the compose `extra_hosts: host-gateway` mapping. Windows RDP listens on 3389 on the private profile only.

## SSH from a terminal (optional)

Requires `cloudflared` installed locally on the client machine (Mac/Linux/Windows).

### One-shot

```bash
cloudflared access ssh --hostname ssh.multica.chugarah.com
```

The first run pops a browser for Access SSO, caches the token, then drops you to a shell.

### Persistent, via `~/.ssh/config`

Append:

```
Host multica-server
    HostName ssh.multica.chugarah.com
    User Administrator
    ProxyCommand cloudflared access ssh --hostname %h
```

Then just `ssh multica-server`. Any standard SSH client (VS Code Remote-SSH, JetBrains, mosh) that respects `ProxyCommand` works.

### Windows client

Install `cloudflared` from https://github.com/cloudflare/cloudflared/releases/latest (pick `cloudflared-windows-amd64.exe`, rename to `cloudflared.exe`, put on `PATH`).

### Prereq on the server

You must have followed [`windows-server-setup.md`](windows-server-setup.md) §5 to install Windows OpenSSH Server. If you never set that up, SSH won't work — stick to RDP.

## Why not Tailscale

See [`eddie-coexistence.md`](eddie-coexistence.md). Short version: AirVPN Eddie already owns the host's route table, and the two VPNs fight. Cloudflare Tunnel is outbound-only and coexists cleanly.

## Revoking access

Add/remove users in the Cloudflare Access application policy (three apps, one per hostname — see [`cloudflare-tunnel.md`](cloudflare-tunnel.md) §3). Changes take effect on next login; to kill active sessions, use **Zero Trust → My Team → Revoke sessions**.
