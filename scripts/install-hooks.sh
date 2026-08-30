#!/usr/bin/env sh
# One-time per clone: point git at this repo's .githooks/ directory and report
# tool availability.
#
# Works whether this repo IS the project or is vendored into a larger project
# (e.g. a git submodule at deps/hooks, tools/hooks, third_party/hooks, ...).
# Run it from anywhere:
#   ./scripts/install-hooks.sh            # standalone repo
#   deps/hooks/scripts/install-hooks.sh   # from a superproject that vendors it
#
# Needs git >= 2.13 for reliable submodule detection when run from inside the
# submodule directory; git >= 2.9 for relative core.hooksPath resolution.
set -eu

# Absolute, symlink-resolved path to the directory that contains .githooks/
# (this repo's root, wherever it has been placed). pwd -P so it compares
# cleanly against git's own physical paths below.
hooks_home=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)

# The worktree whose git config we set. When these hooks are inside a submodule
# that is the SUPERPROJECT, not the submodule itself.
super=$(git rev-parse --show-superproject-working-tree 2>/dev/null || true)
[ -n "$super" ] || super=$(git rev-parse --show-toplevel)
worktree=$(CDPATH= cd -- "$super" && pwd -P)

chmod +x "$hooks_home/.githooks/pre-commit" \
         "$hooks_home/.githooks/commit-msg" \
         "$hooks_home/.githooks/pre-push" 2>/dev/null || true
chmod +x "$hooks_home"/.githooks/lib/*.sh 2>/dev/null || true

# git resolves a relative core.hooksPath against the worktree root (git >= 2.9).
# Use a relative path when .githooks lives inside that worktree, absolute if not.
if [ "$hooks_home" = "$worktree" ]; then
  hooks_path=.githooks
else
  case "$hooks_home/" in
    "$worktree"/*) hooks_path="${hooks_home#"$worktree"/}/.githooks" ;;
    *)             hooks_path="$hooks_home/.githooks" ;;
  esac
fi

git -C "$worktree" config core.hooksPath "$hooks_path"
printf 'hooks: core.hooksPath -> %s   (worktree: %s)\n' "$hooks_path" "$worktree"

printf 'hooks: tool availability (missing tools are skipped locally, enforced in CI):\n'
for t in verible-verilog-format verible-verilog-lint verilator vsg ghdl bats; do
  if command -v "$t" >/dev/null 2>&1; then
    printf '  ok    %s\n' "$t"
  else
    printf '  --    %s\n' "$t"
  fi
done
