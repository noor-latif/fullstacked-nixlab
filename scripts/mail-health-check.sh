#!/usr/bin/env bash
# mail-health-check.sh — assert Stalwart service, listeners, TLS, HTTP, and
# (optionally) authenticated access are working. Complements
# mail-tls-check.sh (TLS cert lifetime + DNS).
# Requires: curl, openssl, base64.
# Optional: sources /home/noor/.config/opencode/fullstacked.env for
# STALWART_HEALTH_EMAIL / STALWART_HEALTH_PASSWORD; without them the
# authenticated probes are skipped (WARN, not FAIL).
# Usage: mail-health-check.sh [HTTP_BASE]
set -u
HTTP_BASE="${1:-http://172.18.0.1:1080}"
MAILHOST="mail.fullstacked.se"
OK=$'\033[0;32m[OK]\033[0m'
BAD=$'\033[0;31m[FAIL]\033[0m'
WARN=$'\033[0;33m[WARN]\033[0m'
FAILED=0

# --- 1. systemd unit -------------------------------------------------------
if systemctl is-active --quiet stalwart; then
  echo "$OK  stalwart.service active"
else
  echo "$BAD  stalwart.service is NOT active"
  FAILED=1
fi

# --- 2. listeners (exact port filter, rendering-independent) ---------------
for spec in "*:25 smtp" "*:465 submissions" "*:993 imaps" "172.18.0.1:1080 webadmin"; do
  listen="${spec%% *}"; label="${spec##* }"
  addr="${listen%:*}"; port="${listen##*:}"
  out=$(ss -ltn -H "sport = :$port" 2>/dev/null) || true
  if printf '%s\n' "$out" | grep -q '^LISTEN' \
     && { [ "$addr" = "*" ] || printf '%s\n' "$out" | grep -qE "^LISTEN .*${addr//./\\.}:$port "; }; then
    echo "$OK  listener $label on $listen"
  else
    echo "$BAD  listener $label on $listen  (NOT listening)"
    FAILED=1
  fi
done

# --- 3. recovery mode / config errors in journal (since current start) ------
START=$(systemctl show stalwart --timestamp=unix --value -p ActiveEnterTimestamp 2>/dev/null)
if [ -z "$START" ]; then
  echo "$WARN  cannot read stalwart ActiveEnterTimestamp; skipping journal check"
elif sudo journalctl -u stalwart --no-pager --since "$START" 2>/dev/null | grep -qE 'http-recovery|failed to load|config.*(error|invalid)|is_recovery'; then
  echo "$BAD  recent config-load errors / recovery mode in journal"
  FAILED=1
else
  echo "$OK  no recovery-mode or config-load errors in recent journal"
fi

