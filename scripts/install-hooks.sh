#!/usr/bin/env sh
# One-time per clone: point git at .githooks/ and report tool availability.
set -eu

root=$(git rev-parse --show-toplevel)
cd "$root"

chmod +x .githooks/pre-commit .githooks/commit-msg .githooks/pre-push 2>/dev/null || true
chmod +x .githooks/lib/*.sh 2>/dev/null || true

git config core.hooksPath .githooks
printf 'hooks: core.hooksPath -> .githooks\n'

printf 'hooks: tool availability (missing tools are skipped locally, enforced in CI):\n'
for t in verible-verilog-format verible-verilog-lint verilator vsg ghdl bats; do
  if command -v "$t" >/dev/null 2>&1; then
    printf '  ok    %s\n' "$t"
  else
    printf '  --    %s\n' "$t"
  fi
done
