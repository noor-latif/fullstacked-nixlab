#!/usr/bin/env bash
# stalwart-mailbox.sh — Easy Stalwart administration for gotalandstrafikskola.se + other domains
# Wraps stalwart-cli with correct env, gotchas, and domainId lookup.
# Usage: stalwart-mailbox.sh <command> [args]
# See: ~/dev/fullstacked-nixlab/docs/operations-gotaland-2026-08-29.md
set -euo pipefail

# Config
STALWART_URL="${STALWART_URL:-http://127.0.0.1:41209}"
SECRETS_FILE="${HOME}/.secrets/fullstacked.env"
if [[ -r "$SECRETS_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$SECRETS_FILE"
fi
export STALWART_URL
export STALWART_USER="${STALWART_USER:-$STALWART_ADMIN_EMAIL}"
export STALWART_PASSWORD="${STALWART_PASSWORD:-$STALWART_ADMIN_PASSWORD}"
if [[ -z "$STALWART_USER" || -z "$STALWART_PASSWORD" ]]; then
  echo "ERROR: Set STALWART_USER/PASSWORD or ensure ~/.secrets/fullstacked.env has STALWART_ADMIN_EMAIL/PASSWORD" >&2
  exit 1
fi

# Helpers
die() { echo "ERROR: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null || die "missing $1"; }
need stalwart-cli

domain_id_for() {
  local domain="$1"
  local id
  id=$(stalwart-cli query domain 2>&1 | awk -v d="$domain" '$2==d {print $1}')
  if [[ -z "$id" ]]; then die "domain '$domain' not found (query: stalwart-cli query domain)"; fi
  echo "$id"
}

account_id_for() {
  local email="$1"
  local id
  id=$(stalwart-cli query account 2>&1 | awk -v e="$email" '$2==e {print $1}')
  echo "$id"
}

# Fetch current aliases map for account id via snapshot (returns JSON object like {"0":{"name":"info","domainId":"c","enabled":true}})
_fetch_aliases_json() {
  local acc_id="$1"
  local tmp
  tmp=$(mktemp)
  # Snapshot Account+Domain to preserve alias domainId references; allow other types
  stalwart-cli snapshot Account Domain --allow-unresolved Tenant,PublicKey,Role,AcmeProvider,DnsServer,Directory --output "$tmp" >/dev/null 2>&1
  python3 -c "
import json, sys
raw=open(sys.argv[1]).read().strip().split('\n')
vals={}
for line in raw:
    if not line.strip():
        continue
    try:
        j=json.loads(line)
    except:
        continue
    if 'value' in j:
        vals.update(j['value'])
target='account-'+sys.argv[2]
entry=vals.get(target, {})
aliases=entry.get('aliases', {})
if aliases is None:
    aliases={}
norm={}
for k,v in aliases.items():
    nv=dict(v)
    did=nv.get('domainId')
    if isinstance(did, str) and did.startswith('#domain-'):
        nv['domainId']=did.replace('#domain-','')
    norm[k]=nv
print(json.dumps(norm))
" "$tmp" "$acc_id"
  rm -f "$tmp"
}

# Update aliases map for account id (expects full map JSON)
_update_aliases() {
  local acc_id="$1"
  local aliases_json="$2"
  stalwart-cli update account "$acc_id" --field "aliases=$aliases_json" >/dev/null
}

usage() {
  cat <<'USAGE'
stalwart-mailbox.sh — Stalwart admin helper (nixlab, http://127.0.0.1:41209)

Commands:
  list-domains                          List all domains (id, name)
  list-accounts                         List all accounts (id, email, name)
  get <email|id>                        Show account details (stalwart-cli get account)
  domain-zone <domain>                  Show desired DNS zone for domain (get domain)
  create --domain <d> --user <u> --password <p> [--name "Full"] [--locale sv-SE]
                                        Create mailbox u@d (handles domainId, credentials map)
  update-password --email <e> --password <p>
                                        Update mailbox password (credentials map gotcha)
  delete --email <e>                    Delete account by email (requires confirmation)
  add-alias --email <e> --alias <a>     Add alias a (e.g. info or info@gotalandstrafikskola.se) to mailbox e
  remove-alias --email <e> --alias <a>  Remove alias a from mailbox e
  move-alias --from <src> --to <dst> --alias <a>
                                        Move alias a from src mailbox to dst (atomic check)
  check-mail --email <e>                Show last 5 messages via IMAP (requires creds from ~/.secrets/* or --password)
  health                                Run mail-health-check.sh (listeners, TLS, auth)
  help                                  This help

Examples:
  stalwart-mailbox.sh list-accounts
  stalwart-mailbox.sh get noor@gotalandstrafikskola.se
  stalwart-mailbox.sh create --domain gotalandstrafikskola.se --user test --password 'S3cur!Pass' --name Test User
  stalwart-mailbox.sh update-password --email noor@gotalandstrafikskola.se --password 'n00rzaff!GOT'
  stalwart-mailbox.sh delete --email test@gotalandstrafikskola.se
  stalwart-mailbox.sh add-alias --email hej@gotalandstrafikskola.se --alias info
  stalwart-mailbox.sh remove-alias --email wordpress@gotalandstrafikskola.se --alias info
  stalwart-mailbox.sh move-alias --from wordpress@gotalandstrafikskola.se --to hej@gotalandstrafikskola.se --alias info
  stalwart-mailbox.sh check-mail --email noor@gotalandstrafikskola.se
  stalwart-mailbox.sh health

Gotchas: credentials/aliases are MAPS {0:{...}} not arrays; locale is dash-form (sv-SE, en-US); JMAP is http://127.0.0.1:41209/jmap plain HTTP.
USAGE
}

cmd="${1:-help}"
shift || true

case "$cmd" in
  list-domains)
    stalwart-cli query domain
    ;;
  list-accounts)
    stalwart-cli query account
    ;;
  get)
    [[ $# -eq 1 ]] || die "usage: $0 get <email|id>"
    arg="$1"
    if [[ "$arg" == *@* ]]; then
      id=$(account_id_for "$arg")
      [[ -n "$id" ]] || die "account '$arg' not found"
      arg="$id"
    fi
    stalwart-cli get account "$arg"
    ;;
  domain-zone)
    [[ $# -eq 1 ]] || die "usage: $0 domain-zone <domain>"
    stalwart-cli get domain "$(domain_id_for "$1")"
    ;;
  create)
    DOMAIN=""; USER=""; PASS=""; NAME=""; LOCALE="sv-SE"
    while [[ $# -gt 0 ]]; do case "$1" in
      --domain) DOMAIN="$2"; shift 2;;
      --user) USER="$2"; shift 2;;
      --password) PASS="$2"; shift 2;;
      --name) NAME="$2"; shift 2;;
      --locale) LOCALE="$2"; shift 2;;
      *) die "unknown flag $1";;
    esac; done
    [[ -n "$DOMAIN" && -n "$USER" && -n "$PASS" ]] || die "need --domain, --user, --password"
    DID=$(domain_id_for "$DOMAIN")
    EMAIL="${USER}@${DOMAIN}"
    EXIST=$(account_id_for "$EMAIL")
    if [[ -n "$EXIST" ]]; then die "account $EMAIL already exists (id $EXIST) — use update-password or delete"; fi
    echo "Creating $EMAIL (domainId $DID, locale $LOCALE)..."
    stalwart-cli create Account/User       --field name="$USER"       --field domainId="$DID"       --field locale="$LOCALE"       --field "description=$NAME"       --field "credentials={\"0\":{\"@type\":\"Password\",\"secret\":\"$PASS\"}}"       --field 'aliases={}'       --field 'encryptionAtRest={"@type":"Disabled"}'       --field 'permissions={"@type":"Inherit"}'       --field 'roles={"@type":"User"}'       --field 'memberGroupIds={}'       --field 'quotas={}'
    echo "Created $EMAIL — verify: stalwart-mailbox.sh get $EMAIL"
    mkdir -p "$HOME/.secrets"
    echo "$EMAIL:$PASS" >> "$HOME/.secrets/mailboxes.txt"
    chmod 600 "$HOME/.secrets/mailboxes.txt" 2>/dev/null || true
    ;;
  update-password)
    EMAIL=""; PASS=""
    while [[ $# -gt 0 ]]; do case "$1" in
      --email) EMAIL="$2"; shift 2;;
      --password) PASS="$2"; shift 2;;
      *) die "unknown flag $1";;
    esac; done
    [[ -n "$EMAIL" && -n "$PASS" ]] || die "need --email and --password"
    ID=$(account_id_for "$EMAIL")
    [[ -n "$ID" ]] || die "account '$EMAIL' not found"
    stalwart-cli update account "$ID" --field "credentials={\"0\":{\"@type\":\"Password\",\"secret\":\"$PASS\"}}"
    echo "Updated password for $EMAIL (id $ID)"
    ;;
  delete)
    EMAIL=""
    while [[ $# -gt 0 ]]; do case "$1" in
      --email) EMAIL="$2"; shift 2;;
      *) EMAIL="$1"; shift;;
    esac; done
    [[ -n "$EMAIL" ]] || die "need --email"
    ID=$(account_id_for "$EMAIL")
    [[ -n "$ID" ]] || die "account '$EMAIL' not found"
    echo "Will delete $EMAIL (id $ID) — Ctrl-C to abort, Enter to confirm"
    read -r
    stalwart-cli delete account "$ID"
    echo "Deleted $EMAIL"
    ;;
  add-alias)
    EMAIL=""; ALIAS=""
    while [[ $# -gt 0 ]]; do case "$1" in
      --email) EMAIL="$2"; shift 2;;
      --alias) ALIAS="$2"; shift 2;;
      *) die "unknown flag $1";;
    esac; done
    [[ -n "$EMAIL" && -n "$ALIAS" ]] || die "need --email and --alias"
    ID=$(account_id_for "$EMAIL")
    [[ -n "$ID" ]] || die "account '$EMAIL' not found"
    # Parse alias local@domain
    if [[ "$ALIAS" == *@* ]]; then
      ALIAS_LOCAL="${ALIAS%@*}"
      ALIAS_DOMAIN="${ALIAS#*@}"
    else
      ALIAS_LOCAL="$ALIAS"
      ALIAS_DOMAIN="${EMAIL#*@}"
    fi
    ALIAS_DID=$(domain_id_for "$ALIAS_DOMAIN")
    CUR_JSON=$(_fetch_aliases_json "$ID")
    # Duplicate check
    if python3 -c "import json,sys; a=json.loads(sys.argv[1]); sys.exit(0 if any(v.get('name')==sys.argv[2] for v in a.values()) else 1)" "$CUR_JSON" "$ALIAS_LOCAL"; then
      die "alias $ALIAS_LOCAL@$ALIAS_DOMAIN already exists on $EMAIL (current: $CUR_JSON)"
    fi
    NEXT=$(python3 -c "import json,sys; a=json.loads(sys.argv[1]); print(max([int(k) for k in a.keys()], default=-1)+1)" "$CUR_JSON")
    NEW_JSON=$(python3 -c "import json,sys; cur=json.loads(sys.argv[1]); cur[sys.argv[2]]={'name':sys.argv[3],'domainId':sys.argv[4],'enabled':True}; print(json.dumps(cur, separators=(',',':')))" "$CUR_JSON" "$NEXT" "$ALIAS_LOCAL" "$ALIAS_DID")
    echo "Adding alias $ALIAS_LOCAL@$ALIAS_DOMAIN -> $EMAIL (domainId $ALIAS_DID, key $NEXT)"
    echo "Before: $CUR_JSON"
    _update_aliases "$ID" "$NEW_JSON"
    echo "After: $NEW_JSON"
    echo "Added alias $ALIAS_LOCAL@$ALIAS_DOMAIN -> $EMAIL"
    stalwart-cli get account "$ID" | grep -A 10 "Email Aliases"
    ;;
  remove-alias)
    EMAIL=""; ALIAS=""
    while [[ $# -gt 0 ]]; do case "$1" in
      --email) EMAIL="$2"; shift 2;;
      --alias) ALIAS="$2"; shift 2;;
      *) die "unknown flag $1";;
    esac; done
    [[ -n "$EMAIL" && -n "$ALIAS" ]] || die "need --email and --alias"
    ID=$(account_id_for "$EMAIL")
    [[ -n "$ID" ]] || die "account '$EMAIL' not found"
    if [[ "$ALIAS" == *@* ]]; then
      ALIAS_LOCAL="${ALIAS%@*}"
    else
      ALIAS_LOCAL="$ALIAS"
    fi
    CUR_JSON=$(_fetch_aliases_json "$ID")
    # Find key to remove
    KEY_TO_REMOVE=$(python3 -c "import json,sys; a=json.loads(sys.argv[1]); found=[k for k,v in a.items() if v.get('name')==sys.argv[2]]; print(found[0] if found else '')" "$CUR_JSON" "$ALIAS_LOCAL")
    if [[ -z "$KEY_TO_REMOVE" ]]; then
      die "alias $ALIAS_LOCAL not found on $EMAIL (current: $CUR_JSON)"
    fi
    NEW_JSON=$(python3 -c "
import json,sys
cur=json.loads(sys.argv[1])
key=sys.argv[2]
# Remove and reindex 0..n-1 to keep map compact
items=[v for k,v in sorted(cur.items(), key=lambda x: int(x[0])) if k != key]
new={str(i): v for i, v in enumerate(items)}
print(json.dumps(new, separators=(',',':')))
" "$CUR_JSON" "$KEY_TO_REMOVE")
    echo "Removing alias $ALIAS_LOCAL from $EMAIL (key $KEY_TO_REMOVE)"
    echo "Before: $CUR_JSON"
    _update_aliases "$ID" "$NEW_JSON"
    echo "After: $NEW_JSON"
    echo "Removed alias $ALIAS_LOCAL from $EMAIL"
    stalwart-cli get account "$ID" | grep -A 10 "Email Aliases"
    ;;
  move-alias)
    FROM=""; TO=""; ALIAS=""
    while [[ $# -gt 0 ]]; do case "$1" in
      --from) FROM="$2"; shift 2;;
      --to) TO="$2"; shift 2;;
      --alias) ALIAS="$2"; shift 2;;
      *) die "unknown flag $1";;
    esac; done
    [[ -n "$FROM" && -n "$TO" && -n "$ALIAS" ]] || die "need --from, --to, --alias"
    FROM_ID=$(account_id_for "$FROM")
    TO_ID=$(account_id_for "$TO")
    [[ -n "$FROM_ID" ]] || die "source '$FROM' not found"
    [[ -n "$TO_ID" ]] || die "dest '$TO' not found"
    if [[ "$ALIAS" == *@* ]]; then
      ALIAS_LOCAL="${ALIAS%@*}"
      ALIAS_DOMAIN="${ALIAS#*@}"
    else
      ALIAS_LOCAL="$ALIAS"
      ALIAS_DOMAIN="${FROM#*@}"
    fi
    # Verify source has alias
    CUR_FROM=$(_fetch_aliases_json "$FROM_ID")
    if ! python3 -c "import json,sys; a=json.loads(sys.argv[1]); sys.exit(0 if any(v.get('name')==sys.argv[2] for v in a.values()) else 1)" "$CUR_FROM" "$ALIAS_LOCAL"; then
      die "alias $ALIAS_LOCAL not found on source $FROM (current: $CUR_FROM)"
    fi
    # Check dest doesn't already have it
    CUR_TO=$(_fetch_aliases_json "$TO_ID")
    if python3 -c "import json,sys; a=json.loads(sys.argv[1]); sys.exit(0 if any(v.get('name')==sys.argv[2] for v in a.values()) else 1)" "$CUR_TO" "$ALIAS_LOCAL"; then
      die "alias $ALIAS_LOCAL already exists on dest $TO (current: $CUR_TO)"
    fi
    echo "Moving alias $ALIAS_LOCAL@$ALIAS_DOMAIN: $FROM -> $TO"
    # Remove from source
    "$0" remove-alias --email "$FROM" --alias "$ALIAS_LOCAL"
    # Add to dest
    "$0" add-alias --email "$TO" --alias "$ALIAS_LOCAL@$ALIAS_DOMAIN"
    echo "Moved alias $ALIAS_LOCAL@$ALIAS_DOMAIN $FROM -> $TO"
    ;;
  check-mail)
    EMAIL=""; PASS=""
    while [[ $# -gt 0 ]]; do case "$1" in
      --email) EMAIL="$2"; shift 2;;
      --password) PASS="$2"; shift 2;;
      *) EMAIL="$1"; shift;;
    esac; done
    [[ -n "$EMAIL" ]] || die "need --email (and optional --password)"
    python3 - "$EMAIL" "$PASS" <<'PY'
import glob, os, re, sys, ssl, imaplib

email_addr = sys.argv[1]
pw = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] else ""

if not pw:
    secrets_dir = os.path.expanduser("~/.secrets")
    mb_file = os.path.join(secrets_dir, "mailboxes.txt")
    if os.path.isfile(mb_file):
        with open(mb_file) as f:
            for line in f:
                line = line.strip()
                if line.startswith(email_addr + ":"):
                    pw = line.split(":", 1)[1].strip()
                    break

if not pw:
    secrets_dir = os.path.expanduser("~/.secrets")
    for env_path in sorted(glob.glob(os.path.join(secrets_dir, "*.env"))):
        try:
            with open(env_path) as f:
                env_lines = f.readlines()
        except OSError:
            continue
        env_vars = {}
        for line in env_lines:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            env_vars[k.strip()] = v.strip().strip("'\"")
        matching_keys = [k for k, v in env_vars.items() if v.lower() == email_addr.lower()]
        for mk in matching_keys:
            prefix = re.sub(r"_(EMAIL|USER)$", "", mk, flags=re.IGNORECASE)
            for cand in [f"{prefix}_PASSWORD", f"{prefix}_PASS", "PASSWORD", "PASS", "JMAP_PASSWORD"]:
                if cand in env_vars and env_vars[cand]:
                    pw = env_vars[cand]
                    break
            if not pw:
                pw_keys = [k for k in env_vars if "PASSWORD" in k]
                if len(pw_keys) == 1:
                    pw = env_vars[pw_keys[0]]
            if pw:
                break
        if pw:
            break

if not pw:
    sys.exit(f"ERROR: password not found for {email_addr} in ~/.secrets — pass --password")

ctx = ssl.create_default_context()
M = imaplib.IMAP4_SSL("mail.fullstacked.se", 993, ssl_context=ctx)
M.login(email_addr, pw)
M.select("INBOX")
typ, data = M.search(None, "ALL")
ids = data[0].split()
print(f"INBOX {email_addr}: {len(ids)} total")
for i in ids[-5:]:
    typ, d = M.fetch(i, "(BODY.PEEK[HEADER.FIELDS (FROM TO SUBJECT DATE)])")
    try:
        hdr = d[0][1].decode(errors="ignore").replace("\r", "").strip()
        hdr_lines = [l.strip() for l in hdr.split("\n") if l.strip()]
        print(f"--- #{i.decode()}: " + " | ".join(hdr_lines))
    except Exception:
        print("---", i.decode(), d)
M.logout()
PY
    ;;
  health)
    exec "${HOME}/dev/fullstacked-nixlab/scripts/mail-health-check.sh" "$@"
    ;;
  help|--help|-h|*)
    usage
    ;;
esac
