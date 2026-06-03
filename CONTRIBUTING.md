# Contributing

## Commit Style

Use Conventional Commits:

```text
<type>[optional scope]: <description>

[optional body]
```

Preferred types for this repo:

- `feat`: user-visible infrastructure capability
- `fix`: correction to broken or unsafe behavior
- `docs`: documentation-only changes
- `chore`: maintenance, snapshots, repo hygiene
- `refactor`: restructuring without behavior change

Keep each commit as one logical changeset. Use the body to explain why the
change exists and any migration or deploy notes.

Examples:

```text
chore(nixos): track mail server baseline

Capture the current NixOS and Pangolin configuration so the VPS can be
rebuilt from git without committing runtime secrets.
```

```text
fix(dns): preserve unrelated apex TXT records

Update the Cloudflare helper to match SPF records by TXT content prefix before
updating, avoiding accidental replacement of verification records.
```
