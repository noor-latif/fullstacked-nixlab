# Operations

## Secrets

Runtime tokens are intentionally not committed. On this server they live in:

```sh
/home/noor/.secrets/fullstacked.env
```

Expected variables:

```sh
CLOUDFLARE_API_TOKEN
CLOUDFLARE_ZONE_NAME=fullstacked.se
PANGOLIN_API_TOKEN (legacy, unused since 2026-09 decommission)
PANGOLIN_ORG_ID=fullstacked (legacy, unused)
PANGOLIN_API_BASE=http://localhost:3003/v1 (legacy, unused)
PANGOLIN_CONTAINER=pangolin (legacy, unused)
CF_DOMAIN=fullstacked.se
CF_MAIL_HOST=mail.fullstacked.se
CF_PUBLIC_IPV4=143.14.50.130
HOSTUP_RELAY=relay.hostup.se
HOSTUP_RELAY_PORT=587
```

Do not put API tokens, mailbox/admin passwords, ACME account keys, or TLS private keys in git.

## Deploy NixOS Config

This repo tracks the deployable NixOS config under `nixos/` and reusable modules under `modules/`. The preferred deploy path is the pinned flake in `flake.nix`.

Build without switching:

```sh
nixos-rebuild build --flake .#nixos
```

Apply:

```sh
scripts/apply-nixos.sh
```

The apply script builds the flake as the current user and only uses `sudo` for
the final `switch-to-configuration` step. Avoid running the whole flake
evaluation with `sudo`, because root may reject a user-owned git checkout.

After the first flake switch, new shells also have:

```sh
apply
```

## DNS

Mail-related hostnames must be DNS-only in Cloudflare. Do not proxy `mail.fullstacked.se`, `mta-sts.fullstacked.se`, or `autoconfig.fullstacked.se`.

Apply base records:

```sh
scripts/cloudflare-upsert-fullstacked-dns.sh
```

## Caddy (replaces Pangolin since 2026-09)

Pangolin/Traefik/Gerbil were decommissioned in September 2026 and removed from this repo
(`pangolin/` compose stack, `modules/traefik-watchdog`). The reverse proxy is user-space Caddy:

```sh
/home/noor/.nix-profile/bin/caddy run --config /home/noor/.config/caddy/config.json
```

The Caddy config is live state, NOT tracked in git — back up `/home/noor/.config/caddy/config.json`
separately. Validate before reload: `caddy validate --config <file>`, then `systemctl --user reload caddy`.
`mail.fullstacked.se` reverse-proxies to Stalwart HTTP at `127.0.0.1:41209`.
