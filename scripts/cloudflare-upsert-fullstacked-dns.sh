#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${ENV_FILE:-$HOME/.secrets/fullstacked.env}"
# shellcheck disable=SC1090
. "$ENV_FILE"

: "${CLOUDFLARE_API_TOKEN:?missing CLOUDFLARE_API_TOKEN}"
: "${CLOUDFLARE_ZONE_NAME:?missing CLOUDFLARE_ZONE_NAME}"
: "${CF_DOMAIN:?missing CF_DOMAIN}"
: "${CF_MAIL_HOST:?missing CF_MAIL_HOST}"
: "${CF_PUBLIC_IPV4:?missing CF_PUBLIC_IPV4}"

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
  records_for TXT "$CF_DOMAIN" | jq -r '.result[] | select(.content | startswith("v=spf1")) | .id' | head -n 1
}

upsert_dns_record() {
  local type="$1" name="$2" content="$3" ttl="${4:-300}" proxied="${5:-false}" priority="${6:-}"
  local id payload

  id="$(record_id_by_name "$type" "$name")"
  if [[ "$type" == "TXT" && "$name" == "$CF_DOMAIN" && "$content" == v=spf1* ]]; then
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

upsert_caa_record() {
  local name="$1" tag="$2" value="$3" flags="${4:-0}" ttl="${5:-300}"
  local id payload

  id="$(records_for CAA "$name" | jq --arg tag "$tag" --arg value "$value" -r \
    '.result[] | select(.data.tag == $tag and .data.value == $value) | .id' | head -n 1)"

  payload="$(
    jq -cn \
      --arg type CAA \
      --arg name "$name" \
      --argjson ttl "$ttl" \
      --arg tag "$tag" \
      --arg value "$value" \
      --argjson flags "$flags" \
      '{type:$type,name:$name,ttl:$ttl,data:{tag:$tag,value:$value,flags:$flags}}'
  )"

  if [[ -n "$id" ]]; then
    cf -X PUT "${API}/zones/${zone_id}/dns_records/${id}" --data "$payload" >/dev/null
    echo "updated CAA ${name} ${tag} ${value}"
  else
    cf -X POST "${API}/zones/${zone_id}/dns_records" --data "$payload" >/dev/null
    echo "created CAA ${name} ${tag} ${value}"
  fi
}

delete_duplicate_spf() {
  local keep_id
  keep_id="$(spf_record_id)"
  records_for TXT "$CF_DOMAIN" \
    | jq -r --arg keep_id "$keep_id" '.result[] | select(.content | startswith("v=spf1")) | select(.id != $keep_id) | .id' \
    | while read -r id; do
        [[ -z "$id" ]] && continue
        cf -X DELETE "${API}/zones/${zone_id}/dns_records/${id}" >/dev/null
        echo "deleted duplicate SPF TXT ${id}"
      done
}

# --- Base DNS records ---
# A/AAAA and MX are always static (host IP + mail hostname).

upsert_dns_record A   "$CF_DOMAIN"   "$CF_PUBLIC_IPV4" 300 false
upsert_dns_record A   "$CF_MAIL_HOST" "$CF_PUBLIC_IPV4" 300 false
upsert_dns_record MX  "$CF_DOMAIN"   "$CF_MAIL_HOST"    300 false 10

# SPF — (keep in sync with your outbound relay).
CF_SPF="${CF_SPF:-v=spf1 mx ~all}"
upsert_dns_record TXT "$CF_DOMAIN"   "$CF_SPF" 300
delete_duplicate_spf
upsert_dns_record TXT "$CF_MAIL_HOST" "v=spf1 a -all" 300

# DMARC — TXT record on the apex domain.
CF_DMARC="${CF_DMARC:-v=DMARC1; p=none; rua=mailto:dmarcreports@${CF_DOMAIN}}"
upsert_dns_record TXT "_dmarc.${CF_DOMAIN}" "$CF_DMARC" 300

