#!/usr/bin/env bash
# place-decoys.sh — put canarytokens.org decoys where an intruder would look.
#
# You create each token yourself on https://canarytokens.org (free, no account; it
# asks only for the email that gets the alerts). This script only places the files
# you got from there. It makes no network calls and never triggers a decoy.
#
# Usage:
#   ./place-decoys.sh aws   <file with the AWS token text> [--profile NAME]
#   ./place-decoys.sh ssh   <canary hostname> [alias]
#   ./place-decoys.sh mysql <downloaded .sql dump or snippet file> [name.sql]
#   ./place-decoys.sh pdf   <downloaded .pdf> [name.pdf]
#   ./place-decoys.sh status
#
# Nothing is ever overwritten. Works with the bash 3.2 that ships with macOS.

set -euo pipefail

DOCS_DIR="${DECOY_DOCS_DIR:-$HOME/Documents}"
# Backdate placed files so they don't look freshly planted (YYYYMMDDhhmm).
BACKDATE="${DECOY_BACKDATE:-$(date -v-21d +%Y%m%d%H%M 2>/dev/null || date -d '21 days ago' +%Y%m%d%H%M)}"

die()  { echo "error: $*" >&2; exit 1; }
ok()   { echo "done: $*"; }
note() { echo "note: $*"; }

finish_file() {  # owner-only, backdated
  chmod 600 "$1"
  touch -t "$BACKDATE" "$1" 2>/dev/null || true
}

