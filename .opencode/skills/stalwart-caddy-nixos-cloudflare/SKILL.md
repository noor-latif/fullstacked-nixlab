---
name: stalwart-caddy-nixos-cloudflare
description: Use when working on the mail stack on fullstacked.se — the Stalwart mail server, Caddy reverse proxy, Cloudflare DNS/DNSSEC, or the NixOS modules that configure them. Triggers on Stalwart, mail server, mail.fullstacked.se, MTA-STS, autoconfig, DKIM, DMARC, Caddy, Cloudflare, or fullstacked-nixlab.
---

# Stalwart + Caddy + NixOS + Cloudflare

Use this skill for work on Noor's mail setup:

- Domain: `fullstacked.se`
- Mail hostname: `mail.fullstacked.se`
- VPS OS: NixOS, flake at `/home/noor/dev/fullstacked-nixlab`
- Mail server: **Stalwart 0.16.16** via the `services.stalwartSetup` module in `modules/stalwart/`. All config lives in the Stalwart **RocksDB datastore** under `/var/lib/stalwart/` (bootstrapped by `/var/lib/stalwart/config.json`).

**`/var/lib/stalwart/config.json` is ONLY a RocksDB storage bootstrap** (its top-level keys are `@type`, `path`, `blobSize`, `bufferSize`, `poolWorkers`). It does NOT contain listener/server/http settings. The real config objects (listeners, domains, certs, ACME, DNS, relay, `SystemSettings`, `proxyTrustedNetworks`, etc.) are stored as RocksDB objects, managed via webadmin / `stalwart-cli` / JMAP (`x:`-namespaced methods). **`/etc/stalwart/stalwart.toml` is EMPTY/unused — never edit it; changes there do nothing.** To find the live `--config=` path: `systemctl cat stalwart.service`.
- Reverse proxy: user-space **Caddy** (`/home/noor/.nix-profile/bin/caddy run --config /home/noor/.config/caddy/config.json`). Pangolin/Traefik/Gerbil were decommissioned 2026-09; `/opt/pangolin` is gone and no pangolin/gerbil/traefik containers run.
- TLS certs: **Stalwart built-in ACME** (DNS-01; Cloudflare provider broken since the DNS move, DeSEC migration planned — see Certificates). Lego is a different project: its `hostup` provider (v5.0.0) can't plug into Stalwart's built-in client.
- Outbound relay: Hostup `relay.hostup.se:587` (`MtaRoute/Relay` id `i31fgvcqacaa`), wired via `MtaOutboundStrategy` route: local-domain → `local`, else → `hostup`.

Do not store or repeat secrets. Existing secrets for this setup are stored in `/home/noor/.secrets/fullstacked.env`; source that file instead of asking again if it exists.

## Machine

- User: `noor`, groups: docker, networkmanager, wheel
- OS: NixOS 26.05, Kernel: Linux 6.18
- CPU: 2 vCPU AMD EPYC (KVM), RAM: 3.8 GiB, disk: 47 GB
- Hostname: `nixos`
- Public IP: `143.14.50.130`
- Timezone: Europe/Stockholm

## Sudo

This machine has `timestamp_type=global` (configured in the NixOS flake). Sudo credentials are cached per-user across all TTYs for 20 minutes.

Warm the cache from a separate terminal with `sudo -v`, then the agent can use sudo for 20 minutes. To end early: `sudo -k`.

If the agent's sudo fails with "a terminal is required", the cache is cold — re-run `sudo -v` manually.

## Operating Rules

- Research official docs or generated local schemas before fixing failed or unclear behavior; do not guess API shapes.
- For Caddy work, read `/home/noor/.config/caddy/config.json` first (it is the live config; it is NOT tracked in this repo). Validate with `caddy validate --config <file>` before reload.
- Track reproducible server changes in `/home/noor/dev/fullstacked-nixlab` git. Make frequent, small commits after each logical change.
- Keep secrets and generated private state out of git.
- The Stalwart config is **generated into the Nix store** by `modules/stalwart/default.nix`. Get the active path with `systemctl cat stalwart.service` (look at the `--config=` arg in `ExecStart`). Do not hand-edit a store path; edit the module instead.
- Keep mail protocols direct on the VPS: `25`, `465`, `993`. No STARTTLS on 587.
- Stalwart HTTP (webadmin/JMAP, `127.0.0.1:41209`) is exposed publicly as `mail.fullstacked.se` via a Caddy `reverse_proxy` route. `mta-sts`/`autoconfig`/`vpn` DNS still points at the VPS but Caddy serves NO route for those hosts (Pangolin used to) — they fall through to the default route. Re-add Caddy routes if MTA-STS policy serving is wanted.
- Keep `mail.fullstacked.se` DNS-only in Cloudflare. Do not proxy mail hostnames through Cloudflare orange-cloud.
- Do not move mail into Kubernetes.
- Do not commit or write API keys, sudo passwords, Stalwart admin passwords, mailbox passwords, or TLS private keys into skill/docs.

## Git Repo

