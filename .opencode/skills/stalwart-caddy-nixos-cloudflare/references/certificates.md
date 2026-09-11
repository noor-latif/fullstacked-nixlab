# Certificates (Stalwart built-in ACME, DNS-01)

Strategy: **Stalwart built-in ACME, DNS-01 via DeSEC** (authoritative since
the 2026-09-11 migration; see `dns.md`). Renewals are Stalwart's `AcmeRenewal`
task — no external client, no hooks, no restarts.

- `AcmeProvider i31clpvcaaqa` (Let's Encrypt, `Dns01`).
- `DnsServer/Cloudflare i31eq2yuaaqa` — LEGACY. Was the challenge writer while
  Cloudflare held a (stale) zone. Delete after the DeSEC path renews once.
- Default cert `i31e2ujkabqa` (Let's Encrypt YE1), SANs `fullstacked.se` +
  `mail.fullstacked.se`, expiry 2026-11-14, renewal ~mid-Oct.
- `SecretKey` values serialize as `{"@type":"Value","secret":"..."}`.

## Why DeSEC (decided 2026-09-10/11, evidence in skill history)

- Stalwart has no HostUp provider and HostUp's nameservers take no TSIG —
  closed `DnsServer` roster, no generic REST/hook.
- HTTP-01 impossible (Caddy reserves `/.well-known/acme-challenge/*` for its
  own ACME — verified 308); TLS-ALPN-01 needs port 443, which is Caddy's.
- CNAME-delegation to a DeSEC child zone is IMPOSSIBLE — verified in Stalwart
  source: `order.rs` writes `_acme-challenge.<domain>` literally, and
  `dns-update/desec.rs` `discover_domain` only walks UP to parent zones.
  DeSEC must be authoritative. No exceptions.
- Rejected: external lego (nixpkgs ships 4.x, `hostup` provider needs 5.0.0;
  plus cert-import-plus-restart glue per renewal), Stalwart-native HostUp
  driver (upstream issue `stalwartlabs/stalwart#3310`, filed 2026-09-11).

## Verify after any change

`scripts/mail-tls-check.sh` (cert age; warns <14 days). Re-check before expiry.

## Known gap

`mta-sts`/`autoconfig`/`autodiscover` are NOT in the cert SANs, and Caddy
serves no route for those hosts. To fix: add Caddy routes AND add the hostnames
to the Domain's `certificateManagement` SANs with a renewal (only after the
DeSEC path works, so the renewal actually succeeds).
