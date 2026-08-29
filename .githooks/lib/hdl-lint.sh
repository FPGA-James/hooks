#!/usr/bin/env sh
# Run verible-verilog-lint on the SystemVerilog files among the arguments.
# VHDL files are ignored here (vsg handles VHDL from hdl-format.sh).
set -u
HOOK_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck disable=SC1091
. "$HOOK_DIR/lib/common.sh"

sv=''
for f in "$@"; do
  [ "$(lang_of "$f")" = sv ] && sv="$sv $f"
done
[ -n "$sv" ] || exit 0

if ! have_tool verible-verilog-lint; then
  missing_tool_notice verible-verilog-lint "SystemVerilog lint"
  exit 0
fi

rules_arg=''
[ -f "$REPO_ROOT/$verible_lint_rules" ] && \
  rules_arg="--rules_config=$REPO_ROOT/$verible_lint_rules"

# shellcheck disable=SC2086
if ! verible-verilog-lint $rules_arg $sv; then
  log_error "verible-verilog-lint reported violations (above)"
  exit 1
fi
exit 0