Repo: `/home/noor/dev/fullstacked-nixlab`
Remote: `https://github.com/noor-latif/fullstacked-nixlab.git`
Git identity: `noor latif <noor@latif.se>`

Do not commit: runtime env files, API tokens, ACME state, Stalwart passwords, mailbox data, TLS private keys.

To apply NixOS changes:

```sh
cd /home/noor/dev/fullstacked-nixlab
git add -A
sudo nixos-rebuild switch --flake '.#nixos'
```

Or use the alias: `apply` (resolves to `scripts/apply-nixos.sh` which builds the toplevel and execs `switch-to-configuration switch`).

## Source of Truth Architecture

The single source of truth for this machine's OS configuration is `/home/noor/dev/fullstacked-nixlab` (and the GitHub remote `noor-latif/fullstacked-nixlab`). The active `/etc/nixos` is a thin wrapper:

- `/etc/nixos/flake.nix` declares a single `path:` flake input pointing at the repo and re-exports `nixlab.nixosConfigurations.nixos`.
- `/etc/nixos/configuration.nix` and `/etc/nixos/hardware-configuration.nix` do not exist; all modules come from the repo.

Consequences:

- `nixos-rebuild switch` without `--flake` still works because the wrapper resolves the same `nixosConfigurations.nixos`.
- `cd /home/noor/dev/fullstacked-nixlab && apply` is the documented way to update. `nixos-rebuild switch --flake .#nixos` from inside the repo is equivalent.
- All paths in this skill point at the repo, not at /etc/nixos.

## Hermes User Install

Hermes Agent is **not** part of the server flake. It is a user-space install owned by `noor`:

- Install method: official `curl -fsSL hermes-agent.nousresearch.com/install.sh | bash`. Lives in `~/.hermes/hermes-agent` (Git checkout, no NixOS module).
- Runtime deps: user `nix profile` (not the server flake, not `/etc/nixos`). Current pinned packages: `git`, `uv`, `python311`, `nodejs_22`. Version pin recorded in `~/.hermes/runtime.toml`.
- Gateway: user systemd unit `hermes-gateway.service`, runs the venv at `~/.hermes/hermes-agent/venv/bin/python`. Backing systemd user instance has lingering enabled.
- Hermes gateway owns port `8642`. There is intentionally **no** `services.hermes-agent` system service and **no** Hermes Cachix trust in the server flake.

If the user mentions "Hermes module", "services.hermes-agent", or "Hermes Cachix" in the context of this machine, those are gone and should not be reintroduced.

## Experimental Features

`nix-command` and `flakes` are NOT on by default in this NixOS config. The repo sets them explicitly with `lib.mkForce`:

```nix
nix.settings.experimental-features = lib.mkForce [ "nix-command" "flakes" ];
```

Verify with `nix show-config | head -3` (no flags). If a fresh `nix build` errors with "experimental Nix feature 'nix-command' is disabled", the wrapper is missing or not switched; check `/etc/nixos/flake.nix` and run `apply`.

## nix.settings Rule

`nix.settings.*` in `nixos/configuration.nix` uses `lib.mkForce` for every list-valued key (substituters, trusted-public-keys, trusted-users, experimental-features). Without `mkForce`, NixOS defaults and our values get merged with `lib.mkMerge`, producing duplicated entries in `/etc/nix/nix.conf`. New list keys added in this repo must also use `lib.mkForce`.

## Git Push Broken: gh Credential Helper

`git push` from this machine fails with:

```text
fatal: could not read Username for 'https://github.com': No such device or address
```

Cause: `~/.gitconfig` has a per-URL section `[credential "https://github.com"]` whose `helper = !/nix/store/<hash>-gh-2.93.0/bin/.gh-wrapped auth git-credential` points at a store path that is gone (gc or package upgrade). The OAuth token is still in `~/.config/gh/hosts.yml` under `oauth_token`.

`git -c credential.helper= ...` does NOT clear this — the per-URL section wins over the global helper. The working workaround is an `insteadOf` URL rewrite that embeds the token:

```sh
TOKEN=$(awk '/oauth_token:/{print $2; exit}' /home/noor/.config/gh/hosts.yml)
git -c credential.helper= \
    -c "url.https://x-access-token:${TOKEN}@github.com/noor-latif/fullstacked-nixlab.git.insteadOf=https://github.com/noor-latif/fullstacked-nixlab.git" \
    push origin main
```

This rewrites only the repo URL, scopes the token to a single command, and never writes it to disk.

Real fix (not done yet): reinstall `gh` via the user nix profile and update the credential helper in `~/.gitconfig` to the new store path.

## New VPS Recovery (Honest Answer)

**No, you cannot `git clone` and `apply` on a fresh VPS and have a working production server.** The repo provides reproducible *configuration*, not reproducible *state*.

What the repo reproduces from a fresh clone:

- System packages and services (Stalwart, Docker, fail2ban, openssh, nix-daemon, etc.).
- User accounts with `noor`'s authorized SSH keys.
- Firewall and Stalwart module defaults.
- The `/etc/nixos` wrapper structure.