# --- 4. SMTP :25 banner + EHLO (plaintext, one connection) ------------------
smtp=$(timeout 8 bash -c 'exec 3<>/dev/tcp/127.0.0.1/25 || exit 1
  read -r -t5 g <&3
  printf "EHLO mail.fullstacked.se\r\n" >&3
  read -r -t5 e <&3
  printf "QUIT\r\n" >&3
  printf "%s|%s" "$g" "$e"' 2>/dev/null)
banner="${smtp%|*}"; ehlo="${smtp#*|}"
if printf '%s' "$banner" | grep -q '^220 .*Stalwart' && printf '%s' "$ehlo" | grep -q '^250'; then
  echo "$OK  SMTP :25 banner + EHLO respond"
else
  echo "$BAD  SMTP :25 banner/EHLO: ${banner:-<none>}"
  FAILED=1
fi

# --- 5. TLS handshake on implicit-TLS ports ---------------------------------
for port in 465 993; do
  if echo | timeout 8 openssl s_client -connect "127.0.0.1:$port" -servername "$MAILHOST" 2>&1 | grep -q 'Verify return code: 0'; then
    echo "$OK  TLS handshake :$port (cert verifies)"
  else
    echo "$BAD  TLS handshake :$port (cert check failed)"
    FAILED=1
  fi
done

# --- 6. IMAP :993 NOOP (pre-auth protocol probe) ----------------------------
if printf 'a1 NOOP\r\na2 LOGOUT\r\n' | timeout 8 openssl s_client -quiet -connect 127.0.0.1:993 -servername "$MAILHOST" 2>&1 | grep -q '^a1 OK'; then
  echo "$OK  IMAP :993 NOOP (pre-auth) responds"
else
  echo "$BAD  IMAP :993 NOOP failed"
  FAILED=1
fi

# --- 7. HTTP surfaces served by Stalwart -----------------------------------
check_http() { # host path expected-code
  local host="$1" path="$2" want="$3" code
  code=$(curl -sS -o /dev/null -w '%{http_code}' -H "Host: $host" "$HTTP_BASE$path" 2>/dev/null)
  if [ "$code" = "$want" ]; then echo "$OK  $host$path  -> $code"; else
    echo "$BAD  $host$path  -> $code (expected $want)"; FAILED=1; fi
}
check_http mta-sts.fullstacked.se    /.well-known/mta-sts.txt 200
check_http autoconfig.fullstacked.se /mail/config-v1.1.xml    200
check_http mail.fullstacked.se       /                        302

# --- 8. authenticated probes (fail-open if creds absent) --------------------
HEALTH_EMAIL="" HEALTH_PASSWORD=""
if [ -r /home/noor/.config/opencode/fullstacked.env ]; then
  . /home/noor/.config/opencode/fullstacked.env
  HEALTH_EMAIL="${STALWART_HEALTH_EMAIL:-}"
  HEALTH_PASSWORD="${STALWART_HEALTH_PASSWORD:-}"
fi
if [ -n "$HEALTH_EMAIL" ] && [ -n "$HEALTH_PASSWORD" ]; then
  sleep 1
  if printf 'a1 LOGIN %s %s\r\na2 LOGOUT\r\n' "$HEALTH_EMAIL" "$HEALTH_PASSWORD" \
     | timeout 8 openssl s_client -quiet -connect 127.0.0.1:993 -servername "$MAILHOST" 2>&1 \
     | grep -q '^a1 OK .*Authentication successful'; then
    echo "$OK  IMAP :993 LOGIN as $HEALTH_EMAIL"
  else
    echo "$BAD  IMAP :993 LOGIN as $HEALTH_EMAIL failed"
    FAILED=1
  fi
  AUTHB64=$(printf '\0%s\0%s' "$HEALTH_EMAIL" "$HEALTH_PASSWORD" | base64 | tr -d '\n')
  if printf 'EHLO mail.fullstacked.se\r\nAUTH PLAIN %s\r\nQUIT\r\n' "$AUTHB64" \
     | timeout 8 openssl s_client -quiet -connect 127.0.0.1:465 -servername "$MAILHOST" 2>&1 \
     | grep -q '^235'; then
    echo "$OK  SMTP :465 AUTH PLAIN as $HEALTH_EMAIL"
  else
    echo "$BAD  SMTP :465 AUTH PLAIN as $HEALTH_EMAIL failed"
    FAILED=1
  fi
else
  echo "$WARN  health credentials absent (STALWART_HEALTH_*); skipping authenticated probes"
fi

# --- 9. TLS/DNS deep check (existing script) --------------------------------
if /home/noor/dev/fullstacked-nixlab/scripts/mail-tls-check.sh >/dev/null 2>&1; then
  echo "$OK  mail-tls-check.sh: cert lifetimes + Cloudflare DNS pass"
else
  echo "$BAD  mail-tls-check.sh: some TLS/DNS item did not pass (run it directly for detail)"
  FAILED=1
fi

echo
if [ "$FAILED" -eq 0 ]; then
  echo "RESULT: healthy"
else
  echo "RESULT: $FAILED check(s) failed"
  exit 1
fi