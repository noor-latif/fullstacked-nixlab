#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${ENV_FILE:-/home/noor/.config/codex-agents/fullstacked.env}"
# shellcheck disable=SC1090
. "$ENV_FILE"

: "${CLOUDFLARE_API_TOKEN:?missing CLOUDFLARE_API_TOKEN}"
: "${CLOUDFLARE_ZONE_NAME:?missing CLOUDFLARE_ZONE_NAME}"
: "${MOX_DOMAIN:?missing MOX_DOMAIN}"
: "${MOX_MAIL_HOST:?missing MOX_MAIL_HOST}"
: "${MOX_PUBLIC_IPV4:?missing MOX_PUBLIC_IPV4}"

API="https://api.cloudflare.com/client/v4"
AUTH=(-H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" -H "Content-Type: application/json")

cf() {
  curl -fsS "${AUTH[@]}" "$@"
}

zone_id="$(cf "${API}/zones?name=${CLOUDFLARE_ZONE_NAME}" | jq -r '.result[0].id // empty')"
if [[ -z "$zone_id" ]]; then
  echo "Could not find Cloudflare zone ${CLOUDFLARE_ZONE_NAME}" >&2
  exit 1
fi

records_for() {
  local type="$1" name="$2"
  cf "${API}/zones/${zone_id}/dns_records?type=${type}&name=${name}&per_page=100"
}

record_id_by_name() {
  local type="$1" name="$2"
  records_for "$type" "$name" | jq -r '.result[0].id // empty'
}

spf_record_id() {
  records_for TXT "$MOX_DOMAIN" | jq -r '.result[] | select(.content | startswith("v=spf1")) | .id' | head -n 1
}

upsert_dns_record() {
  local type="$1" name="$2" content="$3" ttl="${4:-300}" proxied="${5:-false}" priority="${6:-}"
  local id payload

  id="$(record_id_by_name "$type" "$name")"
  if [[ "$type" == "TXT" && "$name" == "$MOX_DOMAIN" && "$content" == v=spf1* ]]; then
    id="$(spf_record_id)"
  fi

  if [[ "$type" == "MX" ]]; then
    payload="$(jq -cn --arg type "$type" --arg name "$name" --arg content "$content" \
      --argjson ttl "$ttl" --argjson priority "$priority" \
      '{type:$type,name:$name,content:$content,ttl:$ttl,priority:$priority}')"
  elif [[ "$type" == "A" || "$type" == "AAAA" || "$type" == "CNAME" ]]; then
    payload="$(jq -cn --arg type "$type" --arg name "$name" --arg content "$content" \
      --argjson ttl "$ttl" --argjson proxied "$proxied" \
      '{type:$type,name:$name,content:$content,ttl:$ttl,proxied:$proxied}')"
  else
    payload="$(jq -cn --arg type "$type" --arg name "$name" --arg content "$content" \
      --argjson ttl "$ttl" \
      '{type:$type,name:$name,content:$content,ttl:$ttl}')"
  fi

  if [[ -n "$id" ]]; then
    cf -X PUT "${API}/zones/${zone_id}/dns_records/${id}" --data "$payload" >/dev/null
    echo "updated ${type} ${name}"
  else
    cf -X POST "${API}/zones/${zone_id}/dns_records" --data "$payload" >/dev/null
    echo "created ${type} ${name}"
  fi
}

upsert_srv_record() {
  local name="$1" service="$2" proto="$3" record_name="$4" priority="$5" weight="$6" port="$7" target="$8" ttl="${9:-300}"
  local id payload

  id="$(record_id_by_name SRV "$name")"
  payload="$(
    jq -cn \
      --arg type SRV \
      --arg name "$name" \
      --arg service "$service" \
      --arg proto "$proto" \
      --arg record_name "$record_name" \
      --arg target "$target" \
      --argjson ttl "$ttl" \
      --argjson priority "$priority" \
      --argjson weight "$weight" \
      --argjson port "$port" \
      '{
        type:$type,
        name:$name,
        ttl:$ttl,
        data:{
          service:$service,
          proto:$proto,
          name:$record_name,
          priority:$priority,
          weight:$weight,
          port:$port,
          target:$target
        }
      }'
  )"

  if [[ -n "$id" ]]; then
    cf -X PUT "${API}/zones/${zone_id}/dns_records/${id}" --data "$payload" >/dev/null
    echo "updated SRV ${name}"
  else
    cf -X POST "${API}/zones/${zone_id}/dns_records" --data "$payload" >/dev/null
    echo "created SRV ${name}"
  fi
}

delete_duplicate_spf() {
  local keep_id
  keep_id="$(spf_record_id)"
  records_for TXT "$MOX_DOMAIN" \
    | jq -r --arg keep_id "$keep_id" '.result[] | select(.content | startswith("v=spf1")) | select(.id != $keep_id) | .id' \
    | while read -r id; do
        [[ -z "$id" ]] && continue
        cf -X DELETE "${API}/zones/${zone_id}/dns_records/${id}" >/dev/null
        echo "deleted duplicate SPF TXT ${id}"
      done
}

