#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${ENV_FILE:-/home/noor/.config/codex-agents/fullstacked.env}"
# shellcheck disable=SC1090
. "$ENV_FILE"

: "${PANGOLIN_API_TOKEN:?missing PANGOLIN_API_TOKEN}"
: "${PANGOLIN_ORG_ID:?missing PANGOLIN_ORG_ID}"
: "${PANGOLIN_API_BASE:?missing PANGOLIN_API_BASE}"
: "${MOX_DOMAIN:?missing MOX_DOMAIN}"

SITE_NICE_ID="${PANGOLIN_SITE_NICE_ID:-local-vps}"
SITE_NAME="${PANGOLIN_SITE_NAME:-Local VPS}"
HOST_GATEWAY="${PANGOLIN_HOST_GATEWAY:-172.18.0.1}"

api() {
  local method="$1" path="$2" data="${3:-}"
  if [[ -n "$data" ]]; then
    curl -fsS \
      -X "$method" \
      -H "Authorization: Bearer ${PANGOLIN_API_TOKEN}" \
      -H "Content-Type: application/json" \
      "${PANGOLIN_API_BASE}${path}" \
      --data "$data"
  else
    curl -fsS \
      -X "$method" \
      -H "Authorization: Bearer ${PANGOLIN_API_TOKEN}" \
      "${PANGOLIN_API_BASE}${path}"
  fi
}

domain_id="$(
  api GET "/org/${PANGOLIN_ORG_ID}/domains" \
    | jq -r --arg domain "$MOX_DOMAIN" '.data.domains[]? | select(.baseDomain == $domain) | .domainId' \
    | head -n 1
)"
if [[ -z "$domain_id" ]]; then
  echo "No Pangolin domain found for ${MOX_DOMAIN}" >&2
  exit 1
fi

site_id="$(
  api GET "/org/${PANGOLIN_ORG_ID}/sites?pageSize=100" \
    | jq -r --arg niceId "$SITE_NICE_ID" '.data.sites[]? | select(.niceId == $niceId) | .siteId' \
    | head -n 1
)"
if [[ -z "$site_id" ]]; then
  site_payload="$(jq -cn --arg name "$SITE_NAME" --arg niceId "$SITE_NICE_ID" '{name:$name,niceId:$niceId,type:"local"}')"
  site_id="$(api PUT "/org/${PANGOLIN_ORG_ID}/site" "$site_payload" | jq -r '.data.siteId')"
  echo "created site ${site_id}"
else
  echo "found site ${site_id}"
fi

resource_id_for_domain() {
  local fqdn="$1"
  api GET "/org/${PANGOLIN_ORG_ID}/resources?pageSize=100&siteId=${site_id}" \
    | jq -r --arg fqdn "$fqdn" '.data.resources[]? | select(.fullDomain == $fqdn) | .resourceId' \
    | head -n 1
}

target_id_for_resource() {
  local resource_id="$1" port="$2"
  api GET "/resource/${resource_id}/targets" \
    | jq -r --arg ip "$HOST_GATEWAY" --argjson port "$port" --argjson siteId "$site_id" \
        '.data.targets[]? | select(.siteId == $siteId and .ip == $ip and .port == $port) | .targetId' \
    | head -n 1
}

ensure_resource() {
  local name="$1" subdomain="$2" port="$3" sso="$4"
  local fqdn="${subdomain}.${MOX_DOMAIN}"
  local resource_id target_id resource_payload update_payload target_payload

  resource_id="$(resource_id_for_domain "$fqdn")"
  if [[ -z "$resource_id" ]]; then
    resource_payload="$(
      jq -cn \
        --arg name "$name" \
        --arg subdomain "$subdomain" \
        --arg domainId "$domain_id" \
        '{name:$name,http:true,subdomain:$subdomain,domainId:$domainId,protocol:"tcp"}'
    )"
    resource_id="$(api PUT "/org/${PANGOLIN_ORG_ID}/resource" "$resource_payload" | jq -r '.data.resourceId')"
    echo "created resource ${name} ${resource_id}"
  else
    echo "found resource ${name} ${resource_id}"
  fi

  update_payload="$(jq -cn --arg name "$name" --argjson sso "$sso" '{name:$name,sso:$sso,ssl:true,enabled:true}')"
  api POST "/resource/${resource_id}" "$update_payload" >/dev/null
  echo "updated resource ${name}"

  target_id="$(target_id_for_resource "$resource_id" "$port")"
  if [[ -z "$target_id" ]]; then
    target_payload="$(
      jq -cn \
        --argjson siteId "$site_id" \
        --arg ip "$HOST_GATEWAY" \
        --argjson port "$port" \
        '{siteId:$siteId,ip:$ip,port:$port,method:"http",enabled:true}'
    )"
    target_id="$(api PUT "/resource/${resource_id}/target" "$target_payload" | jq -r '.data.targetId')"
    echo "created target ${name} ${target_id}"
  else
    target_payload="$(
      jq -cn \
        --argjson siteId "$site_id" \
        --arg ip "$HOST_GATEWAY" \
        --argjson port "$port" \
        '{siteId:$siteId,ip:$ip,port:$port,method:"http",enabled:true}'
    )"
    api POST "/target/${target_id}" "$target_payload" >/dev/null
    echo "updated target ${name} ${target_id}"
  fi
}

ensure_resource "Mox Webmail" "mail" 1080 true
ensure_resource "Mox MTA STS" "mta-sts" 81 false
ensure_resource "Mox Autoconfig" "autoconfig" 81 false

echo "Pangolin Mox resources are reconciled."
