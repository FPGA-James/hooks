#!/usr/bin/env sh
# Bump the "Date Updated :" line in HDL file headers to today's date.
# Usage: header-stamp.sh FILE [FILE ...]
# Prints each file it changed. Exit status is always 0.

set -u

today=$(date +%Y-%m-%d)
# Comment leader (-- or //), optional spaces, "Date Updated", spaces, ":", rest.
re='^([[:space:]]*(--|//)[[:space:]]*Date Updated[[:space:]]*:[[:space:]]*).*$'

for f in "$@"; do
  [ -f "$f" ] || continue
  grep -Eq "$re" "$f" || continue

  tmp=$(mktemp "${TMPDIR:-/tmp}/stamp.XXXXXX") || {
    printf 'hooks: could not create temp file for %s\n' "$f" >&2
    continue
  }
  sed -E "s#$re#\\1${today}#" "$f" > "$tmp"

  if cmp -s "$f" "$tmp"; then
    rm -f "$tmp"
  else
    cat "$tmp" > "$f" && printf '%s\n' "$f"
    rm -f "$tmp"
  fi
done

exit 0