# --- Base DNS records ---

upsert_dns_record A   "$MOX_DOMAIN"   "$MOX_PUBLIC_IPV4" 300 false
upsert_dns_record A   "$MOX_MAIL_HOST" "$MOX_PUBLIC_IPV4" 300 false
upsert_dns_record MX  "$MOX_DOMAIN"   "$MOX_MAIL_HOST"    300 false 10

# SPF
MOX_SPF="${MOX_SPF:-v=spf1 mx ~all}"
upsert_dns_record TXT "$MOX_DOMAIN"   "$MOX_SPF" 300
delete_duplicate_spf
upsert_dns_record TXT "$MOX_MAIL_HOST" "v=spf1 a -all" 300

# DMARC
MOX_DMARC="${MOX_DMARC:-v=DMARC1; p=none; rua=mailto:dmarcreports@${MOX_DOMAIN}}"
upsert_dns_record TXT "_dmarc.${MOX_DOMAIN}" "$MOX_DMARC" 300

# MTA-STS
MOX_MTA_STS_ID="${MOX_MTA_STS_ID:-}"
if [[ -n "$MOX_MTA_STS_ID" ]]; then
  upsert_dns_record CNAME "mta-sts.${MOX_DOMAIN}" "$MOX_MAIL_HOST" 300 false
  upsert_dns_record TXT   "_mta-sts.${MOX_DOMAIN}"  "v=STSv1; id=${MOX_MTA_STS_ID}" 300
fi

# TLSRPT
upsert_dns_record TXT "_smtp._tls.${MOX_DOMAIN}"   "v=TLSRPTv1; rua=mailto:tlsreports@${MOX_DOMAIN}" 300
upsert_dns_record TXT "_smtp._tls.${MOX_MAIL_HOST}" "v=TLSRPTv1; rua=mailto:tlsreports@${MOX_MAIL_HOST}" 300

# Autoconfig
MOX_AUTOCONFIG_CNAME="${MOX_AUTOCONFIG_CNAME:-$MOX_MAIL_HOST}"
upsert_dns_record CNAME "autoconfig.${MOX_DOMAIN}" "$MOX_AUTOCONFIG_CNAME" 300 false

# DKIM — one or more selectors, keyed by MOX_DKIM_SELECTOR_<N> / MOX_DKIM_KEY_<N>
MOX_DKIM_COUNT="${MOX_DKIM_COUNT:-0}"
for i in $(seq 1 "$MOX_DKIM_COUNT"); do
  sel_var="MOX_DKIM_SELECTOR_${i}"
  key_var="MOX_DKIM_KEY_${i}"
  upsert_dns_record TXT \
    "${!sel_var}._domainkey.${MOX_DOMAIN}" \
    "v=DKIM1;h=sha256;p=${!key_var}" 300
done

# Hostup / external auth TXT (optional)
MOX_HOSTUP_AUTH="${MOX_HOSTUP_AUTH:-}"
if [[ -n "$MOX_HOSTUP_AUTH" ]]; then
  upsert_dns_record TXT "_hostup.${MOX_DOMAIN}" "$MOX_HOSTUP_AUTH" 300
fi

# Autodiscovery SRV records
upsert_srv_record "_autodiscover._tcp.${MOX_DOMAIN}" "_autodiscover" "_tcp" "$MOX_DOMAIN" 0 1 443 "$MOX_MAIL_HOST" 300
upsert_srv_record "_imaps._tcp.${MOX_DOMAIN}"       "_imaps"         "_tcp" "$MOX_DOMAIN" 0 1 993 "$MOX_MAIL_HOST" 300
upsert_srv_record "_submissions._tcp.${MOX_DOMAIN}"  "_submissions"   "_tcp" "$MOX_DOMAIN" 0 1 465 "$MOX_MAIL_HOST" 300

# Disable unencrypted services
upsert_srv_record "_imap._tcp.${MOX_DOMAIN}"       "_imap"       "_tcp" "$MOX_DOMAIN" 0 0 0 "." 300
upsert_srv_record "_submission._tcp.${MOX_DOMAIN}"  "_submission" "_tcp" "$MOX_DOMAIN" 0 0 0 "." 300
upsert_srv_record "_pop3._tcp.${MOX_DOMAIN}"        "_pop3"       "_tcp" "$MOX_DOMAIN" 0 0 0 "." 300
upsert_srv_record "_pop3s._tcp.${MOX_DOMAIN}"       "_pop3s"      "_tcp" "$MOX_DOMAIN" 0 0 0 "." 300

echo "Cloudflare DNS records are ready."
