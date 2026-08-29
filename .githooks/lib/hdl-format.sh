#!/usr/bin/env sh
# Check (or, with HOOKS_AUTOFORMAT=1, apply) formatting of the given HDL files.
# SV  -> verible-verilog-format
# VHD -> vsg (covers style + formatting)
set -u
HOOK_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck disable=SC1091
. "$HOOK_DIR/lib/common.sh"

sv='' vhd=''
for f in "$@"; do
  case $(lang_of "$f") in
    sv)   sv="$sv $f" ;;
    vhdl) vhd="$vhd $f" ;;
  esac
done

autofmt=${HOOKS_AUTOFORMAT:-0}
bad=''

if [ -n "$sv" ]; then
  if have_tool verible-verilog-format; then
    for f in $sv; do
      if [ "$autofmt" = "1" ]; then
        verible-verilog-format --inplace "$f"
      elif ! verible-verilog-format "$f" | cmp -s - "$f"; then
        bad="$bad $f"
      fi
    done
  else
    missing_tool_notice verible-verilog-format "SystemVerilog format check"
  fi
fi

if [ -n "$vhd" ]; then
  if have_tool vsg; then
    cfg="$REPO_ROOT/$vsg_config"
    [ -f "$cfg" ] && cfg_arg="-c $cfg" || cfg_arg=''
    for f in $vhd; do
      if [ "$autofmt" = "1" ]; then
        # shellcheck disable=SC2086
        vsg $cfg_arg --fix -f "$f" >/dev/null 2>&1 || true
      # shellcheck disable=SC2086
      elif ! vsg $cfg_arg -f "$f" >/dev/null 2>&1; then
        bad="$bad $f"
      fi
    done
  else
    missing_tool_notice vsg "VHDL style/format check"
  fi
fi

if [ "$autofmt" = "1" ]; then
  [ -n "$sv$vhd" ] && log_info "auto-formatted:$sv$vhd"
  exit 0
fi

if [ -n "$bad" ]; then
  log_error "these files are not formatted:$bad"
  log_error "  fix with: make format   (SV: verible-verilog-format --inplace <file>)"
  exit 1
fi
exit 0
