# Session Handoff — 2026-09-11 (proxy cutover)

## Completed Work
- [x] `laptop.latif.se` now proxied by NixLab Caddy (`subscale up laptop.latif.se 100.112.233.33:8787`); deleted its last explicit A+AAAA. DNS is 100% wildcard for private names.
- [x] Laptop de-elevated: removed local Caddy `:443`/SNI + `/var/lib/caddy/certs`; tailnet hostname served by new user unit `tailscale-serve.service` (foreground-`serve` quirk, `Restart=always`).
- [x] Earlier: retired `omp.latif.se`, fixed `baytdev` 404, removed redundant cv/cv-api/vault/baytdev records, UA-patched `lego-hostup-hook.py`.
- [x] Managed skill `tailnet-private-routing` rewritten to proxy design + serve quirk + don'ts.

## Current State & Verification
- `curl`: laptop/login 200/15K (via NixLab proxy), nixlab 200/11K, tailnet hostname 200/65K, cv/vault/blogg 200, baytdev 307, cv-api 404-normal.
- `tailscale serve status` reports nothing (build quirk) — traffic-proven serving; the systemd unit is source of truth.
- `/tmp/fullstacked-nixlab` working tree: dirty (this handoff file only).

## Immediate Next Steps (Actionable)
1. **Renewal debts GONE** (no laptop cert copies left). Remaining: NixLab LE wildcard auto-renews via lego timer (hook UA-patched).
2. If NixLab goes down, `laptop.latif.se` dies with it (accepted tradeoff) — direct-serving rollback = re-add explicit DNS + local Caddy SNI (see skill history).

## Known Traps & Gotchas
- `tailscale serve` foreground quirk (see skill). Never run load-bearing serve from a shell.
- HostUp MCP needs browser User-Agent; Caddy `200 0` = routeless; tiny 404 = public-listener hit.
