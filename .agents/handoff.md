# Session Handoff — 2026-09-08 15:45 UTC

## Completed Work
- [x] **Caddy CalDAV & IPv6 Routing:** Added 301 permanent redirects for `/.well-known/caldav` and `/.well-known/carddav` to `/home/noor/.config/caddy/config.json` on NixLab, added `[2a13:7c82:111:2d::]:443` IPv6 listener, loaded `mail.fullstacked.se` TLS certificate, and reloaded Caddy via API (`127.0.0.1:2019/load`).
- [x] **iOS CalDAV Synchronization:** Verified native Apple Calendar and Apple Reminders sync with Stalwart account `noor@fullstacked.se`.
- [x] **Disaster Recovery / Snapper:** Configured Btrfs Snapper on laptop for `/home` with 12 hourly and 30 daily snapshots (`TIMELINE_LIMIT_DAILY="30"`), created initial baseline snapshot #1 (`baseline-safety-net`).
- [x] **Unified Life Assistant CLI:** Created `scripts/stalwart-assistant.py` (Python stdlib-only) combining JMAP email triage, draft, send, schedule, sieve with JMAP Calendar event management and CalDAV VTODO task management.
- [x] **Binary & PATH Integration:** Symlinked `stalwart-assistant` into `~/.local/bin/stalwart-assistant` on both laptop and NixLab.
- [x] **OMP Skill Minting:** Created managed skill `stalwart-assistant` at `managed-skills/stalwart-assistant/SKILL.md`.
- [x] **Git Synchronization:** Committed and pushed all changes to `main` at commit `e121703` on `noor-latif/fullstacked-nixlab`.

## Current State & Verification
- **Repository:** `/home/noor/dev/infra/fullstacked-nixlab`
- **Branch / Commit:** `main` at `e121703`
- **Working Tree:** Clean (zero untracked, zero modified files)
- **Tests & Build:** Passing (`stalwart-assistant summary` returns 0 with clean output on both laptop and NixLab)
- **Disaster Recovery:** Snapper config `home` active with active systemd timers `snapper-timeline.timer` and `snapper-cleanup.timer`.

## Immediate Next Steps (Actionable)
1. **Interactive Triage Testing with OMP** — Trigger OMP in terminal or at `omp.latif.se` with an unstructured brain dump (e.g. *"Schedule 1h curriculum review tomorrow at 2 PM and remind me to renew passport by Friday"*), verify events land in Apple Calendar and tasks land in Apple Reminders.
2. **Weekly Morning Review Prompt** — Define a recurring OMP trigger/alias (or shell alias `morning`) invoking `stalwart-assistant summary --json` and synthesizing a 3-point focus plan for the day.
3. **Pangolin Decommissioning — DONE 2026-09-10** — Containers already gone; removed `pangolin/` compose stack, `modules/traefik-watchdog`, renamed `pangolin-bridge` module/option/chain to `bridge-ports` (rules still load-bearing). Caddy (user service) is the reverse proxy. MTA-STS/autoconfig hosts currently unserved (no Caddy route) — re-add if wanted.

## Known Traps & Gotchas
- **Apple CalDAV 307 Rejection:** Apple iOS/macOS CalDAV setup rejects HTTP 307 Temporary Redirects on `/.well-known/caldav` with a cryptic *"CalDAV account verification failed"*. Caddy must return HTTP 301.
- **IPv6-First Handshake:** iPhones on cellular/Wi-Fi use Happy Eyeballs and prioritize IPv6 AAAA records. Caddy's public listener must explicitly listen on `[2a13:7c82:111:2d::]:443` as well as IPv4 `143.14.50.130:443`.
- **JMAP Tasks vs CalDAV VTODO:** Stalwart 0.16 supports `urn:ietf:params:jmap:calendars` natively for events, but does not yet implement the draft JMAP Tasks capability. Task/Reminder management is executed via CalDAV `VTODO` over HTTP PUT/REPORT/DELETE on `/dav/cal/noor%40fullstacked.se/default/`.
