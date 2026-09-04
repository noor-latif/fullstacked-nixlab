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

Track pending sends without storing ids (built-in, per RFC 8621 SS7.3):
`EmailSubmission/query {"filter": {"undoStatus": "pending"}}`
(also `before`/`after` on `sendAt`). IDs are stable per-account server handles (earlier anomalies were my cross-account mixups):
sequences increment, destroyed ids stay `notFound` (verified:
`biaaaaak/bmaaaaal/bqaaaaam/buaaaaan` across create-destroy cycles).

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

## Probed, not yet wired (2026-09-04)

- EventSource push works: `GET /jmap/eventsource/?types=*&closeafter=no&ping=5`
  with `Accept: text/event-stream` -> `200`, `state` events for
  Mailbox/Email changes arrive in seconds. (`closeafter` takes
  `state`|`no`, not seconds.) Path to event-driven: a lightweight
  listener service over `ssh -L` instead of 15-min polling.
- Sieve via JMAP works: blob upload (`Content-Type: application/sieve`)
  -> `SieveScript/set {name, blobId, isActive}`; create-inactive/get/
  destroy cycle verified. 100 scripts max, `fileinto` etc. available.
  Enables server-side auto-filing instead of client cron.
- VacationResponse get/set available (currently disabled).
- Undo: immediate local sends go `final` instantly; cancel only works
  while `pending` (held/queued). No Gmail-style grace window locally.

## Push listener (live 2026-09-04)

`email-assistant.py listen` + `email-assistant-listen.service`
(`Restart=always`). Primary path now; triage timer dropped to hourly fallback.

- Stream: `GET /jmap/eventsource/?types=*&closeafter=no&ping=30`,
  `Accept: text/event-stream`. On `StateChange` for account `c`
  (dedupe identical consecutive states) it logs a triage snapshot.
- Streams are per-principal: admin auth only yields admin-account events.
  The stream uses noor's app password from the overlay file below;
  API reads stay on admin auth (works cross-account).
- App password: minted via `x:AppPassword/set` on account `c`
  (`description: email-assistant listener`), stored ONLY in
  `~/.secrets/email-assistant.env` (`JMAP_USER`/`JMAP_PASSWORD`, 600).
  Never in git/chat. Revoke: `x:AppPassword/destroy` (or webadmin).

```ini
# ~/.config/systemd/user/email-assistant-listen.service
[Unit]
Description=Email push listener (JMAP EventSource)
After=network-online.target
[Service]
Type=simple
ExecStart=%h/.nix-profile/bin/python3 %h/dev/fullstacked-nixlab/scripts/email-assistant.py listen
StandardOutput=append:/home/noor/email-assistant-push.log
StandardError=inherit
Restart=always
RestartSec=5
[Install]
WantedBy=default.target
```

## Sieve management (in script, inactive by default)

```sh
python3 scripts/email-assistant.py sieve-list [account]
python3 scripts/email-assistant.py sieve-put <name> <file.sieve> [--active] [account]
python3 scripts/email-assistant.py sieve-del <id> [account]
```

Upload is `Content-Type: application/sieve` to `/jmap/upload/<account>/`,
then `SieveScript/set`. No active rules yet (inbox empty); activate one
only when real mail shows what needs filing.
