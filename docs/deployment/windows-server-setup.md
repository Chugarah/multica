# Windows Server 2019 — one-time host prep

Follow this once on `192.168.1.162` before running `Install-Multica.ps1`. Commands assume an elevated PowerShell.

## 1. Enable WSL2 and the Virtual Machine Platform

```powershell
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
# Reboot once, then:
wsl --set-default-version 2
wsl --install -d Ubuntu-22.04   # optional — Docker Desktop brings its own WSL distro
```

## 2. Cap WSL2 memory (the 7 GB-host safety net)

Copy [`assets/wslconfig.sample`](assets/wslconfig.sample) to `%USERPROFILE%\.wslconfig`, then:

```powershell
wsl --shutdown
```

The cap kicks in the next time Docker Desktop brings its WSL VM up.

## 3. Install Docker Desktop

Download from https://www.docker.com/products/docker-desktop/ and install with the WSL2 backend (default). After install:

- Open Docker Desktop → Settings → Resources → WSL Integration → leave defaults.
- Verify: `docker version` returns both Client and Server blocks.
- Add the operator user to the `docker-users` local group if not already: `net localgroup docker-users "DOMAIN\user" /add`.

**Caveat**: Docker Desktop's license covers personal use and small business; once this install is no longer hobby-grade, read [`docker-desktop-to-engine.md`](docker-desktop-to-engine.md) for the cutover path.

## 4. Enable RDP (for Cloudflare RDP admin)

RDP is part of the base OS. Verify the service is running and the listener is on the default port:

```powershell
Get-Service TermService | Format-List Status, StartType
Get-NetTCPConnection -LocalPort 3389 -State Listen
```

If RDP isn't enabled: `Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 0`. Also run `Enable-NetFirewallRule -DisplayGroup "Remote Desktop"` for **private** profile only — **do not** allow 3389 on the public firewall profile. All external RDP reaches the host via `cloudflared`, not directly.

## 5. (Optional) Enable Windows OpenSSH Server

Only if you want the `ssh.multica.chugarah.com` admin path in addition to RDP.

```powershell
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Start-Service sshd
Set-Service sshd -StartupType Automatic
New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 -Profile Private
```

Again — private profile only. External reachability comes via cloudflared.

## 6. AirVPN Eddie sanity check

Confirm:
- Eddie is running with its usual kill-switch + route-all-traffic settings.
- Outbound TCP/443 is NOT blocked. (AirVPN's default doesn't block it; just verify.)
- No stale TAP/WinTun adapter is flapping. `Get-NetAdapter | ? Status -eq 'Up'` should show Eddie's tunnel and your LAN NIC, nothing more.

See [`eddie-coexistence.md`](eddie-coexistence.md) for the theory.

## 7. Clone or copy the repo onto the server

Pick a path under your shared `Apps` folder (so it shows up at `V:\Multica\` from your dev machine too). For example `D:\Apps\Multica\` if `D:\Apps` is what backs the `\\192.168.1.162\Apps` share.

```powershell
cd D:\Apps   # or wherever the Apps share physically lives
git clone https://github.com/<your-fork>/multica.git Multica
cd Multica
```

## 8. First-time install

```powershell
.\scripts\windows\deploy.cmd
```

The wrapper self-elevates, runs `Install-Multica.ps1`, offers to register the Scheduled Tasks, and offers to start the stack.

## 9. Verify

```powershell
.\scripts\windows\Start-Multica.ps1
docker compose -f docker-compose.prod.yml ps
docker stats --no-stream
```

Expect four containers (postgres, backend, frontend, cloudflared) all running, backend `healthy`, and total memory under ~1.5 GB steady-state.
