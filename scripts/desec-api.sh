#!/usr/bin/env bash
# desec-api.sh — DeSEC v1 API with Token auth from env. Runs ON NIXLAB.
# Usage:
#   desec-api.sh <METHOD> <path> [json-body]
#   desec-api.sh --help
# Examples:
#   desec-api.sh GET /domains/
#   desec-api.sh GET /domains/fullstacked.se/
# Env: DESEC_API_TOKEN (or ~/.secrets/fullstacked.env). Never print it.
set -euo pipefail

if [[ "${1:-}" == "--help" || $# -lt 2 ]]; then
  sed -n '2,9p' "$0"
  exit 0
fi
SECRETS_FILE="${HOME}/.secrets/fullstacked.env"
if [[ -r "$SECRETS_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$SECRETS_FILE"
fi
: "${DESEC_API_TOKEN:?Set DESEC_API_TOKEN or ensure ~/.secrets/fullstacked.env has it}"
METHOD="$1"
PATH_ARG="$2"
BODY="${3:-}"
ARGS=(-s --max-time 25 -X "$METHOD" "https://desec.io/api/v1${PATH_ARG}"
  -H "Authorization: Token $DESEC_API_TOKEN" -H "Accept: application/json")
if [[ -n "$BODY" ]]; then
  echo "$BODY" | python3 -c "import json,sys; json.load(sys.stdin)" ||
    die "body must be JSON (got: $BODY)"
  ARGS+=(-H "Content-Type: application/json" -d "$BODY")
fi
curl "${ARGS[@]}"
echo
