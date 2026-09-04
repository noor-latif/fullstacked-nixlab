# Gotaland migration — Stalwart mailbox + HostUp DNS — 2026-08-29 (updated 2026-08-30)

For nixlab operator. See also wp-gotaland workspace doc: `gotalandstrafikskola-wp/.opencode/skills/gotalandstrafikskola-wp-ops/reference/stalwart-hostup-migration-2026-08-29.md`

## What was done (2026-08-29 → 2026-08-30)

- Created `noor@gotalandstrafikskola.se` (Account j) on Stalwart 0.16.17 via `stalwart-cli` (172.18.0.1:1080) with locale sv_SE, pass n00rzaff!GOT, verified IMAP 993 + SMTP 465.
- Updated password from random T7lr... to provided n00rzaff!GOT via `stalwart-cli update account j --field credentials=...`.
- Migrated HostUp DNS gotalandstrafikskola.se (zone_06f6vfm22y...) from Zoho (3 MX, CNAME mail, Zoho TXT/DKIM) to Stalwart: 1 MX mail.fullstacked.se, SPF v=spf1 mx -all → v=spf1 mx ip4:95.141.241.143 include:spf.hostup.se -all (added relay IP 95.141.241.143 for Postfix SPF pass, drr_06f8w6y2acj6yrhwmsvm6hqky0), DMARC, 6 SRVs, 3 CNAMEs + 3 TXTs (mta-sts/autoconfig). Kept DKIM v1-* and google-site-verification. 18→27 records.
- Created `hej@gotalandstrafikskola.se` (k) `2026-08-30`, moved `info` alias `wordpress (h) -> hej (k)` via `stalwart-mailbox.sh move-alias`, wired `FluentSMTP` on wp-gotaland to `hej@` `mail.fullstacked.se:465 SSL` via `migration/fluent-wire.sh`.

## How to repeat faster

```bash
# 1. Tailscale (both directions)
tailscale ping nixlab || (add grant wp-gotaland→nixlab in https://login.tailscale.com/admin/acls)
tailscale ping wp-gotaland || (add grant nixlab→wp-gotaland)
ssh-keyscan wp-gotaland >> ~/.ssh/known_hosts; ssh-keyscan nixlab >> ~/.ssh/known_hosts

# 2. Stalwart
export STALWART_URL='http://172.18.0.1:1080' STALWART_USER='admin@fullstacked.se' STALWART_PASSWORD=$(grep STALWART_ADMIN_PASSWORD ~/.secrets/fullstacked.env | cut -d= -f2)
stalwart-cli query domain; stalwart-cli get domain c  # desired zone
stalwart-cli query account

# create (see wp-gotaland doc for full flags) — credentials as map "0": {"@type":"Password","secret":$PASS}
stalwart-cli create Account/User --field name=noor --field domainId=c --field locale=sv_SE --field 'credentials={"0":{"@type":"Password","secret":"$PASS"}}' ...

# alias ops (now functional, handles #domain- norm)
~/dev/fullstacked-nixlab/scripts/stalwart-mailbox.sh add-alias --email hej@gotalandstrafikskola.se --alias info
~/dev/fullstacked-nixlab/scripts/stalwart-mailbox.sh move-alias --from wordpress@gotalandstrafikskola.se --to hej@gotalandstrafikskola.se --alias info

# 3. HostUp
export HOSTUP_API_KEY=$(grep HOSTUP_API_KEY ~/.secrets/hostup.env | cut -d= -f2)
curl -H "Authorization: Bearer $HOSTUP_API_KEY" -X POST https://cloud.hostup.se/mcp --data '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"list_dns_records","arguments":{"zone":"gotalandstrafikskola.se"}}}'
# then manage_dns_record deletes/creates as in wp-gotaland doc — SPF now ip4:95..., _hostup comma-separated

# 4. Fluent (from nixlab via ssh)
ssh wp-gotaland ~/gotalandstrafikskola-wp/migration/fluent-wire.sh --email hej@gotalandstrafikskola.se
```

## Secrets

- `~/.secrets/hostup.env` (HOSTUP_API_KEY + ID apikey_06g1j...), also appended to `fullstacked.env`
- `~/.secrets/noor-gotalandstrafikskola.env` (noor mailbox), `hej-gotalandstrafikskola.env` (hej, 62433dab...), `wordpress-gotaland.env`
- `~/.secrets/fullstacked.env` (admin, Cloudflare, Pangolin, HOSTUP_API_KEY)

