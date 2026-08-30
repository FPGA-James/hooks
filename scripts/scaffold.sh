#!/usr/bin/env sh
# Wire this hooks repo into the project that vendors it: create or extend the
# project-root .gitattributes and .editorconfig, add the hooks.mk include to the
# project Makefile, and install a CI workflow if there is none.
#
# Idempotent. The dotfile edits live inside marker-delimited blocks
#   # >>> hdl-git-hooks (managed) >>>
#   ...
#   # <<< hdl-git-hooks <<<
# so re-running refreshes only that block and leaves your own lines untouched.
#
# Run from the superproject after `git submodule add <url> deps/hooks`:
#   deps/hooks/scripts/scaffold.sh
set -eu

hooks_home=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
super=$(git rev-parse --show-superproject-working-tree 2>/dev/null || true)
[ -n "$super" ] || super=$(git rev-parse --show-toplevel)
super=$(CDPATH= cd -- "$super" && pwd -P)

if [ "$hooks_home" = "$super" ]; then
  printf 'scaffold: standalone checkout (hooks are at the repo root) — nothing to do.\n' >&2
  printf '          run scripts/install-hooks.sh instead.\n' >&2
  exit 0
fi

# hooks dir as a path relative to the project root
case "$hooks_home/" in
  "$super"/*) rel=${hooks_home#"$super"/} ;;
  *)          rel=$hooks_home ;;
esac

BEGIN="# >>> hdl-git-hooks (managed) >>>"
END="# <<< hdl-git-hooks <<<"

strip_block() {   # stdin -> stdout, remove BEGIN..END inclusive
  awk -v b="$BEGIN" -v e="$END" '
    $0==b { inblk=1; next }
    inblk && $0==e { inblk=0; next }
    !inblk { print }
  '
}

trim_trailing() { # stdin -> stdout, drop trailing blank lines
  awk '{ l[NR]=$0 }
       END { n=NR; while (n>0 && l[n] ~ /^[ \t]*$/) n--; for (i=1;i<=n;i++) print l[i] }'
}

merge_block() {   # $1 = project-relative target, $2 = absolute template file
  target=$super/$1
  if [ -e "$target" ]; then
    kept=$(strip_block < "$target" | trim_trailing)
    verb=updated
  else
    kept=""
    verb=created
  fi
  {
    [ -n "$kept" ] && printf '%s\n\n' "$kept"
    printf '%s\n' "$BEGIN"
    cat "$2"
    printf '%s\n' "$END"
  } > "$target"
  printf 'scaffold: %s %s\n' "$verb" "$1"
}

# --- .gitattributes: append the template verbatim -------------------------
merge_block .gitattributes "$hooks_home/examples/gitattributes"

# --- .editorconfig: keep `root = true` only when creating it fresh --------
if [ -e "$super/.editorconfig" ]; then
  t=$(mktemp "${TMPDIR:-/tmp}/ec.XXXXXX")
  grep -v '^root = true' "$hooks_home/examples/editorconfig" > "$t"
  merge_block .editorconfig "$t"
  rm -f "$t"
else
  merge_block .editorconfig "$hooks_home/examples/editorconfig"
fi

# --- Makefile: add the include once -------------------------------------
mk=$super/Makefile
if [ -e "$mk" ] && grep -qF "$rel/hooks.mk" "$mk"; then
  printf 'scaffold: Makefile already includes %s/hooks.mk\n' "$rel"
elif [ -e "$mk" ]; then
  printf '\ninclude %s/hooks.mk\n' "$rel" >> "$mk"
  printf 'scaffold: appended the hooks.mk include to Makefile\n'
else
  printf 'include %s/hooks.mk\n' "$rel" > "$mk"
  printf 'scaffold: created Makefile with the hooks.mk include\n'
fi

# --- CI workflow: never overwrite -------------------------------------
wf=$super/.github/workflows/hdl.yml
if [ -e "$wf" ]; then
  printf 'scaffold: .github/workflows/hdl.yml exists — see %s/examples/hdl.yml to merge the hook steps in\n' "$rel"
else
  mkdir -p "$super/.github/workflows"
  sed "s#deps/hooks#$rel#g" "$hooks_home/examples/hdl.yml" > "$wf"
  printf 'scaffold: created .github/workflows/hdl.yml (HOOKS_DIR=%s)\n' "$rel"
fi

printf 'scaffold: done — review the changes, then commit them.\n'
