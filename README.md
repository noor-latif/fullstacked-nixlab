# Mox Mail Server — NixOS Module

NixOS module for running a [Mox](https://www.xmox.nl/) mail server with automated Let's Encrypt certificates (DNS-01), optional SMTP relay, and optional Pangolin/Traefik reverse proxy integration.

## Quick Start

1. Copy and edit the example configuration:

   ```sh
   cp nixos/configuration.nix.example nixos/configuration.nix
   $EDITOR nixos/configuration.nix
   ```

2. Set at minimum: `hostname`, `domain`, `publicIps`, `adminAccount`, `acme.email`, `dkimSelectors`.

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

   If you have the `apply` shell alias set up, you can also run `apply`.

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
| `services.mox-mail.certExtraDomains` | list | no | Additional SAN domains for the TLS cert (default: `[]`) |
| `services.mox-mail.internalIps` | list | no | IPs for internal HTTP listener (default: `["127.0.0.1" "::1"]`) |
| `services.mox-mail.acme.email` | str | yes | Email for Let's Encrypt registration |
| `services.mox-mail.acme.server` | str | no | ACME server (default: `"letsencrypt"`, also `"letsencrypt-staging"`) |
| `services.mox-mail.acme.envFile` | str | no | Path to DNS API credentials (default: `/var/lib/acme/cloudflare.env`) |
| `services.mox-mail.acme.dnsProvider` | str | no | Lego DNS provider (default: `"cloudflare"`) |
| `services.mox-mail.acme.legoExtraFlags` | list | no | Extra flags for lego, e.g. `["--ipv4only"]` (default: `[]`) |
| `services.mox-mail.dkimSelectors` | list | yes | DKIM selector names |
| `services.mox-mail.dkimKeyType` | str | no | Key type used in DKIM filename (default: `"rsa2048"`) |
| `services.mox-mail.relay.enable` | bool | no | Enable SMTP relay for outbound mail |
| `services.mox-mail.relay.host` | str | conditional | Relay hostname (required if relay enabled) |
| `services.mox-mail.pangolin.enable` | bool | no | Enable Pangolin/Traefik cert copying |
| `services.mox-mail.forcePasswordChange` | bool | no | Require password change on first login (default: `false`) |
| `services.mox-mail.dnsPropagationWait` | str | no | Fixed wait for DNS propagation before ACME validation (e.g. `"30s"`) |

## Architecture

Direct mail ports on host:

```text
Internet -> VPS:25   SMTP receive
Internet -> VPS:465  SMTP submissions (implicit TLS)
Internet -> VPS:993  IMAPS
```

Internal HTTP services (reverse proxy these through Nginx, Traefik, or Pangolin):

```text
<internal IP>:81    MTA-STS, Autoconfig (plain HTTP, forwarded header trusted)
<internal IP>:1080  Webmail, Admin, Account, WebAPI (plain HTTP, forwarded header trusted)
```

The internal HTTP ports are bound to the IPs configured in `internalIps`. When using Docker/Pangolin, add the Docker bridge IP (e.g. `"172.18.0.1"`). When using Nginx on the host, `"127.0.0.1"` is sufficient.

## Files

```
modules/mox/
  default.nix          Options schema + imports
  seed-config.nix      Generates mox.conf + domains.conf from options (first boot only)
  cert-renewal.nix     Lego DNS-01 cert renewal service + timer
  systemd-service.nix  Mox systemd service (hardened)
  firewall.nix         Opens TCP 25/465/993/1080 via lib.mkAfter

nixos/
  configuration.nix.example  Example machine configuration
  hardware-configuration.nix Auto-generated hardware config

scripts/
  apply-nixos.sh                        Convenience wrapper for nixos-rebuild switch
  cloudflare-upsert-fullstacked-dns.sh  Cloudflare DNS record management
  pangolin-reconcile-mox-resources.sh   Pangolin API resource reconciliation
```

## Certificate Renewal

Certificates are issued via Let's Encrypt DNS-01 challenge using [lego](https://go-acme.github.io/lego/). The module runs `mox-lego-cert.service` (oneshot) on a daily timer. Certs are copied to `/var/lib/mox/config/tls/` for Mox and optionally to a Traefik certs directory if `pangolin.enable` is true.

Set `acme.server` to `"letsencrypt-staging"` while testing to avoid rate limits.

## DKIM Keys

DKIM private keys must be generated manually and placed under `/var/lib/mox/config/dkim/`. The expected filename pattern is:

```
<selector>._domainkey.<domain>.<keyType>.privatekey.pkcs8.pem
```

Example for selector `2026a`, domain `example.com`, key type `rsa2048`:
```
dkim/2026a._domainkey.example.com.rsa2048.privatekey.pkcs8.pem
```

The `dkimKeyType` option (default `"rsa2048"`) controls the key type portion of the filename.

## Firewall

The module opens TCP ports 25, 465, 993, and 1080 via `lib.mkAfter`. Port 81 (MTA-STS/autoconfig) is internal only and should be reverse proxied, not exposed directly.

## CAA Records

Add Certificate Authority Authorization records to restrict which CAs can issue certificates for your domain:

```
example.com              CAA 0 issue "letsencrypt.org"
mail.example.com         CAA 0 issue "letsencrypt.org"
mta-sts.example.com      CAA 0 issue "letsencrypt.org"
autoconfig.example.com   CAA 0 issue "letsencrypt.org"
```

The cloudflare-upsert script includes CAA record management.

## Backup and Maintenance

Back up before upgrades:

```sh
sudo -u mox mox backup /path/to/backup --config /var/lib/mox/config/mox.conf
```

After a backup restore, run:

```sh
sudo -u mox mox verifydata /path/to/restored/data
```

For each account with changed mailbox state after restore, bump UID validity to force IMAP clients to re-sync:

```sh
sudo -u mox mox bumpuidvalidity --config /var/lib/mox/config/mox.conf ACCOUNT_NAME
```

Mox also exposes Prometheus metrics at the `/metrics` endpoint on the webmail/admin listener (port 1080).

## License

MIT
