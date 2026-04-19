# Eddie coexistence — why no Tailscale, and how `cloudflared` stays out of the way

The home Windows Server runs AirVPN's Eddie client with:
- kill-switch enabled,
- force-all-traffic-through-VPN enabled,
- periodic exit-server rotation (Eddie picks a new server every few hours or on demand).

This document records why we ruled out Tailscale on the same host and why `cloudflared` is safe.

## The dual-VPN problem

Both Tailscale and Eddie want to own the host's routing table:

| Concern | Eddie | Tailscale |
|---|---|---|
| Default route | Takes over `0.0.0.0/0` via the VPN tunnel | Wants to publish routes for `100.64.0.0/10` (CGNAT) and handshake outbound to its control plane + DERP relays |
| Kill-switch | Blocks outbound that isn't via the tunnel | Depends on outbound being reachable |
| Exit rotation | Egress IP changes on every rotation | Tailscale coordination server sees the node's source IP change, marks the device as "moved", re-keys |

Running both on the same Windows host means the Tailscale node is at best flapping (node identity changes on every Eddie rotation; DERP handshakes get torn down and re-established) and at worst completely unreachable (Eddie's kill-switch blocks Tailscale's outbound before it can reach the control plane).

## Options considered and rejected

### A) Tailscale in a Docker sidecar

Works partially. `network_mode: "service:tailscale"` can expose *container* services to the tailnet — useful for the app, but **cannot expose the Windows host's RDP/SSH**. Since the whole point of putting Tailscale on this host was admin access, that's a dead end.

### B) Eddie split-tunnel excluding Tailscale traffic

Eddie's Routes tab supports IP/domain exclusions. Tailscale's DERP relay IP set is **dynamic** — there's no stable whitelist. You'd miss relays on every rotation. Unworkable.

### C) (Chosen) Cloudflare Tunnel for everything

`cloudflared` makes **outbound-only** TLS/QUIC connections to Cloudflare's edge (a small set of well-known anycast IPs on TCP/443). That's the same traffic shape as ordinary browsing; Eddie doesn't care whether it's an app or a tunnel.

## Why `cloudflared` coexists cleanly

- **No routing-table ownership.** cloudflared does not install a default route or a tun/tap device. It's just a process opening TCP to a destination.
- **Outbound, not inbound.** Cloudflare's edge doesn't need to reach the home IP. Nothing changes if Eddie rotates egress.
- **Inherits Eddie's tunnel.** Traffic from cloudflared goes through whatever Eddie-selected path Windows hands it — that's fine. Cloudflare authenticates at the application layer (tunnel token), not the network layer.
- **Auto-reconnect.** When Eddie rotates exit servers, the TCP connection from cloudflared drops; `cloudflared` reconnects within seconds and resumes. The tunnel ingress rules and tunnel ID in Cloudflare's dashboard stay valid.

## If Eddie ever blocks `cloudflared`

In a default AirVPN config it won't — outbound TCP/443 is open. If you ever restrict Eddie further (e.g. allow-list by destination), add an exception:

- **Destination**: `*.cloudflare.com` (primary) and `*.cloudflareaccess.com` (Access edges) on port 443.

Because cloudflared uses anycast IPs served by Cloudflare's network, you cannot pin this to static IPs; use domains.

## Observing Eddie + cloudflared in practice

Normal healthy state:

```powershell
docker compose logs --tail 100 cloudflared
```

should show periodic `INF Connection <id> registered connIndex=N location=<airport-code>` lines. When Eddie rotates you'll see one connection drop and a new `registered` line within ~30 seconds. If you see repeated `ERR failed to dial to edge` for more than a minute, Eddie's kill-switch or firewall rules may have tightened — check Eddie's log.

## One-line summary

`cloudflared` is invisible to Eddie because it's ordinary outbound HTTPS. Tailscale is not, and tries to compete with Eddie for the route table. On this host, we pick the invisible one.
