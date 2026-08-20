#!/usr/bin/env bash
# mail-health-check.sh — assert Stalwart service, listeners, TLS, and HTTP
# surfaces are up. Complements mail-tls-check.sh (TLS cert lifetime + DNS).
# Requires: curl, openssl. No jq.
# Usage: mail-health-check.sh [HTTP_BASE]
set -u
HTTP_BASE="${1:-http://172.18.0.1:1080}"
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

# --- 2. listeners ----------------------------------------------------------
LISTEN=$(ss -ltn)
for spec in "*:25 smtp" "*:465 submissions" "*:993 imaps" "172.18.0.1:1080 webadmin"; do
  listen="${spec%% *}"; label="${spec##* }"
  match=$(printf '%s\n' "$LISTEN" | grep -E "LISTEN .*${listen//./\\.}") || true
  if printf '%s\n' "$match" | grep -q "^LISTEN"; then
    echo "$OK  listener $label on $listen"
  else
    echo "$BAD  listener $label on $listen  (NOT listening)"
    FAILED=1
  fi
done

# --- 3. recovery mode / config errors in journal (since current start) ------
START=$(systemctl show stalwart -p ActiveEnterTimestamp --value 2>/dev/null | sed 's/^[A-Za-z]* //; s/[A-Z][A-Z]*$//')
if sudo journalctl -u stalwart --no-pager --since "$START" 2>/dev/null | grep -qE 'http-recovery|failed to load|config.*(error|invalid)|is_recovery'; then
  echo "$BAD  recorder hit: recent config-load errors / recovery mode in journal"
  FAILED=1
else
  echo "$OK  no recovery-mode or config-load errors in recent journal"
fi

# --- 4. SMTP banner (port 25, plaintext) -----------------------------------
banner=$(timeout 8 bash -c "exec 3<>/dev/tcp/127.0.0.1/25; head -1 <&3" 2>/dev/null)
if printf '%s' "$banner" | grep -q '^220 .*Stalwart'; then
  echo "$OK  SMTP :25 banner: $banner"
else
  echo "$BAD  SMTP :25 banner: ${banner:-<none>}"
  FAILED=1
fi

# --- 5. TLS handshake on implicit-TLS ports ---------------------------------
for port in 465 993; do
  if echo | timeout 8 openssl s_client -connect "127.0.0.1:$port" -servername mail.fullstacked.se 2>/dev/null | grep -q 'Verify return code: 0'; then
    echo "$OK  TLS handshake :$port (cert verifies)"
  else
    echo "$BAD  TLS handshake :$port (cert check failed)"
    FAILED=1
  fi
done

# --- 6. HTTP surfaces served by Stalwart -----------------------------------
check_http() { # host path expect-1 expect-2(optional redirect target)
  local host="$1" path="$2" want="$3" code
  code=$(curl -sS -o /dev/null -w '%{http_code}' -H "Host: $host" "$HTTP_BASE$path" 2>/dev/null)
  case "$want" in
    200) [ "$code" = "200" ] ;;
    302) [ "$code" = "302" ] ;;
  esac
  if [ $? -eq 0 ]; then echo "$OK  $host$path  -> $code"; else
    echo "$BAD  $host$path  -> $code (expected $want)"; FAILED=1; fi
}
check_http mta-sts.fullstacked.se    /.well-known/mta-sts.txt 200
check_http autoconfig.fullstacked.se /mail/config-v1.1.xml    200
check_http mail.fullstacked.se       /                        302

# --- 7. TLS/DNS deep check (existing script) --------------------------------
if /home/noor/dev/fullstacked-nixlab/scripts/mail-tls-check.sh >/dev/null 2>&1; then
  echo "$OK  mail-tls-check.sh: cert lifetimes + Cloudflare DNS pass"
else
  echo "$WARN  mail-tls-check.sh: some TLS/DNS item did not pass (run it directly for detail)"
fi

echo
if [ "$FAILED" -eq 0 ]; then
  echo "RESULT: healthy"
else
  echo "RESULT: $FAILED check(s) failed"
  exit 1
fi