#!/usr/bin/env sh
# Whole-design elaboration lint. Reads a newline-separated HDL file list on
# stdin. Arg 1 is the mode: "local" (missing tools warn and pass) or "ci"
# (missing tools / missing config are hard failures).
set -u
HOOK_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck disable=SC1091
. "$HOOK_DIR/lib/common.sh"

mode=${1:-local}
have_sv=0
vhd=''
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case $(lang_of "$f") in
    sv)   have_sv=1 ;;
    vhdl) vhd="$vhd $f" ;;
  esac
done

fail=0
_miss() {  # tool, step  -> warn+ok in local, error+fail in ci
  if [ "$mode" = ci ]; then
    log_error "$1 required in CI: $2"
    fail=1
  else
    missing_tool_notice "$1" "$2"
  fi
}

if [ "$have_sv" -eq 1 ]; then
  if have_tool verilator; then
    if [ -f "$REPO_ROOT/$verilator_filelist" ]; then
      if ! ( cd "$REPO_ROOT" && verilator --lint-only -Wall -f "$verilator_filelist" ); then
        log_error "verilator --lint-only failed"
        fail=1
      fi
    else
      msg="verilator_filelist '$verilator_filelist' not found; SV elaboration lint unconfigured"
      if [ "$mode" = ci ]; then
        log_error "$msg"
        fail=1
      else
        log_warn "$msg"
      fi
    fi
  else
    _miss verilator "SystemVerilog elaboration lint"
  fi
fi

if [ -n "$vhd" ]; then
  if have_tool ghdl; then
    if [ "${ghdl_analyze:-0}" = "1" ]; then
      wd=$(mktemp -d "${TMPDIR:-/tmp}/ghdl.XXXXXX")
      set -- -a "--workdir=$wd" "--std=$vhdl_std"
    else
      set -- -s "--std=$vhdl_std"
    fi
    # shellcheck disable=SC2086
    if ! ( cd "$REPO_ROOT" && ghdl "$@" $vhd ); then
      log_error "ghdl reported errors"
      fail=1
    fi
    [ -n "${wd:-}" ] && rm -rf "$wd"
  else
    _miss ghdl "VHDL analysis"
  fi
fi

exit "$fail"
