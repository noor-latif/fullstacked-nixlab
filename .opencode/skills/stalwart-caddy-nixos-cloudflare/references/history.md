# History (marked; live docs above — do not act on this)

## Pangolin era (decommissioned 2026-09)

Pangolin/Traefik/Gerbil fronted Stalwart; `/opt/pangolin` deleted, no
pangolin/gerbil/traefik containers run. `bridge-ports` module/chain is the
renamed survivor (still load-bearing for bridge container traffic).

- 2026-08-16 auto-ban incident: external scanner junk via public frontends got
  Gerbil's IP fail2ban'd (`portScanning`), Stalwart RST'd its own proxy.
  Durable fix: permanent `AllowedIp 172.18.0.0/16` + cleared
  `proxyTrustedNetworks`. Recipe for RST-with-no-response: correlate
  `BlockedIp.createdAt` with last public-frontend probe.
- Same session: truncated Traefik `dynamic_config.yml` restored from backup
  (minus the stale minica `tls.certificates` block); minica self-signed cert
  era ended with LE issuance. `/var/lib/acme/` (minica + empty lego state)
  deleted 2026-09-10, backup `~/backups/orphaned-20260910/`.
- `vpn.fullstacked.se` was a Pangolin route; deleted with the stack.

## DNS migrations

- 2026-09-09: Cloudflare → HostUp authority. Migration dropped all TXT
  records; restored from Cloudflare values (retired `v1-rsa` skipped).
  Stale Oracle apex A + `vpn` A/AAAA deleted.
- 2026-09-11: HostUp → DeSEC authority (Stalwart has no HostUp provider, no
  TSIG; delegation-to-child-zone disproved in Stalwart source). Zonefile
  `/home/noor/fullstacked.se.zone`. Delegation accepted via MCP; watcher
  `desec-watch.timer` mailed transitions.
- HostUp position (their KB + agent, 2026-09-11): hooks are the house answer
  (acme.sh plugin merged upstream; tickets #763670/#386405). No TSIG endpoint.
  Feedback filed (TSIG-or-driver + DNS-move follow-up). Upstream
  `stalwartlabs/stalwart#3310` (HostUp provider) auto-closed by bot — must go
  via support.stalw.art triage; re-post draft lives in session history.

## Standing follow-ups (verify before acting — may be done)

MTA-STS/autoconfig SANs+routes · DMARC monitoring · MTA-STS enforce ·
DANE (needs DNSSEC) · IMAP/SMTP-auth fail2ban jail · IPv6 rDNS
(`2a13:7c82:111:2d::`) · `backup-prod-state.sh` · passphrase-encrypted token
bootstrap · `gh` credential-helper reinstall.
