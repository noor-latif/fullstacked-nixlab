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
PANGOLIN_API_TOKEN
PANGOLIN_ORG_ID=fullstacked
PANGOLIN_API_BASE=http://localhost:3003/v1
PANGOLIN_CONTAINER=pangolin
CF_DOMAIN=fullstacked.se
CF_MAIL_HOST=mail.fullstacked.se
CF_PUBLIC_IPV4=143.14.50.130
HOSTUP_RELAY=relay.hostup.se
HOSTUP_RELAY_PORT=587
```

Do not put API tokens, mailbox/admin passwords, ACME account keys, TLS private keys, or `/opt/pangolin/config/db` in git.

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

## Pangolin

Pangolin runs from `/opt/pangolin` with Docker Compose. The tracked config files are templates/snapshots; keep secrets out of tracked copies.

Before first deploy from a fresh clone:

```sh
cp pangolin/.env.example pangolin/.env
```

Set `PANGOLIN_SERVER_SECRET` in `pangolin/.env` to the live Pangolin-generated server secret from the existing installation, or generate a new one for a brand-new deployment:

```sh
openssl rand -hex 32
```

List Pangolin resources and targets via the integration API (see `config/openapi.yaml`):