What the repo does **not** reproduce (state that must be backed up separately):

- `/var/lib/stalwart/` — rocksdb data (`db/`), `config/tls/` (certs + DKIM keys), webadmin principals. This is the mailbox + account state.
- `/home/noor/.config/caddy/config.json` — the live Caddy config (NOT in git; back it up separately).
- `/home/noor/.secrets/fullstacked.env` — the ops secrets file (Cloudflare token, Stalwart admin + health passwords, Clerk keys; legacy Pangolin tokens unused). Restore it with `chmod 700 ~/.secrets && chmod 600 ~/.secrets/fullstacked.env`.
- `/etc/ssh/ssh_host_*` — host keys. New VPS will get fresh ones; existing clients will need to re-trust or have `known_hosts` cleaned.
- The Cloudflare API token for (legacy) ACME lives in `/home/noor/.secrets/fullstacked.env` (`CLOUDFLARE_API_TOKEN`). (`/var/lib/acme/` — minica-era lego state — was deleted 2026-09-10, backup in `~/backups/orphaned-20260910/`.)

Practical new-VPS recovery, in order:

1. Provision a new VPS at Hostup with the same disk layout (btrfs subvols for `/`, `/home`, `/nix`, swap). Get the new public IP.
2. Bootstrap NixOS on the new VPS via Hostup's installer. During install, set up `noor` with an SSH key you can reach.
3. `git clone https://github.com/noor-latif/fullstacked-nixlab.git /home/noor/dev/fullstacked-nixlab` and `cd` there.
4. `apply`. This sets up system services. Stalwart will start with a fresh `/var/lib/stalwart/db`.
5. Restore state from backup: `/var/lib/stalwart/`, `/home/noor/.config/caddy/config.json`. Restart Stalwart (`systemctl restart stalwart`), reload Caddy.
6. The Docker bridge gateway IP `172.18.0.1` is assigned by Docker; if it changed on the new VPS, update `data/bridge-ports.json` consumers and Caddy upstreams that dial it.
7. Update HostUp DNS: change the `mail.fullstacked.se` A record to the new VPS IP (HostUp MCP `manage_dns_record`; Cloudflare is stale — do not edit there).
8. Update Hostup: PTR/rDNS for the new IP. SPF `include:spf.hostup.se` is unchanged because it is the relay's SPF, not yours. DKIM selectors are unchanged.
9. Reinstall Hermes: `curl -fsSL hermes-agent.nousresearch.com/install.sh | bash`, then restore `~/.hermes/` (excluding the venv, which can be rebuilt). Add git, uv, python311, nodejs_22 to the user nix profile.

**To get closer to "git clone + switch = up"**, the next work is:

- A `scripts/backup-prod-state.sh` that tarballs `/var/lib/stalwart`, `/home/noor/.config/caddy/config.json`, `/home/noor/.hermes` (sans venv). Run nightly via cron, ship to Backblaze B2 or similar.
- Move the Cloudflare token into a passphrase-encrypted file in the repo, decrypted by a small bootstrap script at apply time.

This is real work, not a one-line fix. Tell me if you want to start on it.

## Expected Architecture

Stalwart listeners on host (verified 2026-09-10 via `ss -ltnp`):

```text
[::]:25                      SMTP receive (plaintext, implicit-TLS only on 465)
[::]:465                     SMTP submissions, implicit TLS
[::]:993                     IMAPS, implicit TLS
[::]:41209                   Stalwart HTTP: webadmin + JMAP (plain HTTP, localhost + Caddy)
```

Nothing listens on `172.18.0.1:1080` anymore (that was the Pangolin-era webadmin bind). The `webadminBind` option in `modules/stalwart` is vestigial — the live HTTP listener is on `41209`.

Caddy public HTTPS routes (mail-related, in `/home/noor/.config/caddy/config.json`):

```text
mail.fullstacked.se       -> 127.0.0.1:41209   — webadmin + JMAP (reverse_proxy; no SSO layer)
fullstacked.se            -> static 404        — apex hosts nothing (added 2026-09-10 so TLS handshakes succeed; stale Oracle A 207.127.89.124 deleted same day)
```
`mta-sts`/`autoconfig`/`vpn` A records still point at the VPS but Caddy serves no route for them (Pangolin used to) — MTA-STS policy over HTTPS is currently unserved. Re-add Caddy routes if it is wanted.
Firewall: 25, 465, 993 opened by the Stalwart module. Bridge-scoped container ports opened via `bridge-ports` (reads `data/bridge-ports.json`).

## NixOS Module Structure

The repo contains a reusable NixOS module at `modules/stalwart/`:

```
modules/stalwart/
  default.nix          ← options (services.stalwartSetup) + listeners + TLS + S3 backup
```

Key points (from `modules/stalwart/default.nix`):

