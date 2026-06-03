# Mox Mail Server — NixOS Module

NixOS module for running a [Mox](https://www.xmox.nl/) mail server with automated Let's Encrypt certificates (DNS-01), optional SMTP relay, and optional Pangolin/Traefik reverse proxy integration.

## Quick Start

1. Copy and edit the example configuration:

   ```sh
   cp nixos/configuration.nix.example nixos/configuration.nix
   $EDITOR nixos/configuration.nix
   ```

2. Set at minimum: `hostname`, `domain`, `publicIps`, `adminAccount`, `acme.email`, `acme.envFile`, `dkimSelectors`.

3. Generate DKIM keys (run once):

   ```sh
   sudo -u mox mox config dkim \
     --config /var/lib/mox/config/mox.conf \
     YOUR_DOMAIN YOUR_SELECTOR
   ```

4. Apply:

   ```sh
   sudo nixos-rebuild switch --flake '.#nixos'
   ```

5. Set the admin password:

   ```sh
   sudo -u mox mox setadminpassword \
     --config /var/lib/mox/config/mox.conf
   ```

## Module Options

See `modules/mox/default.nix` for the full option schema. Key options:

| Option | Type | Required | Description |
|--------|------|----------|-------------|
| `services.mox-mail.enable` | bool | yes | Enable the Mox mail server |
| `services.mox-mail.hostname` | str | yes | Mail server FQDN, e.g. `mail.example.com` |
| `services.mox-mail.domain` | str | yes | Primary mail domain, e.g. `example.com` |
| `services.mox-mail.publicIps` | list | yes | Public IPv4/IPv6 addresses |
| `services.mox-mail.adminAccount` | str | yes | Admin account name for postmaster, DMARC, TLSRPT |
| `services.mox-mail.certName` | str | no | Cert file prefix (default: `"mail"`) |
| `services.mox-mail.certExtraDomains` | list | no | Additional SAN domains on the TLS cert |
| `services.mox-mail.internalIps` | list | no | IPs for internal HTTP listener (default: `127.0.0.1`, `::1`) |
| `services.mox-mail.acme.email` | str | yes | Email for Let's Encrypt registration |
| `services.mox-mail.acme.envFile` | str | no | Path to DNS provider credentials file (default: `/var/lib/acme/cloudflare.env`) |
| `services.mox-mail.acme.dnsProvider` | str | no | Lego DNS provider (default: `cloudflare`) |
| `services.mox-mail.acme.legoExtraFlags` | list | no | Extra flags for lego, e.g. `["--ipv4only"]` |
| `services.mox-mail.dkimSelectors` | list | yes | DKIM selector names |
| `services.mox-mail.relay.enable` | bool | no | Enable SMTP relay for outbound mail |
| `services.mox-mail.relay.host` | str | conditional | Relay hostname (required if relay enabled) |
| `services.mox-mail.pangolin.enable` | bool | no | Enable Pangolin/Traefik cert copying |

## Architecture

Direct mail ports on host:

```text
Internet -> VPS:25   SMTP receive
Internet -> VPS:465  SMTP submissions (implicit TLS)
Internet -> VPS:993  IMAPS
```

Internal HTTP services (reverse proxy these through Nginx, Traefik, or Pangolin):

```text
172.x.x.1:81    MTA-STS, Autoconfig (plain HTTP, forwarded header trusted)
172.x.x.1:1080  Webmail, Admin, Account, WebAPI (plain HTTP, forwarded header trusted)
```

## Files

```
modules/mox/
  default.nix          Options schema + imports
  seed-config.nix      Generates mox.conf + domains.conf from options (first boot only)
  cert-renewal.nix     Lego DNS-01 cert renewal service + timer
  systemd-service.nix  Mox systemd service (hardened)
  firewall.nix         Opens TCP 25/465/587/993/1080

nixos/
  configuration.nix.example  Example machine configuration
  hardware-configuration.nix Auto-generated hardware config

scripts/
  cloudflare-upsert-fullstacked-dns.sh  Cloudflare DNS management (example)
  pangolin-reconcile-mox-resources.sh   Pangolin API reconciliation (example)
```

## Certificate Renewal

Certificates are issued via Let's Encrypt DNS-01 challenge using [lego](https://go-acme.github.io/lego/). The module runs `mox-lego-cert.service` (oneshot) on a daily timer. Certs are copied to `/var/lib/mox/config/tls/` for Mox and optionally to a Traefik certs directory.

## Firewall

The module opens TCP ports 25, 465, 587, 993, and 1080 via `lib.mkAfter`. Port 81 (MTA-STS/autoconfig) is internal only.

## License

MIT
