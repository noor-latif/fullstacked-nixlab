#!/usr/bin/env bash
# hostup-mcp.sh — call HostUp MCP tools without hand-building envelopes.
# Runs ON NIXLAB (HOSTUP_API_KEY lives in ~/.secrets/fullstacked.env there).
# Usage:
#   hostup-mcp.sh list                                # list all tool names
#   hostup-mcp.sh <tool> ['<json-object-args>']       # tools/call
#   hostup-mcp.sh --help
# Examples:
#   hostup-mcp.sh list_dns_records '{"zone":"fullstacked.se"}'
#   hostup-mcp.sh update_domain_nameservers '{"domain":"fullstacked.se","nameservers":["ns1.desec.io","ns2.desec.org"]}'
# Gotchas (learned): JSON-RPC envelope REQUIRES "id"; recordType filter 403s —
# list unfiltered and filter client-side; HostUp rejects python-urllib UA (curl fine).
set -euo pipefail

ENDPOINT="https://cloud.hostup.se/api/v2"
MCP="https://cloud.hostup.se/mcp"
UA="curl-hostup-mcp"

if [[ "${1:-}" == "--help" || $# -eq 0 ]]; then
  sed -n '2,12p' "$0"
  exit 0
fi
SECRETS_FILE="${HOME}/.secrets/fullstacked.env"
if [[ -r "$SECRETS_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$SECRETS_FILE"
fi
: "${HOSTUP_API_KEY:?Set HOSTUP_API_KEY or ensure ~/.secrets/fullstacked.env has it}"
command -v curl >/dev/null || { echo "ERROR: missing curl" >&2; exit 1; }
if [[ "$1" == "list" ]]; then
  curl -s --max-time 25 -X POST "$MCP" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $HOSTUP_API_KEY" -H "User-Agent: $UA" \
    -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' |
    python3 -c "import json,sys; d=json.load(sys.stdin); [print(t['name']) for t in d['result']['tools']]"
  exit 0
fi

TOOL="$1"
ARGS="${2:-{}}"
ID=$((RANDOM % 100000 + 1))
TOOL_NAME="$TOOL" TOOL_ARGS="$ARGS" TOOL_ID="$ID" python3 -c "import json,os; print(json.dumps({'jsonrpc':'2.0','id':int(os.environ['TOOL_ID']),'method':'tools/call','params':{'name':os.environ['TOOL_NAME'],'arguments':json.loads(os.environ['TOOL_ARGS'])}}))" | {
read -r PAYLOAD
curl -s --max-time 25 -X POST "$MCP" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $HOSTUP_API_KEY" -H "User-Agent: $UA" \
  -d "$PAYLOAD"
}
echo
