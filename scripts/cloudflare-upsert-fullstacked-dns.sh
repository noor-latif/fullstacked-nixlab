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

upsert_record A "$MOX_DOMAIN" "$MOX_PUBLIC_IPV4" 300 false
upsert_record A "$MOX_MAIL_HOST" "$MOX_PUBLIC_IPV4" 300 false
upsert_record CNAME "mta-sts.${MOX_DOMAIN}" "$MOX_MAIL_HOST" 300 false
upsert_record CNAME "autoconfig.${MOX_DOMAIN}" "$MOX_MAIL_HOST" 300 false
upsert_record MX "$MOX_DOMAIN" "$MOX_MAIL_HOST" 300 false 10
upsert_record TXT "_hostup.${MOX_DOMAIN}" "v=mc1 auth=h_MTQzLjE0LjUwLjEzMA==_5f2a2a918e34" 300
upsert_record TXT "$MOX_DOMAIN" "v=spf1 include:spf.hostup.se mx ~all" 300
delete_duplicate_spf
upsert_record TXT "_dmarc.${MOX_DOMAIN}" "v=DMARC1; p=none; rua=mailto:dmarcreports@${MOX_DOMAIN}; adkim=s; aspf=s" 300
upsert_record TXT "$MOX_MAIL_HOST" "v=spf1 a -all" 300
upsert_record TXT "_mta-sts.${MOX_DOMAIN}" "v=STSv1; id=20260603T075354" 300
upsert_record TXT "_smtp._tls.${MOX_DOMAIN}" "v=TLSRPTv1; rua=mailto:tlsreports@${MOX_DOMAIN}" 300
upsert_record TXT "_smtp._tls.${MOX_MAIL_HOST}" "v=TLSRPTv1; rua=mailto:tlsreports@${MOX_MAIL_HOST}" 300
upsert_record TXT "2026a._domainkey.${MOX_DOMAIN}" "v=DKIM1;h=sha256;p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA4R+Fr3iMMrgXuVIdSwAzQMnXRJHXKKBDU9u4zIwcvz08bbfwXf/+pUKEJ9dMF1Y1AWI0FdAp29LdxPdtOYp6sn+2tZVrSBASVLlPQ0fMqxLajKZVbvm6LNn67CIpbRvLBdx/KFAw4I3vwhFTgWvtV8r3IGKNifq7yIijDl3qHcf4ywIb+j8IRrAgzffjJVmxgtVgxerXWEzg5Clepmr+s8p/ZCRKHeRYluAzyHbqZTUpP+1OBBhtNSVuooXhEvKhduL2O/dWVLulpBFYoQj7gw2bdatn8oxp8VxCMbrWKJzPbnTsbPnmpSVGJATkI2wQ47BxxEsr+lqIW/lq4FE9rQIDAQAB" 300
upsert_record TXT "2026b._domainkey.${MOX_DOMAIN}" "v=DKIM1;h=sha256;p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAxQrggzmL4Vc7QXadWAxWRZNoFUU+5Xj9LSR1uyiDNxE+CWcjok2zhGV8aLNcA68wQh4thH1hXfcHLNFRNfCrhsDrbddSrbsCBKI7UAcZui9FQY4VSZdXfIZL9Ot0Zy/iP0YWNdd82i5F8J87w+SE87vEKDathOIi4fTjiGi9sqWpKjdAc6T3hgI5F6UIhFFAedDG/U8j8+gGtC36gUIEv4plX/gL9vW2/18z/BfSjmOQSsw+zwqGOaebv9yxxiZZnZA5GaW6ySMUM6eB+SdS95abyJxcrNh4ZOMOI4oVpRr8vfa+9ViZmeeUWvay52YPWSzBi/w1vNzBDSB4i/DGTQIDAQAB" 300
upsert_srv_record "_autodiscover._tcp.${MOX_DOMAIN}" "_autodiscover" "_tcp" "$MOX_DOMAIN" 0 1 443 "$MOX_MAIL_HOST" 300
upsert_srv_record "_imaps._tcp.${MOX_DOMAIN}" "_imaps" "_tcp" "$MOX_DOMAIN" 0 1 993 "$MOX_MAIL_HOST" 300
upsert_srv_record "_submissions._tcp.${MOX_DOMAIN}" "_submissions" "_tcp" "$MOX_DOMAIN" 0 1 465 "$MOX_MAIL_HOST" 300
upsert_srv_record "_imap._tcp.${MOX_DOMAIN}" "_imap" "_tcp" "$MOX_DOMAIN" 0 0 0 "." 300
upsert_srv_record "_submission._tcp.${MOX_DOMAIN}" "_submission" "_tcp" "$MOX_DOMAIN" 0 0 0 "." 300
upsert_srv_record "_pop3._tcp.${MOX_DOMAIN}" "_pop3" "_tcp" "$MOX_DOMAIN" 0 0 0 "." 300
upsert_srv_record "_pop3s._tcp.${MOX_DOMAIN}" "_pop3s" "_tcp" "$MOX_DOMAIN" 0 0 0 "." 300

echo "Cloudflare base DNS records are ready."