# MTA-STS — policy ID changes when you update the policy.
CF_MTA_STS_ID="${CF_MTA_STS_ID:-}"
if [[ -n "$CF_MTA_STS_ID" ]]; then
  upsert_dns_record CNAME "mta-sts.${CF_DOMAIN}" "$CF_MAIL_HOST" 300 false
  upsert_dns_record TXT   "_mta-sts.${CF_DOMAIN}"  "v=STSv1; id=${CF_MTA_STS_ID}" 300
fi

# TLSRPT — TLS reporting recipients.
upsert_dns_record TXT "_smtp._tls.${CF_DOMAIN}"   "v=TLSRPTv1; rua=mailto:tlsreports@${CF_DOMAIN}" 300
upsert_dns_record TXT "_smtp._tls.${CF_MAIL_HOST}" "v=TLSRPTv1; rua=mailto:tlsreports@${CF_MAIL_HOST}" 300

# Autoconfig CNAME — update if you change mail hostname.
CF_AUTOCONFIG_CNAME="${CF_AUTOCONFIG_CNAME:-$CF_MAIL_HOST}"
upsert_dns_record CNAME "autoconfig.${CF_DOMAIN}" "$CF_AUTOCONFIG_CNAME" 300 false

# DKIM — one or more selectors. Set CF_DKIM_COUNT to the number of selectors,
# then CF_DKIM_SELECTOR_N and CF_DKIM_KEY_N for each.
CF_DKIM_COUNT="${CF_DKIM_COUNT:-0}"
for i in $(seq 1 "$CF_DKIM_COUNT"); do
  sel_var="CF_DKIM_SELECTOR_${i}"
  key_var="CF_DKIM_KEY_${i}"
  upsert_dns_record TXT \
    "${!sel_var}._domainkey.${CF_DOMAIN}" \
    "v=DKIM1;h=sha256;p=${!key_var}" 300
done

# Hostup / external relay auth TXT — optional. Generated by your relay provider.
CF_HOSTUP_AUTH="${CF_HOSTUP_AUTH:-}"
if [[ -n "$CF_HOSTUP_AUTH" ]]; then
  upsert_dns_record TXT "_hostup.${CF_DOMAIN}" "$CF_HOSTUP_AUTH" 300
fi

# Autodiscovery SRV records
upsert_srv_record "_autodiscover._tcp.${CF_DOMAIN}" "_autodiscover" "_tcp" "$CF_DOMAIN" 0 1 443 "$CF_MAIL_HOST" 300
upsert_srv_record "_imaps._tcp.${CF_DOMAIN}"       "_imaps"         "_tcp" "$CF_DOMAIN" 0 1 993 "$CF_MAIL_HOST" 300
upsert_srv_record "_submissions._tcp.${CF_DOMAIN}"  "_submissions"   "_tcp" "$CF_DOMAIN" 0 1 465 "$CF_MAIL_HOST" 300

# Disable unencrypted services
upsert_srv_record "_imap._tcp.${CF_DOMAIN}"       "_imap"       "_tcp" "$CF_DOMAIN" 0 0 0 "." 300
upsert_srv_record "_submission._tcp.${CF_DOMAIN}"  "_submission" "_tcp" "$CF_DOMAIN" 0 0 0 "." 300
upsert_srv_record "_pop3._tcp.${CF_DOMAIN}"        "_pop3"       "_tcp" "$CF_DOMAIN" 0 0 0 "." 300
upsert_srv_record "_pop3s._tcp.${CF_DOMAIN}"       "_pop3s"      "_tcp" "$CF_DOMAIN" 0 0 0 "." 300

# CAA — restricts which Certificate Authorities can issue certs for these names.

upsert_caa_record "$CF_DOMAIN"  "issue" "letsencrypt.org" 0 300
upsert_caa_record "$CF_MAIL_HOST" "issue" "letsencrypt.org" 0 300
upsert_caa_record "mta-sts.${CF_DOMAIN}"  "issue" "letsencrypt.org" 0 300
upsert_caa_record "autoconfig.${CF_DOMAIN}" "issue" "letsencrypt.org" 0 300

echo "Cloudflare DNS records are ready."