place_aws() {
  local src="${1:-}" profile="default"
  [ -f "$src" ] || die "give the file you saved the AWS token text into"
  shift
  if [ "${1:-}" = "--profile" ]; then profile="${2:-}"; [ -n "$profile" ] || die "--profile needs a name"; fi

  local key secret
  key=$(sed -nE 's/^[[:space:]]*aws_access_key_id[[:space:]]*=[[:space:]]*([A-Z0-9]+).*/\1/p' "$src" | head -1)
  secret=$(sed -nE 's/^[[:space:]]*aws_secret_access_key[[:space:]]*=[[:space:]]*([A-Za-z0-9/+]+).*/\1/p' "$src" | head -1)
  [[ "$key" =~ ^AKIA[A-Z0-9]{16}$ ]] || die "no AWS access key id found in $src"
  [ ${#secret} -eq 40 ] || die "no 40-character AWS secret found in $src"

  mkdir -p "$HOME/.aws"; chmod 700 "$HOME/.aws"
  local creds="$HOME/.aws/credentials"
  if [ -e "$creds" ]; then
    # A real credentials file is already here. Never touch the default profile.
    [ "$profile" != "default" ] || die "$creds already exists (maybe real keys). Re-run with --profile NAME, e.g. --profile backup-admin, to add the decoy as an extra profile."
    grep -qE "^\[$profile\]" "$creds" && die "profile [$profile] already exists in $creds"
    cp -p "$creds" "$creds.before-decoy"
    printf '\n[%s]\naws_access_key_id = %s\naws_secret_access_key = %s\n' "$profile" "$key" "$secret" >> "$creds"
    chmod 600 "$creds"
    ok "added decoy profile [$profile] to $creds (backup: $creds.before-decoy)"
  else
    printf '[%s]\naws_access_key_id = %s\naws_secret_access_key = %s\n' "$profile" "$key" "$secret" > "$creds"
    finish_file "$creds"
    if [ ! -e "$HOME/.aws/config" ]; then
      printf '[default]\nregion = us-east-2\noutput = json\n' > "$HOME/.aws/config"
      finish_file "$HOME/.aws/config"
    fi
    ok "placed decoy AWS key in $creds"
  fi
  note "you can now delete $src"
}

place_ssh() {
  local host="${1:-}" alias="${2:-db-backup}"
  [[ "$host" =~ ^[a-z0-9]+\.canarytokens\.(com|net|org)$ ]] || die "give the DNS token hostname, like abc123.canarytokens.com"
  [[ "$alias" =~ ^[A-Za-z0-9._-]+$ ]] || die "alias may only use letters, digits, dot, dash, underscore"
  mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
  local cfg="$HOME/.ssh/config"
  if [ -e "$cfg" ] && grep -qiE "^[[:space:]]*Host[[:space:]].*\b$alias\b" "$cfg"; then
    die "a Host named $alias is already in $cfg"
  fi
  [ -e "$cfg" ] && cp -p "$cfg" "$cfg.before-decoy"
  # A Host line always starts a new block, so appending can't change earlier entries.
  printf '\nHost %s\n  HostName %s\n  User admin\n' "$alias" "$host" >> "$cfg"
  chmod 600 "$cfg"
  ok "added decoy server '$alias' to $cfg — don't ssh to it yourself"
}

place_mysql() {
  local src="${1:-}" name="${2:-client-export.sql}"
  [ -f "$src" ] || die "give the .sql dump (or snippet) you downloaded"
  grep -q "FROM_BASE64" "$src" && grep -qiE "canarytokens|SET @b *=" "$src" \
    || die "$src doesn't look like a canarytokens MySQL file"
  local dest="$DOCS_DIR/$name"
  [ -e "$dest" ] && die "$dest already exists"
  mkdir -p "$DOCS_DIR"
  cp "$src" "$dest"
  finish_file "$dest"
  ok "placed decoy database export at $dest"
}

pdf_has_risky_actions() {  # returns 0 if it finds scripts, launch actions or embedded files
  local f="$1"
  LC_ALL=C grep -aqE '/(JavaScript|JS|Launch|EmbeddedFile|RichMedia|XFA|SubmitForm)\b' "$f" && return 0
  # Most objects are compressed; look inside them too when python3 is around.
  if command -v python3 >/dev/null 2>&1; then
    python3 -I - "$f" <<'PY' && return 0
import re, sys, zlib
d = open(sys.argv[1], 'rb').read()
for m in re.finditer(rb'stream\r?\n', d):
    raw = d[m.end():d.find(b'endstream', m.end())]
    try:
        t = zlib.decompressobj().decompress(raw)
    except Exception:
        continue
    if re.search(rb'/(JavaScript|JS|Launch|EmbeddedFile|RichMedia|XFA|SubmitForm)\b', t):
        sys.exit(0)
sys.exit(1)
PY
  else
    note "python3 not found: only the uncompressed parts of the PDF were checked"
  fi
  return 1
}

place_pdf() {
  local src="${1:-}" name="${2:-Client fees 2026.pdf}"
  [ -f "$src" ] || die "give the .pdf you downloaded"
  [ "$(head -c 5 "$src")" = "%PDF-" ] || die "$src is not a PDF"
  pdf_has_risky_actions "$src" && die "$src contains scripts or embedded files — not placing it"
  local dest="$DOCS_DIR/$name"
  [ -e "$dest" ] && die "$dest already exists"
  mkdir -p "$DOCS_DIR"
  cp "$src" "$dest"
  finish_file "$dest"
  ok "placed decoy PDF at $dest"
}

status() {
  # Reports only where decoys are; never prints key values.
  if [ -f "$HOME/.aws/credentials" ] && grep -q "aws_access_key_id" "$HOME/.aws/credentials"; then
    echo "aws:   ~/.aws/credentials has $(grep -c '^\[' "$HOME/.aws/credentials") profile(s)"
  else echo "aws:   none"; fi
  if [ -f "$HOME/.ssh/config" ] && grep -qE "canarytokens\.(com|net|org)" "$HOME/.ssh/config"; then
    echo "ssh:   decoy host in ~/.ssh/config"
  else echo "ssh:   none"; fi
  local f found=0
  for f in "$DOCS_DIR"/*.sql; do
    [ -f "$f" ] && grep -q "FROM_BASE64" "$f" && { echo "sql:   $f"; found=1; }
  done
  for f in "$DOCS_DIR"/*.pdf; do
    [ -f "$f" ] && pdf_mentions_canary "$f" && { echo "pdf:   $f"; found=1; }
  done
  [ "$found" = 1 ] || echo "files: no decoy .sql/.pdf in $DOCS_DIR"
}

pdf_mentions_canary() {  # the PDF's trigger link is usually inside a compressed object
  LC_ALL=C grep -aq "canarytokens" "$1" && return 0
  command -v python3 >/dev/null 2>&1 || return 1
  python3 -I - "$1" <<'PY'
import re, sys, zlib
d = open(sys.argv[1], 'rb').read()
for m in re.finditer(rb'stream\r?\n', d):
    try:
        if b'canarytokens' in zlib.decompressobj().decompress(d[m.end():d.find(b'endstream', m.end())]):
            sys.exit(0)
    except Exception:
        pass
sys.exit(1)
PY
}

cmd="${1:-}"; [ $# -gt 0 ] && shift
case "$cmd" in
  aws)    place_aws "$@" ;;
  ssh)    place_ssh "$@" ;;
  mysql)  place_mysql "$@" ;;
  pdf)    place_pdf "$@" ;;
  status) status ;;
  *)      sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
