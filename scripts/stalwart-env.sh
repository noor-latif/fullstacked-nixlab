#!/usr/bin/env bash
# stalwart-env.sh — export Stalwart admin connection vars. Runs ON NIXLAB.
# Sourced:  source scripts/stalwart-env.sh
# Captured: eval "$(scripts/stalwart-env.sh --print)"
# Bare execution prints NOTHING (refuses) so secrets never land in logs.
# Provides STALWART_URL / STALWART_USER / STALWART_PASSWORD from
# ~/.secrets/fullstacked.env (STALWART_ADMIN_EMAIL/PASSWORD).
SOURCED_GUARD="stalwart-env"
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  SOURCED_GUARD="sourced"
fi

SECRETS_FILE="${HOME}/.secrets/fullstacked.env"
if [[ -r "$SECRETS_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$SECRETS_FILE"
fi

STALWART_URL="${STALWART_URL:-http://127.0.0.1:41209}"
STALWART_USER="${STALWART_USER:-${STALWART_ADMIN_EMAIL:?STALWART_ADMIN_EMAIL missing}}"
STALWART_PASSWORD="${STALWART_PASSWORD:-${STALWART_ADMIN_PASSWORD:?STALWART_ADMIN_PASSWORD missing}}"

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  export STALWART_URL STALWART_USER STALWART_PASSWORD
elif [[ "${1:-}" == "--print" ]]; then
  printf 'export STALWART_URL=%q STALWART_USER=%q STALWART_PASSWORD=%q\n' \
    "$STALWART_URL" "$STALWART_USER" "$STALWART_PASSWORD"
else
  echo "Usage: source scripts/stalwart-env.sh | eval \"\$(scripts/stalwart-env.sh --print)\"" >&2
  exit 1
fi
