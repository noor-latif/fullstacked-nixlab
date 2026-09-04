#!/usr/bin/env bash
# mail-tls-check.sh — sanity-check Stalwart mail TLS endpoints + Cloudflare DNS.
# Requires: openssl, dig (bind.dnsutils), jq, curl.
# Usage: mail-tls-check.sh [DOMAIN] [MAILHOST] [PUBLIC_IP]
set -u
DOMAIN="${1:-fullstacked.se}"
MAILHOST="${2:-mail.fullstacked.se}"
PUBLIC_IP="${3:-143.14.50.130}"
WARN_DAYS=14
CF_RESOLVER="1.1.1.1"
OK=$'\033[0;32m[OK]\033[0m'
BAD=$'\033[0;31m[FAIL]\033[0m'
WARN=$'\033[0;33m[WARN]\033[0m'
FAILED=0

tls_cert_days() { # host port [starttls]
  local host="$1" port="$2" stls="${3:-}" end="" start="" days="" extra=""
  [ "$stls" = "smtp" ] && extra="-starttls smtp"
  end=$(echo | timeout 15 openssl s_client -servername "$host" -connect "$host:$port" $extra -crlf </dev/null 2>/dev/null \
        | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
  [ -z "$end" ] && return 1
  start=$(date +%s); end=$(date -d "$end" +%s)
  days=$(( (end - start) / 86400 ))
  echo "$days"
  [ "$days" -lt "$WARN_DAYS" ]
}

echo "=== TLS endpoints for $MAILHOST (ports 25/465/993) and $DOMAIN (443) ==="
for spec in "25:smtp" "465:" "993:"; do
  p="${spec%%:*}"; stls="${spec##*:}"
  days=$(tls_cert_days "$MAILHOST" "$p" "$stls")
  if [ -z "$days" ]; then echo "$BAD  $MAILHOST:$p  no cert / handshake failed"; FAILED=1; else
    if [ "$days" -lt "$WARN_DAYS" ]; then echo "$WARN  $MAILHOST:$p  cert expires in $days days"; else
      echo "$OK  $MAILHOST:$p  cert valid ($days days)"; fi
  fi
done
days=$(tls_cert_days "$DOMAIN" 443)
if [ -z "$days" ]; then
  if timeout 5 bash -c "echo > /dev/tcp/$DOMAIN/443" 2>/dev/null; then
    echo "$BAD  $DOMAIN:443  port open but TLS handshake failed"; FAILED=1
  else
    echo "$WARN  $DOMAIN:443  no listener (no site published on apex?)"
  fi
else
  if [ "$days" -lt "$WARN_DAYS" ]; then echo "$WARN  $DOMAIN:443  cert expires in $days days"; else
    echo "$OK  $DOMAIN:443  cert valid ($days days)"; fi
fi

echo; echo "=== Cloudflare DNS sanity (resolver $CF_RESOLVER) ==="
check_txt() { # name expected-substring
  local name="$1" want="$2" got
  got=$(dig +short TXT "$name" @"$CF_RESOLVER" 2>/dev/null | tr -d '"' | head -1)
  if [ -z "$got" ]; then echo "$BAD  $name  no TXT record"; FAILED=1; return; fi
  if printf '%s' "$got" | grep -qi "$want"; then echo "$OK  $name  -> $got"; else
    echo "$WARN  $name  -> $got  (expected ~ $want)"; fi
}
check_a() { # name expected-ip
  local name="$1" want="$2" got
  got=$(dig +short A "$name" @"$CF_RESOLVER" 2>/dev/null | tail -1)
  if [ "$got" = "$want" ]; then echo "$OK  $name  -> $got"; else
    echo "$BAD  $name  -> ${got:-<none>}  (expected $want)"; FAILED=1; fi
}
check_resolves() { # name (informational; must resolve to an IP)
  local name="$1" got
  got=$(dig +short A "$name" @"$CF_RESOLVER" 2>/dev/null | tail -1)
  if [ -n "$got" ]; then echo "$OK  $name  -> $got"; else echo "$BAD  $name  -> <none>"; FAILED=1; fi
}

check_a "$MAILHOST" "$PUBLIC_IP"
check_txt "$DOMAIN" "v=spf1"                      # SPF (should include spf.hostup.se for relay)
check_txt "_dmarc.$DOMAIN" "v=DMARC1"            # DMARC
check_txt "_mta-sts.$DOMAIN" "v=STSv1"           # MTA-STS policy id
check_a "mta-sts.$DOMAIN" "$PUBLIC_IP"           # MTA-STS policy host
check_resolves "autoconfig.$DOMAIN"              # autoconfig host
check_resolves "autodiscover.$DOMAIN"            # autodiscover host
echo "$OK  DNS checks complete"
exit "$FAILED"
