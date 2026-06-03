# Operations

## Secrets

Runtime tokens are intentionally not committed. On this server they live in:

```sh
/home/noor/.config/codex-agents/fullstacked.env
```

Expected variables:

```sh
CLOUDFLARE_API_TOKEN
CLOUDFLARE_ZONE_NAME=fullstacked.se
PANGOLIN_API_TOKEN
PANGOLIN_ORG_ID=fullstacked
PANGOLIN_API_BASE=http://localhost:3003/v1
PANGOLIN_CONTAINER=pangolin
MOX_DOMAIN=fullstacked.se
MOX_MAIL_HOST=mail.fullstacked.se
MOX_PUBLIC_IPV4=143.14.50.130
HOSTUP_RELAY=relay.hostup.se
HOSTUP_RELAY_PORT=587
```

Do not put API tokens, Mox mailbox/admin passwords, ACME account keys, TLS private keys, or `/opt/pangolin/config/db` in git.

## Deploy NixOS Config

This repo tracks the deployable NixOS config under `nixos/` and reusable modules under `modules/`.

Current live host imports `/etc/nixos/mox.nix`. Keep live changes mirrored here before rebuilding:

```sh
sudo cp nixos/configuration.nix /etc/nixos/configuration.nix
sudo cp modules/mox.nix /etc/nixos/mox.nix
sudo nixos-rebuild switch
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

Check current resources:

```sh
scripts/pangolin-reconcile-mox-resources.sh
```

## Mox

Validate config:

```sh
sudo -u mox sh -c 'cd /var/lib/mox && mox -config config/mox.conf config test'
```

Start after TLS cert paths are real:

```sh
sudo systemctl start mox
sudo systemctl status mox --no-pager
```
