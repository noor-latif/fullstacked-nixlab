# fullstacked-nixlab
NixOS infrastructure-as-code for the `fullstacked.se` VPS on NixLab (`143.14.50.130`).

## Architecture
- **Mail Server**: Stalwart mail server (SMTP, IMAP, submission) + Webmail portal on private Tailnet (`41209`).
- **Reverse Proxy**: Caddy `2.11+` running in user space (`systemctl --user status caddy`) terminating TLS:
  - Public listener (`143.14.50.130:443`): Strictly `blogg.latif.se` only.
  - Private listener (`100.111.219.50:443` & `[fd7a:115c:a1e0::3f3a:db33]:443`): All private services.
- **Routing CLI**: Pure-Go `subscale` CLI (`~/dev/subscale/`, installed to `~/.local/bin/subscale`).
- **DNS Provider**: HostUp (`cloud.hostup.se/mcp`) for `latif.se` and `fullstacked.se`. Wildcard `*.latif.se` routes to NixLab Tailscale.
- **TLS Automation**: Automated Let's Encrypt wildcard renewal via `lego-renew.timer` + `lego-hostup-hook.py`.
- **Agent Stack**: Native Oh My Pi (OMP v18) + `omp-web.service` on `127.0.0.1:8787`.
- **Decommissioned**: Pangolin (Traefik/Gerbil) and Python Hermes stacks were fully decommissioned in September 2026.

## Layout
```
nixos/                        Example NixOS configuration
modules/
  stalwart/                   services.stalwartSetup — Stalwart listeners, TLS, firewall
scripts/
  apply-nixos.sh              Build flake as current user + sudo switch-to-configuration
  mail-health-check.sh        Service/listener/TLS/HTTP/auth health probe
```

## Operations
- Secrets: `~/.config/environment.d/secrets.conf` (`chmod 600`) and `~/.secrets/hostup.env`.
- Private Subdomain Routing:
  ```bash
  subscale up <FQDN> <PORT|HOST:PORT>
  subscale down <FQDN>
  subscale list
  ```
- Health: `scripts/mail-health-check.sh` (exit 0 = healthy).
