---
name: stalwart-caddy-nixos-cloudflare
description: Operate the Stalwart mail stack for fullstacked.se on nixlab: mail server objects, Caddy proxy, DeSEC/HostUp DNS, ACME certs, NixOS modules. Triggers on Stalwart, mail server, mail.fullstacked.se, MTA-STS, autoconfig, DKIM, DMARC, Caddy, DeSEC, HostUp DNS, fullstacked-nixlab. Do NOT use for mailbox creation (stalwart-mailbox-admin), mail reading/triage (stalwart-assistant), or general coding.
metadata:
  version: "2.0.0"
  rewritten: "2026-09-11"
compatibility: "nixlab ssh, Stalwart 0.16, DeSEC + HostUp APIs"
---

# Stalwart + Caddy + NixOS + DeSEC

Noor's mail setup: domain `fullstacked.se`, MX `mail.fullstacked.se`,
NixOS flake at `/home/noor/dev/fullstacked-nixlab`, Stalwart 0.16 via
`services.stalwartSetup`, Caddy user unit as proxy, DeSEC authoritative DNS.

Do not store or repeat secrets. They live in `/home/noor/.secrets/fullstacked.env`
(nixlab, 600); source that file, never ask, never print values.

## Scripts (black boxes — run with --help, don't read source)

All admin runs ON NIXLAB over ssh. Prefer these over hand-built commands:

- `scripts/stalwart-env.sh` — `source` it for `STALWART_URL/USER/PASSWORD`
  (admin). Refuses bare execution so secrets never hit logs.
- `scripts/hostup-mcp.sh <tool> ['<json-args>']` — HostUp MCP without
  hand-building envelopes. `list_dns_records '{"zone":"fullstacked.se"}'`.
- `scripts/desec-api.sh <METHOD> <path> [json-body]` — DeSEC v1 API.
  `GET /domains/` to verify token + zones.
- `scripts/mail-health-check.sh` — full service health (listeners, TLS,
  IMAP/SMTP auth as vcheck, HTTP surfaces). Exit 1 on any FAIL.
- `scripts/mail-tls-check.sh` — cert age + DNS sanity. Warns <14 days.
- `scripts/desec-delegation-watch.py` — migration watcher (state in
  `~/.cache/desec-watch.json`, mails on change). See `references/dns.md`.
- `scripts/stalwart-mailbox.sh` — mailbox admin (see stalwart-mailbox-admin).

## Operating rules

- Research official docs or local schemas before fixing unclear behavior;
  never guess API shapes. Read Stalwart's source when docs are silent
  (ACME: `order.rs`; DNS drivers: `dns-update` crate).
- Caddy config is live-only (`/home/noor/.config/caddy/config.json`, NOT in
  git): back up, `caddy validate`, then `systemctl --user reload caddy`.
- Track reproducible changes in git; small commits per logical change.
- Mail ports stay direct (25/465/993); no STARTTLS on 587.
- `dnsManagement` stays Manual (Stalwart's auto-SPF drops the relay include).
- Never edit the Nix store, `/etc/stalwart/stalwart.toml` (empty), or the
  stale Cloudflare zone (guard: `ALLOW_STALE_CF=1`).
- After listener-affecting Stalwart edits: restart (not hot-reloaded).

## Verify before done

End every change with its gate — never claim done without the output:

- Service edits → `scripts/mail-health-check.sh`
- TLS/DNS edits → `scripts/mail-tls-check.sh`
- DNS migration steps → `dig` against both authorities + public resolver
- NixOS edits → `apply` succeeds, service active, health script green

## Live state (volatile — query, don't memorize)

Object ids, cert expiry, delegation status change. Resolve at runtime
(`stalwart-cli query domain|account`, `dig NS/DS`). Current migration state:
`references/certificates.md` + `references/dns.md`; watcher state:
`~/.cache/desec-watch.json` on nixlab.

## Focused references (read the one matching the task)

- [references/stalwart-ops.md](references/stalwart-ops.md) — listeners, DB
  objects, JMAP gotchas, recovery mode, diagnostics.
- [references/certificates.md](references/certificates.md) — ACME strategy,
  migration log, rejected paths.
- [references/dns.md](references/dns.md) — DNS history, record conventions,
  DNSSEC, MCP usage.
- [references/host.md](references/host.md) — machine, sudo, git, nix rules,
  Hermes, gh fix.
- [references/recovery.md](references/recovery.md) — new-VPS rebuild limits.
- [references/history.md](references/history.md) — marked past incidents,
  standing follow-ups. Not actionable.

## Self-maintenance

Update skill + scripts after DNS, Stalwart, Caddy, TLS, or module changes.
Keep the live copy `~/.config/opencode/skills/stalwart-caddy-nixos-cloudflare/SKILL.md`
identical (copy after every edit). Never store secret values — paths and
variable names only.
