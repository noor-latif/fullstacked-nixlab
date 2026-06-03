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

upsert_record() {
  local type="$1" name="$2" content="$3" ttl="${4:-300}" proxied="${5:-false}" priority="${6:-}"
  local id payload

  id="$(record_id_by_name "$type" "$name")"
  if [[ "$type" == "TXT" && "$name" == "$MOX_DOMAIN" && "$content" == v=spf1* ]]; then
    id="$(spf_record_id)"
  fi

  if [[ "$type" == "MX" ]]; then
    payload="$(jq -cn --arg type "$type" --arg name "$name" --arg content "$content" --argjson ttl "$ttl" --argjson priority "$priority" '{type:$type,name:$name,content:$content,ttl:$ttl,priority:$priority}')"
  elif [[ "$type" == "A" || "$type" == "AAAA" || "$type" == "CNAME" ]]; then
    payload="$(jq -cn --arg type "$type" --arg name "$name" --arg content "$content" --argjson ttl "$ttl" --argjson proxied "$proxied" '{type:$type,name:$name,content:$content,ttl:$ttl,proxied:$proxied}')"
  else
    payload="$(jq -cn --arg type "$type" --arg name "$name" --arg content "$content" --argjson ttl "$ttl" '{type:$type,name:$name,content:$content,ttl:$ttl}')"
  fi

  if [[ -n "$id" ]]; then
    cf -X PUT "${API}/zones/${zone_id}/dns_records/${id}" --data "$payload" >/dev/null
    echo "updated ${type} ${name}"
  else
    cf -X POST "${API}/zones/${zone_id}/dns_records" --data "$payload" >/dev/null
    echo "created ${type} ${name}"
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

upsert_record A "$MOX_DOMAIN" "$MOX_PUBLIC_IPV4" 300 false
upsert_record A "$MOX_MAIL_HOST" "$MOX_PUBLIC_IPV4" 300 false
upsert_record CNAME "mta-sts.${MOX_DOMAIN}" "$MOX_MAIL_HOST" 300 false
upsert_record CNAME "autoconfig.${MOX_DOMAIN}" "$MOX_MAIL_HOST" 300 false
upsert_record MX "$MOX_DOMAIN" "$MOX_MAIL_HOST" 300 false 10
upsert_record TXT "_hostup.${MOX_DOMAIN}" "v=mc1 auth=h_MTQzLjE0LjUwLjEzMA==_5f2a2a918e34" 300
upsert_record TXT "$MOX_DOMAIN" "v=spf1 include:spf.hostup.se mx ~all" 300
delete_duplicate_spf
upsert_record TXT "_dmarc.${MOX_DOMAIN}" "v=DMARC1; p=none; rua=mailto:dmarcreports@${MOX_DOMAIN}; adkim=s; aspf=s" 300

echo "Cloudflare base DNS records are ready."
