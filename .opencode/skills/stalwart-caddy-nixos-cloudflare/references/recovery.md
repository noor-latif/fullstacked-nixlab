# New VPS recovery (honest answer)

**No — `git clone` + `apply` does not yield a working server.** The repo gives
reproducible *configuration*, not *state*.

Reproduced from clone: system packages/services, `noor` + SSH keys, firewall
+ module defaults, the `/etc/nixos` wrapper.

State to back up separately (proposed `scripts/backup-prod-state.sh` tarballs
`/var/lib/stalwart`, `/home/noor/.config/caddy/config.json`, `~/.hermes`
sans venv, nightly → B2 or similar — NOT built yet):

- `/var/lib/stalwart/` — rocksdb (mailboxes, principals, all config objects).
- `/home/noor/.config/caddy/config.json` — live Caddy config (NOT in git).
- `/home/noor/.secrets/fullstacked.env` — restore `chmod 700 ~/.secrets &&
  chmod 600 ~/.secrets/fullstacked.env`.
- `/etc/ssh/ssh_host_*` — fresh on new VPS; clean clients' `known_hosts`.

Order: provision (btrfs `/`,`/home`,`/nix`,swap) → bootstrap NixOS + `noor`
SSH → clone → `apply` → restore state → restart Stalwart, reload Caddy →
fix bridge-gateway IP if changed (`172.18.0.1` is Docker-assigned; check
`data/bridge-ports.json` consumers + Caddy upstreams) → point DNS at new IP
→ PTR/rDNS (SPF/DKIM unchanged) → reinstall Hermes (official install.sh,
restore `~/.hermes` sans venv, user-profile packages).
