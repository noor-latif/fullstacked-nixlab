# Session Handoff — 2026-09-12 (final)

## Completed Work
- [x] `laptop.latif.se` proxied by NixLab Caddy → `latif:8787` (MagicDNS short-name; survives reinstalls). DNS 100% wildcard for private names.
- [x] Laptop de-elevated: local Caddy `:443`/SNI + `/var/lib/caddy/certs` removed; `tailscale-serve.service` (user unit, `Restart=always`) serves tailnet hostname → devproxy `:30180`.
- [x] Deleted placeholder CNAME `nizam-beta.latif.se → fallback.here.now` (now wildcard blank-200).
- [x] Scrubbed baked-in `HOSTUP_API_KEY` default from NixLab `lego-hostup-hook.py` (fails closed; unit injects env); UA patch intact, compiles.
- [x] Independent `TailnetAudit` subagent: 11/11 endpoints pass, DNS zero-straggler, units/listeners clean.
- [x] Managed skill `tailnet-private-routing` current (proxy design, short-names, serve quirk, don'ts). Scratch `/tmp/*.html`, keys shredded.

## Current State & Verification
- `curl` (tailnet): laptop/login 200/15K, nixlab 200/11K, tailnet name 200/65K, cv 200/120K, vault/blogg 200/23K, baytdev 307, cv-api 404-normal, omp + nizam blank-200 (retired, wildcard-caught).
- `/tmp/fullstacked-nixlab` tree clean (`.agents/handoff.md` gitignored by design). No code changes anywhere. No stray jobs.

## Immediate Next Steps (Actionable, user undecided)
1. **Renewal dry-run** — run NixLab `lego-hostup-hook.py present _acme-test.latif.se <dummy>` → confirm TXT via `list_dns_records` → `cleanup`. Proves December renewal path untouched-cert.
2. **Dead-backend watchdog** — `subscale list` UP ≠ app alive (every recent outage looked UP). Proposed: NixLab timer curling each endpoint's expected code+size, alert on mismatch.

## Known Traps & Gotchas
- `tailscale serve` foreground quirk (1.102.x): shell runs die with shell; `serve status` may lie; unit is truth.
- HostUp MCP needs browser User-Agent; Caddy `200 0` = routeless; tiny 404 = public-listener hit.
- Retired names under wildcard blank-200 forever — routeless IS the dead state.
