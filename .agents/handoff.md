# Session Handoff — 2026-09-11

## Completed Work
- [x] Revived `nixlab.latif.se` + `laptop.latif.se` (were blank `200 0`: resolving but routeless) via `subscale up <name> 8787` on NixLab.
- [x] Retired `omp.latif.se`: `subscale down`, deleted HostUp A+AAAA. `nixlab.latif.se` is its replacement (same backend).
- [x] Moved `laptop.latif.se` onto the laptop: explicit HostUp A+AAAA → `100.112.233.33`/`fd7a:115c:a1e0::2b2f:e922`; local Caddy owns `:443` on TS IPs with SNI (`laptop` → ompweb `:8787`, tailnet name → devproxy `:30180`); `tailscale serve --https=443` off; sysctl unprivileged ports persisted.
- [x] Fixed `baytdev.latif.se` (public-IP 404 → repointed to tailnet, now 307).
- [x] Deleted redundant explicit records (cv/cv-api/vault/baytdev): wildcard covers them. Verified all endpoints.
- [x] Patched NixLab `lego-hostup-hook.py` with browser User-Agent (Cloudflare 1010 was 403ing it).
- [x] Minted managed skill `tailnet-private-routing` with the full runbook.

## Current State & Verification
- `curl`: cv 200/120K, vault 200/23K, blogg 200/23K, baytdev 307, nixlab 200/11K, laptop `/login` 200/15K, cv-api 404-normal, omp blank-200 (retired).
- Working tree (`/tmp/fullstacked-nixlab`): clean (docs/handoff only, no code changes).

## Immediate Next Steps (Actionable)
1. **Laptop wildcard cert expires 2026-12-07** — re-sync `/var/lib/caddy/certs/wildcard.*` on latif from NixLab `/home/noor/.secrets/certs/lego/certificates/` (or automate).
2. **Laptop `tailscale cert` (~90d)** — re-issue for `latif.rohu-mirach.ts.net` into `/var/lib/caddy/certs/ts.*` (caddy-owned), reload Caddy via `:2019`.
3. **Do NOT re-add explicit DNS** for NixLab-bound names or AAAA for `cv-api` — wildcard covers; see skill.

## Known Traps & Gotchas
- HostUp MCP 403/1010 = missing browser User-Agent (urllib default blocked). Every caller must set one.
- Caddy `200 0` = resolvable but routeless; tiny 404 = DNS hitting the public listener. Diagnose in that order.
