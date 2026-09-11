# DNS (DeSEC authoritative since 2026-09-11)

History: Cloudflare (to 2026-09) → HostUp `primary`/`secondary.ns.hostup.se`
(2026-09-09…11) → **DeSEC `ns1.desec.io`/`ns2.desec.org`** (delegation accepted
2026-09-11, propagation in flight — check `dig NS fullstacked.se`).
Registrar for `fullstacked.se` is Hostup AB (also the VPS provider).

## Managing records

- DeSEC zone: dashboard, or `scripts/desec-api.sh` (Token auth from
  `~/.secrets/fullstacked.env` as `DESEC_API_TOKEN`, nixlab).
- Import source of truth: `/home/noor/fullstacked.se.zone` (31 live records
  exported 2026-09-11: 5 A, 1 AAAA, 4 CNAME, 1 MX, 7 SRV, 10 TXT; SOA+apex NS
  omitted; TTL unified 3600 = DeSEC floor; retired `v1-rsa` DKIM intentionally
  absent).
- `dnsManagement` on the Stalwart Domain is currently **Automatic** against the
  Cloudflare `DnsServer` (writes land in the stale zone — live-safe, renewal
  broken). At the DeSEC cutover, point the Domain at the DeSEC object AND
  decide Manual vs Automatic: verify first whether Automatic would overwrite
  the relay-include SPF (`v=spf1 mx include:spf.hostup.se -all`) — do not
  assume. See `certificates.md`.
  (`https://cloud.hostup.se/mcp`, Bearer `HOSTUP_API_KEY`) via
  `scripts/hostup-mcp.sh` — e.g. `hostup-mcp.sh list_dns_records
  '{"zone":"fullstacked.se"}'`. Envelope REQUIRES `id`; `recordType` filter
  403s (list unfiltered, filter client-side); TXTs raw without quotes.
- Cloudflare zone is STALE — never edit there. Guard script
  `scripts/cloudflare-upsert-fullstacked-dns.sh` aborts without `ALLOW_STALE_CF=1`.

## Record conventions

- All mail A records DNS-only (never proxied / orange-cloud).
- `dnsManagement` on the Stalwart Domain stays **Manual** — Stalwart's
  automatic DNS hardcodes `v=spf1 mx -all` (no relay include). We own SPF:
  `v=spf1 mx include:spf.hostup.se -all`. Do NOT re-enable Automatic.
- After any future DNS migration: run `scripts/mail-tls-check.sh` and diff TXT
  against the zonefile (SPF×2, DMARC, MTA-STS, DKIM 2026a/2026b + ed25519,
  TLSRPT×2, `_hostup`).

## DNSSEC

- `.se` parent had signed delegation (HostUp SmartDNSSEC). On NS change the old
  DS auto-removes (KB #832118); SmartDNSSEC Sync re-adds the new DS after a
  mandatory ~24h block (KB #958624, DeSEC coverage unconfirmed).
- DeSEC DS fallback (paste in HostUp portal Settings → DNSSEC if Sync hasn't
  acted in 48h): tag `56980`, alg `13`, digest-type `2`, digest
  `3e698f3f65d249b336fa66c6a84a216c7aca0b344127686b1f507b4d84c3944d`.
- Verify: `dig DS fullstacked.se`, Zonemaster (`zonemaster.se`), DNSSEC Analyzer.
- Watcher while migrating: `scripts/desec-delegation-watch.py` + user timer
  `desec-watch.timer` (6h × 48h, mails on NS flip / DS back / SUCCESS / FAIL).
