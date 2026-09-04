# Email assistant MVP — operations (2026-09-04)

Tailnet-only JMAP assistant. No containers, no public surface, no n8n.
One stdlib Python script + one systemd user timer. Auth as
`admin@fullstacked.se` (creds in `~/.secrets/fullstacked.env`, never in git),
operates on `noor@fullstacked.se` (JMAP account `c`) via cross-account access.

## Paths

- `scripts/email-assistant.py` — the assistant (triage/draft/send/schedule/cancel)
- Live timer: `~/.config/systemd/user/email-assistant-triage.{service,timer}`
- Triage log: `~/email-assistant-triage.log`

## Usage (on nixlab)

```sh
python3 scripts/email-assistant.py triage                                     # unread/total per mailbox, accounts c + b
python3 scripts/email-assistant.py draft                                      # create+destroy draft proof in c
python3 scripts/email-assistant.py send                                       # admin self-mail proof
python3 scripts/email-assistant.py schedule <to> <minutes> <subject> <text>   # native future release (RFC 4865 HOLDUNTIL)
python3 scripts/email-assistant.py cancel <submission-id> [account]           # undoStatus=canceled
```

## Scheduling mechanism

Stalwart advertises `maxDelayedSend: 2592000` + `FUTURERELEASE`.
`sendAt` on `EmailSubmission/set` is server-set and rejected client-side;
future release is requested via `envelope.mailFrom.parameters.HOLDUNTIL`.
Verified: +2min send released on time with correct From. Cancel via
`EmailSubmission/set update {id: {undoStatus: canceled}}`.

## Timer install (already active; reproduce with)

```ini
# ~/.config/systemd/user/email-assistant-triage.service
[Unit]
Description=MVP email triage (JMAP read-only summary)
[Service]
Type=oneshot
ExecStart=%h/.nix-profile/bin/python3 %h/dev/fullstacked-nixlab/scripts/email-assistant.py triage
StandardOutput=append:/home/noor/email-assistant-triage.log
StandardError=inherit
```

```ini
# ~/.config/systemd/user/email-assistant-triage.timer
[Unit]
Description=Run email triage every 15 minutes
[Timer]
OnCalendar=*:0/15
Persistent=true
[Install]
WantedBy=timers.target
```

```sh
systemctl --user daemon-reload
systemctl --user enable --now email-assistant-triage.timer
```

Requires `loginctl` linger for `noor` (enabled) and `python3` in the user
nix profile. JMAP endpoint is `http://172.18.0.1:1080` (localhost-only);
from other tailnet hosts use `ssh -L 1080:172.18.0.1:1080 nixlab`.

## Verification

```sh
scripts/mail-health-check.sh   # 16 OK, exit 0 (apex :443 no-listener is WARN, not FAIL)
systemctl --user list-timers | grep email-assistant
tail ~/email-assistant-triage.log
```

## Limits / next

- Draft command is create+destroy proof only; composing real drafts is next.
- No digest/nudge logic yet; triage only reports counts (inbox empty).
- `mail.fullstacked.se` Pangolin resource keeps `sso=True`; public JMAP
  would need a separate `sso=False` host — deferred (tailnet is enough).