## Gotchas (updated 2026-08-30)

- JMAP maps not arrays, 172.18.0.1 not /api, need snapshot Account+Domain --allow-unresolved Tenant... for aliases (handles #domain- → c).
- SPF `v=spf1 mx ip4:95.141.241.143 include:spf.hostup.se -all` — `ip4:95...` is `relay.hostup.se` for Postfix SPF pass (was `mx include` → Postfix spf=fail → Gmail isn't authenticated). Stalwart signs DKIM so SPF fail still dmarc=pass via DKIM, but Postfix needs SPF. Keep mx + ip4 + include.
- `_hostup` is MailChannels Domain Lockdown for `relay.hostup.se`: `v=mc1 auth=h_MTM2..._043ea...,143.14.50.130` comma-separated (was single h_MTM2... only wp-gotaland 136... → Stalwart on nixlab 143... got 554 Domain is locked. Only 136...; fixed 2026-08-30 drr_06g52aytn7r1dbc91ztym8f1x4). Test via `python SMTP relay.hostup.se:587 MAIL FROM` from nixlab should be 250 Ok (was 554).
- HostUp DNS TTL 600, no confirmation for DNS (unlike VPS), live on primary.ns.hostup.se 198.41.222.135 immediately, cached old ≤10 min on 8.8.8.8/Google. Wait 10 min then `host -t TXT gotalandstrafikskola.se 8.8.8.8` and `host -t TXT _hostup... 8.8.8.8` should show new.
- Postfix on wp-gotaland never DKIM-signs — only Stalwart signs (v1-rsa/ed25519). WordPress via Fluent hej@ is therefore always DKIM authenticated; Postfix via relay relies on SPF. `sendmail` without To: header gives empty To: → spam signal — use full headers: `printf "From: ...\nTo: ...\nSubject: ...\nDate: $(date -R)\n\nbody\n" | sendmail -t`.
- `stalwart-mailbox.sh` now has `add-alias`/`remove-alias`/`move-alias`/`check-mail` (IMAP peek) — use instead of manual `stalwart-cli update` with maps. `stalwart-remote.sh` on wp-gotaland fixed `printf %q` quoting for passwords with spaces. `fluent-wire.sh` validates IMAP+SMTP pre-check and uses php var for From: (avoids .hej invalid).
- Hermes skill `~/.hermes/skills/devops/gotalandstrafikskola-mail-ops/SKILL.md` (enabled) teaches same helpers; `hermes skills list` shows `gotalandstrafikskol…`.

## Postfix on wp-gotaland (136.148.208.139) + nixlab relay (143.14.50.130) — 2026-08-30

- HostUp DNS _hostup `v=mc1 auth=h_MTM2..._043ea...,143.14.50.130` (comma-separated, 600, drr_06g52...) + SPF `v=spf1 mx ip4:95... include...` (600, drr_06f8w6...), Postfix `relayhost = [relay.hostup.se]:587`, `myhostname gotalandstrafikskola.se`, loopback-only.
- Tested via `sendmail -t` with proper headers → `relay.hostup.se[95...]:587` `250 2.0.0 Ok: queued as ...` → Gmail `spf=pass` (after TTL) + `Stalwart` `dkim=pass` → no Be careful. `Postfix` alone `spf=pass` (no DKIM) → dmarc=pass via SPF.
- Stalwart `hej@` via `mail.fullstacked.se:465` → `relay.hostup.se` → Gmail `spf=pass` + `dkim=pass` (`signed-by gotalandstrafikskola.se`) → always authenticated.

## Helper scripts

- `~/dev/fullstacked-nixlab/scripts/stalwart-mailbox.sh` — main helper (see --help). Wrapper for stalwart-cli with domainId lookup, MAPS fix, alias Domain Lockdown, check-mail.
- On wp-gotaland: `migration/stalwart-remote.sh` (SSH wrapper, fixed quoting) + `migration/hostup-mail-dns.sh` + `migration/fluent-wire.sh` + `migration/check-mail.sh` + `migration/README-MAIL-HELPERS.md`