- Do **not** name the module `services.stalwart-mail`: upstream registers a `mkRenamedOptionModule` that redirects the whole `services.stalwart-mail.*` subtree to `services.stalwart.*`, which would land custom options on non-existent paths. This module uses the distinct name `services.stalwartSetup`.
- Listeners are implicit-TLS-only: smtp `:25`, submissions `:465` (tlsImplicit), imaps `:993` (tlsImplicit), HTTP on `[::]:41209` (webadmin + JMAP, plaintext, proxied by Caddy as `mail.fullstacked.se`).
- TLS is wired via `server.tls.certificate = "default"` + `[certificate.default]` using the `%{file:...}%` macro (a literal path is treated as PEM content and implicit-TLS then serves plaintext). `certificate.*` and `server.tls.*` must be in `config.local-keys` for the macro to expand.
- First-run admin bootstrap via `authentication.fallback-admin` (sha512-crypt hash from `adminPasswordHash`; generate with `mkpasswd -m sha-512 <pw>`).

## Existing Services

### Stalwart Service (0.16.16)

- Unit: `stalwart.service` (systemd), enabled. Started with `--config=/var/lib/stalwart/config.json`.
- Config is DB-backed (RocksDb datastore); **all objects** (domains, accounts, certs, ACME, DNS, relay, strategies) are managed via webadmin / `stalwart-cli` / JMAP, never by editing a TOML file.
- Data: `/var/lib/stalwart/config.json` (RocksDb: mailboxes, principals, blobs, all config objects).
- Default cert: `Certificate` object `i31e2ujkabqa` (Let's Encrypt YE1, SANs `fullstacked.se` + `mail.fullstacked.se`), set as `defaultCertificateId` in `SystemSettings`.
- DKIM: selectors `2026a` / `2026b`, auto-managed by Stalwart (`dkimManagement` Automatic on domain `b`).
- Admin: `admin@fullstacked.se` (wizard-created). Recovery admin in `/etc/stalwart-admin.env` (root 600) still authenticates if locked out.
- First-run webadmin bootstrap completed; the TEMP `STALWART_RECOVERY_MODE` env block is removed from the module.

## Recovery Mode (CRITICAL diagnostic)

`stalwart.service` is launched with `Environment=STALWART_RECOVERY_MODE_PORT=1080`. If Stalwart **fails to load its RocksDB config**, it enters **recovery mode** and serves ONLY a single HTTP listener on `[::]:1080` (listener name logged as `http-recovery`). Source: `crates/common/src/config/server/listener.rs:47` (`if !bp.registry.is_recovery_mode()` → else branch builds the `[::]:<RECOVERY_PORT>` `http-recovery` listener) and `crates/store/src/build/registry.rs:282` (`is_recovery_mode`).

In recovery mode (`crates/common/src/config/network.rs:404-460`):
- `url_https` is forced empty, `allowed_endpoint` is empty, no anonymous/authenticated rate limits, CORS is permissive.
- NO SMTP/IMAP/IMAPS/submission listeners are started — only the recovery HTTP on `1080`. So if Stalwart is in recovery mode, **mail protocols are down too**, not just the web surfaces.
- The recovery HTTP listener uses `..Default::default()` (proxyProtocol off) and still serves the configured sites over plain HTTP.

**How to tell if Stalwart is in recovery mode:** `sudo journalctl -u stalwart` for `listenerId = "http-recovery"` / config-load errors, and check whether ports `25/465/993` are listening (`ss -ltnp`). If only `1080` is up (and/or the listener is named http-recovery), it is in recovery mode.

**Common trigger after config edits:** a malformed JMAP/`stalwart-cli` change (bad SAN, bad `proxyTrustedNetworks` type, bad cert reference, broken ACME object) can make the datastore unloadable → silent fall into recovery mode. Fix by correcting the offending object via the recovery web UI on `1080` or by re-setting it with `stalwart-cli`/`x:` JMAP, then restart.

## Diagnostics on this host (gotchas)

- **`tcpdump` captures NOTHING on this NixOS host** — even for known-good local traffic (e.g. `curl` to `127.0.0.1:41209` returns 200 but produces zero packets in `tcpdump -i any`). Do NOT rely on tcpdump here. Use `curl` for app-layer tests instead.
- **(Pangolin era, kept for the server-side lesson)** Source-IP dependent HTTP close — ROOT CAUSED (2026-08-16): a Stalwart HTTP listener with a non-empty `proxy_networks` (populated automatically when `SystemSettings.proxyTrustedNetworks` is set, e.g. to `172.18.0.0/16`) makes Stalwart **require the PROXY protocol header from any source in that network**. Bridge peers that send no PROXY header get TCP-open then silent close with **no HTTP response** (surfaced as `502` from the proxy). Confirmed fix: set `SystemSettings.proxyTrustedNetworks` to `{}` (empty Map) and **restart** Stalwart (the listener's `proxy_networks` is built at startup, not hot-reloaded). The companion `AllowedIp 172.18.0.0/16` object (bypasses auto-bans without the PROXY side effect) is still applied and holds.
- HTTP backend checks now target `127.0.0.1:41209` directly: `curl -sS http://127.0.0.1:41209/.well-known/jmap`. A connection refused there with mail protocols still up means the HTTP listener config regressed; a full `25/465/993` outage plus only `1080` listening means recovery mode (see above).

### Caddy (user service, replaces Pangolin 2026-09)

- Binary: `/home/noor/.nix-profile/bin/caddy`, config `/home/noor/.config/caddy/config.json` (live, NOT in git).
- Serves `mail.fullstacked.se` → `reverse_proxy 127.0.0.1:41209` (webadmin + JMAP, no SSO layer), plus `omp`/`cv`/`vault`/`blogg` and other hosts.
- Reload: `caddy validate --config /home/noor/.config/caddy/config.json` then `systemctl --user reload caddy` (or restart the user unit).

## Stalwart Config Highlights

All of the following are **DB objects** (manage via `stalwart-cli` / webadmin / JMAP), NOT TOML:

- Listeners: `smtp :25` (STARTTLS), `submissions :465` (implicit TLS), `imaps :993` (implicit TLS), `http` on `[::]:41209` (webadmin + JMAP, plaintext, reverse-proxied by Caddy as `mail.fullstacked.se`).
- Domain `b` = `fullstacked.se`: `dnsManagement` = **Manual** (we manage Cloudflare DNS ourselves so SPF can include the Hostup relay), `certificateManagement` Automatic → `AcmeProvider i31clpvcaaqa`, `dkimManagement` Automatic.
- `DnsServer/Cloudflare` `i31eq2yuaaqa` (Cloudflare API token) — used ONLY for ACME DNS-01 challenges, not zone management (dnsManagement is Manual).
- `AcmeProvider` `i31clpvcaaqa`: Let's Encrypt, challenge `Dns01`.
- `MtaRoute/Relay` `i31fgvcqacaa`: Hostup `relay.hostup.se:587`, protocol `smtp`, `implicitTls: false` (STARTTLS).
- `MtaOutboundStrategy` route: `{"match":{"0":{"if":"is_local_domain(rcpt_domain)","then":"'local'"}},"else":"'hostup'"}`.
- Account `c` = `noor@fullstacked.se` (User). Other accounts: `admin@fullstacked.se` (wizard), `f` = `vcheck@fullstacked.se` (dedicated health-check account; used only by `scripts/mail-health-check.sh` auth probes, creds `STALWART_HEALTH_EMAIL`/`STALWART_HEALTH_PASSWORD` in `fullstacked.env`).

## JMAP scripting gotchas (Stalwart 0.16)

- **All registry set/get methods are namespaced `x:`**. Use `x:Account/set`, `x:Domain/set`, `x:DnsServer/set`, `x:AccountPassword/set`, etc. — NOT `Account/set`. Plain `Account/set` returns `unknownMethod`.
- `AccountPassword/set` only changes the **authenticated user's own** password (object id `singleton`); it returns `notFound` for any other account id. To set another user's password, patch the `Account` object's `credentials` property instead.
- `Account.credentials` is a **`Map<Id, Credential>`** (object keyed by credential id), NOT a list. Create form: `{"credentials":{"1":{"@type":"Password","secret":"<pw>"}}}`. A list value yields `invalidPatch: Invalid value for object property credentials`.
- `SecretKey` values serialize as `{"@type":"Value","secret":"..."}` (e.g. for `DnsServer/Cloudflare.secret`).
- Auth for JMAP/cli: `STALWART_URL=http://127.0.0.1:41209`, basic auth `admin@fullstacked.se` + admin password (from `/home/noor/.secrets/fullstacked.env`).
- The webadmin management API listens on `[::]:41209` (plain HTTP); Caddy exposes it publicly as `mail.fullstacked.se` (no SSO layer).

## Certificates

Strategy: **Stalwart built-in ACME. DNS-01 via Cloudflare is BROKEN since the 2026-09 DNS migration** (authority moved to HostUp; LE follows delegation, so CF-written `_acme-challenge` TXT is invisible). Cert `i31e2ujkabqa` expires 2026-11-14; renewal (~mid-Oct) WILL FAIL unless migrated. Do NOT rely on it silently — verify after any change with `scripts/mail-tls-check.sh` (cert age) and re-check before 2026-10-15.

- `AcmeProvider i31clpvcaaqa` (Let's Encrypt, `Dns01`) + `DnsServer/Cloudflare i31eq2yuaaqa` (legacy, keep until the new path renews once, then delete).
- **Migration path (chosen 2026-09-10): DNS-01 via DeSEC challenge delegation.** Stalwart has no HostUp provider and HostUp's API (126 MCP tools, checked) has no TSIG/RFC2136 primitive — only interactive HTTPS record CRUD, unusable at ACME machine speed. HTTP-01 is impossible (Caddy reserves `/.well-known/acme-challenge/*` for its own ACME — user routes for that path never fire, verified: 308 + `looking up info for HTTP challenge` in Caddy log); TLS-ALPN-01 needs port 443 which is Caddy's (stock Caddy terminates TLS itself; only a custom caddy-l4 build could forward `acme-tls/1` by ALPN — rejected as fragile). So: free DeSEC account → API token into `~/.secrets/fullstacked.env` as `DESEC_API_TOKEN` (user adds it by hand over ssh, never via chat) → `DnsServer/DeSEC` object in Stalwart → CNAME `_acme-challenge.<each SAN>` to the DeSEC-served name → LE follows the CNAME, Stalwart writes TXT via DeSEC. Then confirm one renewal, delete the Cloudflare `DnsServer` object.
- HostUp v2 ACME-relevant endpoints (read from lego's `hostup` provider source 2026-09-11; NOT usable by Stalwart, recorded for hook-script fallback only): base `https://cloud.hostup.se/api/v2`, `Authorization: Bearer <key>`; `GET /dns-zones?name=<zone>` → zone id; `POST /dns-zones/{id}/records` `{type:TXT,name,value,ttl}` → record id; `DELETE /dns-zones/{zoneID}/records/{recordID}`. Rejected paths: external lego (nixpkgs ships lego 4.35.2, provider needs 5.0.0 → source-build overlay required; plus cert-import-plus-restart glue per renewal), Stalwart-native driver (needs upstream Rust PR; no existing issue in stalwartlabs/stalwart as of 2026-09-11 — file one if pursuing).
- Default cert `i31e2ujkabqa` (Let's Encrypt YE1), SANs `fullstacked.se` + `mail.fullstacked.se`, renewed by Stalwart's `AcmeRenewal` task (next ~2026-10-15).
- **KNOWN GAP:** `mta-sts`/`autoconfig`/`autodiscover` are NOT in the cert SANs, and Caddy serves no route for those hosts — MTA-STS policy fetch fails for both reasons. To fix: add Caddy routes AND add the hostnames to the Domain's `certificateManagement` SANs with a renewal (after the DeSEC migration, so the renewal actually works).
- Cloudflare API token for (legacy) ACME: in `/home/noor/.secrets/fullstacked.env` (`CLOUDFLARE_API_TOKEN`).

## Cloudflare DNS → HostUp DNS (authority moved 2026-09)

Authoritative nameservers are now `primary`/`secondary.ns.hostup.se` (check `dig NS`). Manage via HostUp MCP (`https://cloud.hostup.se/mcp`, Bearer `HOSTUP_API_KEY`): `tools/call list_dns_records` (needs `id` in the JSON-RPC envelope; `recordType` filter 403s — list unfiltered and filter client-side) and `manage_dns_record` (create/update/delete, TXT content raw without quotes, TTL 300 matches zone convention). NOTE: HostUp MCP rejects python-urllib's User-Agent — use curl or set a browser UA.
The Cloudflare zone is STALE (kept for the ACME DNS-01 token only) but remains the backup copy of the TXT set — the 2026-09 migration dropped all 11 TXT records and they had to be re-created from Cloudflare values (SPF apex+mail, DMARC, MTA-STS, DKIM 2026a/2026b + v1-ed25519, TLSRPT x2, _hostup). Retired `v1-rsa` (423 chars, exceeds one TXT string) was intentionally NOT restored — rotation retired it. After any future DNS migration, run `scripts/mail-tls-check.sh` and diff TXT against this list.
All mail A records must be DNS-only (not proxied). API tokens in `/home/noor/.secrets/fullstacked.env` (`CLOUDFLARE_API_TOKEN`, `HOSTUP_API_KEY`).

DNS records: A (apex, mail), MX, SPF, Hostup auth TXT, DKIM TXT (2026a, 2026b), DMARC, MTA-STS policy TXT, TLSRPT TXT, SRV autoconfig records.

**SPF (managed manually in Cloudflare, not by Stalwart):** `v=spf1 mx include:spf.hostup.se -all`. Stalwart's automatic DNS management hardcodes `v=spf1 mx -all` (no relay include), so `dnsManagement` on domain `b` is set to **Manual** and we own the zone. Do NOT re-enable Automatic DNS management or Stalwart will overwrite this SPF.

Base records managed by script: `/home/noor/dev/fullstacked-nixlab/scripts/cloudflare-upsert-fullstacked-dns.sh`

### DNSSEC

Enabled on Cloudflare (status: pending). Hostup SmartDNSSEC should auto-push DS record to `.se` registry within 24h.

DS record values (if needed manually):
- Key Tag: 2371, Algorithm: 13 (ECDSA P-256 SHA-256), Digest Type: 2 (SHA-256)
- Digest: FB8E8A735BF52AAFDA2EAA8C763E27E0084A19F9316E3437CAC797FB0DA68289

## Tooling (openssl + dig + TLS check script)

`pkgs.openssl` and `pkgs.bind.dnsutils` are installed via `environment.systemPackages` in `modules/stalwart/default.nix` (added 2026-08-16, applied with `nixos-rebuild switch`). `jq` is NOT on the host — use `python3 -c 'import json,...'` for JSON parsing in shell.

TLS + DNS sanity check script: `scripts/mail-tls-check.sh` (no args; defaults to `fullstacked.se` / `mail.fullstacked.se` / `143.14.50.130`). Checks STARTTLS cert on 25, implicit-TLS on 465/993, 443; warns if cert < 14 days; verifies Cloudflare MX/SPF/DMARC/MTA-STS/autoconfig/autodiscover. Exits non-zero if any check FAILs. Run:

Service health check: `scripts/mail-health-check.sh` — asserts service active, listeners (exact `sport` filter), no recovery-mode journal errors, SMTP banner+EHLO, TLS handshakes, IMAP NOOP, HTTP surfaces, and delegates to `mail-tls-check.sh`. If `STALWART_HEALTH_EMAIL`/`STALWART_HEALTH_PASSWORD` are set in `fullstacked.env` it also runs authenticated IMAP LOGIN (:993) + SMTP AUTH PLAIN (:465) as `vcheck@fullstacked.se`; without them those probes WARN and skip (fail-open). Exit 1 on any FAIL.

```sh
/home/noor/dev/fullstacked-nixlab/scripts/mail-tls-check.sh
```

## Common Commands

```sh
systemctl status stalwart --no-pager
systemctl cat stalwart.service --no-pager          # get active --config= path
sudo journalctl -u stalwart --no-pager -n 50
ss -ltnp | grep -E ':(25|465|993|41209) '
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
systemctl --user status caddy --no-pager
/home/noor/dev/fullstacked-nixlab/scripts/mail-tls-check.sh
```

stalwart-cli (auth via `STALWART_URL` / `STALWART_USER` / `STALWART_PASSWORD`):

```sh
stalwart-cli get Domain b
stalwart-cli get Account c
stalwart-cli get MtaRoute i31fgvcqacaa
stalwart-cli get Certificate i31e2ujkabqa
```

Verify HTTP surfaces served by Stalwart (direct + via Caddy):

```sh
curl -sS http://127.0.0.1:41209/.well-known/jmap
curl -sSI https://mail.fullstacked.se/jmap/ | head -n 5
```

Caddy:

```sh
caddy validate --config /home/noor/.config/caddy/config.json
systemctl --user reload caddy
```

## Focused References

- [references/troubleshooting.md](references/troubleshooting.md) — common failure modes and fixes
- [references/certificates.md](references/certificates.md) — cert architecture, renewal, validation

## Current Status & Remaining Follow-ups

Stalwart 0.16.16 running and verified (DB config, built-in ACME):

- Stalwart active on 25/465/993 (TLS verified via `mail-tls-check.sh`) + HTTP/JMAP on `[::]:41209`, exposed as `mail.fullstacked.se` via Caddy.
- Let's Encrypt cert `i31e2ujkabqa` issued via ACME DNS-01; default cert set; renewal task scheduled.
- Cloudflare DNS published: MX, SPF (`v=spf1 mx include:spf.hostup.se -all`), DMARC (`p=reject`), MTA-STS policy TXT, DKIM `2026a`/`2026b`. `dnsManagement` = Manual (we own the zone).
- Hostup relay `i31fgvcqacaa` wired; `MtaOutboundStrategy` routes non-local → `hostup`. Connectivity to `relay.hostup.se:587` confirmed.
- Account `noor@fullstacked.se` (id `c`) created with password; IMAP login on 993 verified.
- **Inbound delivery works**: a message to `noor@fullstacked.se` from an unauthenticated sender is received and stored in `Junk Mail` (correct — no SPF/DKIM). Authenticated senders land in INBOX.
- `openssl` + `dig` installed via module; `scripts/mail-tls-check.sh` created.

Remaining (hardening + gaps):

1. **MTA-STS / autoconfig cert SANs — DONE in the Pangolin era (2026-08-16), SUPERSEDED 2026-09.** SANs were added and Traefik served them, but Pangolin is gone and Caddy serves no `mta-sts`/`autoconfig` route — policy over HTTPS is unserved again regardless of SANs. To restore: add Caddy routes first, then confirm SANs/renewal.
2. **Pangolin mta-sts/autoconfig resources — DONE in the Pangolin era (2026-08-16), MOOT now.** (Historical: a GLOBAL default TLS cert (minica self-signed) in `/opt/pangolin/config/traefik/dynamic_config.yml` shadowed on-demand ACME; removed, LE issued. `/opt/pangolin` deleted 2026-09 with the decommission.)
 3. **RESOLVED — mta-sts/autoconfig 502 (2026-08-16).** Root cause was an **auto IP ban, not the PROXY config**: Stalwart's fail2ban had `BlockedIp` `172.18.0.3` (Gerbil) with reason `portScanning` — Stalwart RSTs all connections from blocked IPs (TCP connects, full HTTP request ACKed, then RST, no response). It recurred because **external scanners hit the public Pangolin frontends (`mta-sts`/`autoconfig` are SSO-disabled), Traefik forwards their junk paths (e.g. `wp-login.php`, `.env`, `xmlrpc.php`) from Gerbil's IP `172.18.0.3`, and Stalwart bans its own reverse proxy** (`is_http_banned_path` → `block_ip(ip, PortScanning)` in `crates/common/src/network/security.rs`; the ban is created for the connection source = Gerbil). `SystemSettings.proxyTrustedNetworks = 172.18.0.0/16` had *masked* the first instance (proxy-trusted networks are auto-inserted into the allow-list), but it also forces PROXY-header reading — so the real durable fix is **not** proxy networks:
    - **Durable fix (applied, holds):** created a permanent `AllowedIp` object for `172.18.0.0/16` (`stalwart-cli create AllowedIp --field 'address=172.18.0.0/16' --field 'reason=...'`), which feeds `is_ip_allowed()` and bypasses ALL auto-bans (`is_http_banned_path`, `is_scanner_fail2banned`, `is_rcpt_fail2banned`, `is_auth_fail2banned`, `is_loiter_fail2banned`) — WITHOUT the PROXY-header side effect (PROXY reading is gated only on `proxy_networks`/`proxyTrustedNetworks` in `crates/common/src/network/listen.rs`, not on `AllowedIp`).
    - Also: `proxyTrustedNetworks = {}` stays cleared, `BlockedIp` `172.18.0.3` deleted, Stalwart restarted (in-memory ban state loads at startup; changes via JMAP `x:BlockedIp/set` are NOT hot-reloaded into the running server). Gerbil netns → `172.18.0.1:1080` verified OK, external `mta-sts`/`autoconfig` = `200`, `autodiscover`/`mail` = `302` (Pangolin SSO redirect, by design). Scanner-junk probe through the public frontends no longer re-bans Gerbil.
    **Diagnosis recipe for RST-with-no-response:** `tcpdump 'tcp port 1080'` → watch `[R.]` right after request ACK; then `x:BlockedIp/query` via JMAP (recovery admin `admin` + pw in `/etc/stalwart-admin.env`, root 600) to find the banned IP and its `createdAt`; correlate a fresh ban with the last public-frontend probe.
    **Also fixed same session:** `vpn.fullstacked.se` was `404` (pre-existing) because `/opt/pangolin/config/traefik/dynamic_config.yml` had been truncated at 11:59 — restored the `services` block (`next-service` → `http://pangolin:3002`, `api-service` → `http://pangolin:3000`) and `api-router`/`ws-router` from the `.bak.1786874365`, but **kept the `tls: certificates:` block REMOVED** (it pinned a stale self-signed minica cert that shadowed on-demand LE). Now `vpn.fullstacked.se` = `200` and mail SSO login target = `200`; LE certs verified on mail/mta-sts/autoconfig. Backup of the pre-cleanup file: `dynamic_config.yml.restore-tmp`.
    **Cleanup still due — MOOT:** Pangolin deleted 2026-09; no targets to prune.
4. **TEMP recovery env** — confirm `STALWART_RECOVERY_MODE` block is removed from `modules/stalwart/default.nix` (recovery admin at `/etc/stalwart-admin.env` may stay). Note `STALWART_RECOVERY_MODE_PORT=1080` IS still set (this is the recovery port, not the trigger).
5. **PTR/rDNS — DONE (2026-09-04).** `143.14.50.130 → mail.fullstacked.se` resolves (verified via 1.1.1.1). Note: Gmail still spam-foldered a fresh-domain test mail despite valid SPF/DKIM/DMARC+PTR — reputation warm-up needed (report-not-spam + real correspondence).
6. **DMARC** — currently `p=reject`. Keep monitoring reports before relying on it for third parties.
7. **MTA-STS enforce** — set `mode: enforce` (raise `max_age`) once the 502/recovery-mode incident is fixed and policy is live over HTTPS.
8. **DANE** — requires DNSSEC. Configure after DNSSEC is active.
9. **fail2ban** — add IMAP/SMTP-auth failure jail.
10. **IPv6** — host address `2a13:7c82:111:2d::/64` + gateway `2a13:7c82:111::1` assigned on `ens18` (NM "Wired connection 1", `ipv6.method manual`, persistent). `AAAA mail.fullstacked.se` published + resolves. Stalwart listeners already bind `[::]:25/465/993` (dual-stack, verified OPEN on v6). **Remaining:** set Hostup rDNS for `2a13:7c82:111:2d::` → `mail.fullstacked.se` (same panel field as IPv4).

## Self-Maintenance

Update this file after DNS changes, Stalwart config changes, Caddy route changes, TLS strategy changes, script changes, or NixOS module structure changes.

The live copy at `~/.config/opencode/skills/stalwart-caddy-nixos-cloudflare/SKILL.md` must match the repo copy at `.opencode/skills/stalwart-caddy-nixos-cloudflare/SKILL.md`. When you edit one, copy it over the other in the same commit.
Never store: API token values, sudo passwords, Stalwart admin passwords, mailbox passwords, TLS private key contents. Store paths and variable names instead.

Secrets location: `/home/noor/.secrets/fullstacked.env` (permissions: 600, parent: 700).
