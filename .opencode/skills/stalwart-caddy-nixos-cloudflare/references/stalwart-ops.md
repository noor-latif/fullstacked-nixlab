# Stalwart operations (0.16)

All config lives in the RocksDB datastore (`/var/lib/stalwart/`, bootstrapped
by `/var/lib/stalwart/config.json` — storage bootstrap ONLY). Manage objects
via `stalwart-cli` / webadmin / JMAP, never by editing TOML.
`/etc/stalwart/stalwart.toml` is EMPTY/unused. Live `--config=` path:
`systemctl cat stalwart.service`. Nix module: `modules/stalwart/default.nix`
(`services.stalwartSetup` — never `services.stalwart-mail`: upstream redirects
that subtree).

## Connection

`source scripts/stalwart-env.sh` (exports `STALWART_URL=http://127.0.0.1:41209`
+ admin user/password from `~/.secrets/fullstacked.env`). All admin runs ON
NIXLAB over ssh. Resolve IDs at runtime (`stalwart-cli query domain`,
`stalwart-cli query account`) — never hardcode object ids; `b`/`c`/`f` below
are last-seen hints, not constants.

## Listeners (verified `ss -ltnp`)

`25` SMTP · `465` submissions implicit-TLS · `993` IMAPS implicit-TLS ·
`[::]:41209` HTTP webadmin+JMAP (plaintext, Caddy-exposed as
`mail.fullstacked.se`). Keep mail protocols direct: no STARTTLS on 587.
TLS via `server.tls.certificate = "default"` + `%{file:...}%` macro;
`certificate.*`/`server.tls.*` must be in `config.local-keys`.

## Config highlights (DB objects)

- Domain `fullstacked.se`: `dnsManagement` Manual, `certificateManagement`
  Automatic → `AcmeProvider`, `dkimManagement` Automatic (selectors
  `2026a`/`2026b`).
- `MtaRoute/Relay`: Hostup `relay.hostup.se:587`, STARTTLS (`implicitTls: false`).
- `MtaOutboundStrategy`: local-domain → `local`, else → `hostup` relay.
- Health account `vcheck@fullstacked.se` (auth probes only).

## JMAP gotchas (0.16)

- Registry methods are `x:`-namespaced (`x:Account/set`, `x:DnsServer/set`…).
  Plain `Account/set` → `unknownMethod`.
- `AccountPassword/set` only touches the caller's own password (`singleton`).
  For others, patch `Account.credentials`.
- `Account.credentials` is a `Map<Id, Credential>`, not a list.
- `SecretKey` serializes as `{"@type":"Value","secret":"..."}`.

## Recovery mode (CRITICAL)

`STALWART_RECOVERY_MODE_PORT=1080` is set (port, not trigger). If the datastore
fails to load, Stalwart serves ONLY `[::]:1080` (`http-recovery`) — **mail
protocols die too**. Detect: journal shows `http-recovery` / config-load
errors; only `1080` listens. Common trigger: malformed object edit (bad SAN,
cert ref, broken ACME object). Fix via recovery web UI on `1080` or
`stalwart-cli`, then restart. Note: ban/property changes via JMAP are NOT
hot-reloaded — restart after listener-affecting edits.

## Diagnostics gotchas

- `tcpdump` captures NOTHING on this host — use `curl`, not packet capture.
- Source-IP silent close = PROXY-protocol mismatch: a listener with non-empty
  `proxy_networks` (from `SystemSettings.proxyTrustedNetworks`) RSTs sources
  that send no PROXY header. Keep `proxyTrustedNetworks = {}`; the permanent
  `AllowedIp 172.18.0.0/16` bypasses auto-bans without that side effect.
- HTTP probe: `curl -sS http://127.0.0.1:41209/.well-known/jmap`. Refused + mail
  up = HTTP listener regressed. `25/465/993` down + only `1080` = recovery mode.
- Caddy: binary `/home/noor/.nix-profile/bin/caddy`, live config
  `/home/noor/.config/caddy/config.json` (NOT in git — back up before edits);
  `caddy validate` then `systemctl --user reload caddy`. Serves
  `mail.fullstacked.se` → `127.0.0.1:41209`; apex → static 404;
  `mta-sts`/`autoconfig` unserved (no route).
