#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${ENV_FILE:-/home/noor/.config/codex-agents/fullstacked.env}"
# shellcheck disable=SC1090
. "$ENV_FILE"

: "${PANGOLIN_API_TOKEN:?missing PANGOLIN_API_TOKEN}"
: "${PANGOLIN_ORG_ID:?missing PANGOLIN_ORG_ID}"
: "${MOX_DOMAIN:?missing MOX_DOMAIN}"

CONTAINER="${PANGOLIN_CONTAINER:-pangolin}"
API_BASE="${PANGOLIN_API_BASE:-http://localhost:3003/v1}"
SITE_NICE_ID="${PANGOLIN_SITE_NICE_ID:-local-vps}"
SITE_NAME="${PANGOLIN_SITE_NAME:-Local VPS}"
HOST_GATEWAY="${PANGOLIN_HOST_GATEWAY:-172.18.0.1}"

api() {
  local method="$1" path="$2" data="${3:-}"
  if [[ -n "$data" ]]; then
    docker exec "$CONTAINER" sh -c \
      'curl -fsS -X "$0" -H "Authorization: Bearer $1" -H "Content-Type: application/json" "$2$3" --data "$4"' \
      "$method" "$PANGOLIN_API_TOKEN" "$API_BASE" "$path" "$data"
  else
    docker exec "$CONTAINER" sh -c \
      'curl -fsS -X "$0" -H "Authorization: Bearer $1" "$2$3"' \
      "$method" "$PANGOLIN_API_TOKEN" "$API_BASE" "$path"
  fi
}

site_id="$(api GET "/org/${PANGOLIN_ORG_ID}/sites" | jq -r --arg nice "$SITE_NICE_ID" '.sites[]? | select(.niceId == $nice) | .siteId' | head -n 1)"
if [[ -z "$site_id" ]]; then
  site_payload="$(jq -cn --arg name "$SITE_NAME" --arg niceId "$SITE_NICE_ID" '{name:$name,niceId:$niceId,type:"local"})"
  site_id="$(api POST "/org/${PANGOLIN_ORG_ID}/sites" "$site_payload" | jq -r '.site.siteId // .siteId')"
  echo "created site ${site_id}"
else
  echo "found site ${site_id}"
fi

ensure_resource() {
  local name="$1" subdomain="$2" port="$3" sso="$4"
  local fqdn="${subdomain}.${MOX_DOMAIN}"
  local resource_id target_id resource_payload target_payload

  resource_id="$(api GET "/org/${PANGOLIN_ORG_ID}/resources" | jq -r --arg fqdn "$fqdn" '.resources[]? | select(.fullDomain == $fqdn or .domain == $fqdn) | .resourceId' | head -n 1)"
  if [[ -z "$resource_id" ]]; then
    resource_payload="$(jq -cn --arg name "$name" --arg subdomain "$subdomain" --arg domain "$MOX_DOMAIN" --argjson siteId "$site_id" --argjson sso "$sso" '{name:$name,subdomain:$subdomain,domain:$domain,siteId:$siteId,http:true,protocol:"http",proxyPort:443,sso:$sso}')"
    resource_id="$(api POST "/org/${PANGOLIN_ORG_ID}/resources" "$resource_payload" | jq -r '.resource.resourceId // .resourceId')"
    echo "created resource ${name} ${resource_id}"
  else
    echo "found resource ${name} ${resource_id}"
  fi

  target_id="$(api GET "/org/${PANGOLIN_ORG_ID}/resources/${resource_id}/targets" | jq -r --arg ip "$HOST_GATEWAY" --argjson port "$port" '.targets[]? | select(.ip == $ip and .port == $port) | .targetId' | head -n 1)"
  if [[ -z "$target_id" ]]; then
    target_payload="$(jq -cn --arg ip "$HOST_GATEWAY" --argjson port "$port" --arg method "http" '{ip:$ip,port:$port,method:$method,enabled:true}')"
    target_id="$(api POST "/org/${PANGOLIN_ORG_ID}/resources/${resource_id}/targets" "$target_payload" | jq -r '.target.targetId // .targetId')"
    echo "created target ${name} ${target_id}"
  else
    echo "found target ${name} ${target_id}"
  fi
}

ensure_resource "Mox Webmail" "mail" 1080 true
ensure_resource "Mox MTA STS" "mta-sts" 81 false
ensure_resource "Mox Autoconfig" "autoconfig" 81 false

echo "Pangolin Mox resources are reconciled."
