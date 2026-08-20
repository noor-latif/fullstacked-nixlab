# fullstacked-nixlab

NixOS infrastructure-as-code for the `fullstacked.se` VPS.

Mail stack (see the `*.opencode` skills): Stalwart mail server, Pangolin/Traefik reverse proxy, Cloudflare DNS.

## Layout

```
nixos/                        Example NixOS configuration
modules/
  stalwart/                   services.stalwartSetup — Stalwart listeners, TLS, lego-free ACME, firewall
  pangolin-bridge/            Pangolin host firewall bridge
scripts/
  apply-nixos.sh              Build flake as current user + sudo switch-to-configuration
  cloudflare-upsert-fullstacked-dns.sh   Upsert all Cloudflare DNS records
  mail-health-check.sh        Service/listener/TLS/HTTP/auth health probe
  mail-tls-check.sh           TLS cert lifetime + Cloudflare DNS sanity check
```

## Deploy

```sh
scripts/apply-nixos.sh        # or: nixos-rebuild switch --flake .#nixos
```

## Operations

- Secrets: `~/.secrets/fullstacked.env` (600, not in git).
- DNS records are managed by the Cloudflare API script; keep mail hostnames DNS-only (unproxied).
- Health: `scripts/mail-health-check.sh` (exit 0 = healthy).

See `docs/operations.md` and the Stalwart skill for details.