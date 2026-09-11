# Host (nixlab)

- `noor` (docker, networkmanager, wheel) · NixOS · hostname `nixos` ·
  `143.14.50.130` · Europe/Stockholm. Repo `/home/noor/dev/fullstacked-nixlab`
  (`noor-latif/fullstacked-nixlab`), identity `noor latif <noor@latif.se>`.
- Repo = OS source of truth; `/etc/nixos` is a thin `path:`-flake wrapper, so
  plain `nixos-rebuild switch` resolves the repo. Apply: `cd` repo + `apply`
  (`scripts/apply-nixos.sh`) or `sudo nixos-rebuild switch --flake '.#nixos'`.
  Never commit env files, tokens, passwords, mailbox data, TLS keys.
- Sudo: `timestamp_type=global`, cached per-user 20 min. Cold cache ("a
  terminal is required") → user runs `sudo -v` in their own terminal.
- Nix rules: `nix.settings.*` lists need `lib.mkForce` (else merged/duplicated
  in nix.conf). `nix-command`+`flakes` forced on; verify with
  `nix show-config | head -3`.
- Hermes is user-space (`~/.hermes`, gateway unit, port 8642, lingering on) —
  NOT part of the flake. Never reintroduce `services.hermes-agent`/Cachix.
- `git push` breakage: per-URL credential helper in `~/.gitconfig` points at a
  gc'd `/nix/store/...gh...` path. Workaround: single-command `insteadOf`
  rewrite with token from `~/.config/gh/hosts.yml` (`oauth_token`). Real fix:
  reinstall `gh` via user profile, update helper path.
- Tooling: `openssl` + `dig` via `modules/stalwart`. No `jq` on host — parse
  JSON with `python3 -c 'import json,...'`.
