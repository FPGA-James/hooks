#!/usr/bin/env sh
# Check (or, with HOOKS_AUTOFORMAT=1, apply) formatting of the given HDL files.
# SV  -> verible-verilog-format
# VHD -> vsg (covers style + formatting)
#
# stdout is a machine-readable channel: under HOOKS_AUTOFORMAT=1 it carries one
# path per line for every file rewritten in place (same contract as
# header-stamp.sh, so pre-commit can re-stage them). Nothing else is written to
# stdout; all human-facing text goes to stderr via log_*.
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
fmted=''

if [ -n "$sv" ]; then
  if have_tool verible-verilog-format; then
    for f in $sv; do
      if [ "$autofmt" != "1" ]; then
        if ! verible-verilog-format "$f" | cmp -s - "$f"; then
          bad="$bad $f"
        fi
      elif verible-verilog-format "$f" | cmp -s - "$f"; then
        :  # already canonical; nothing to rewrite
      elif ! verible-verilog-format --inplace "$f"; then
        log_error "verible-verilog-format --inplace failed on $f"
        bad="$bad $f"
      elif verible-verilog-format "$f" | cmp -s - "$f"; then
        printf '%s\n' "$f"
        fmted="$fmted $f"
      else
        # --inplace reported success but the file is still not canonical:
        # almost always a parse error (verible leaves the file untouched).
        log_error "verible-verilog-format could not format $f (syntax error?)"
        bad="$bad $f"
      fi
    done
  else
    missing_tool_notice verible-verilog-format "SystemVerilog format check"
  fi
fi

if [ -n "$vhd" ]; then
  if have_tool vsg; then
    # Build the config flag as positional parameters so a path containing a
    # space survives; "$@" is free here (the file list lives in $vhd).
    # resolve_conf checks the project root first, then the bundled copy.
    vsgcfg=$(resolve_conf "$vsg_config")
    if [ -n "$vsgcfg" ]; then
      set -- -c "$vsgcfg"
    else
      set --
    fi
    for f in $vhd; do
      if [ "$autofmt" = "1" ]; then
        before=$(mktemp "${TMPDIR:-/tmp}/vsgfix.XXXXXX") || {
          log_error "could not create a temp file to check $f"
          bad="$bad $f"
          continue
        }
        cat "$f" > "$before"
        vsg_rc=0
        vsg "$@" --fix -f "$f" >/dev/null 2>&1 || vsg_rc=$?
        cmp -s "$before" "$f" || { printf '%s\n' "$f"; fmted="$fmted $f"; }
        rm -f "$before"
        if [ "$vsg_rc" != "0" ]; then
          log_error "vsg --fix could not fully fix $f (violations remain)"
          bad="$bad $f"
        fi
      else
        # Keep vsg's rule report: capture it and re-emit on stderr, so stdout
        # stays reserved for the auto-format path's machine-readable list.
        if ! out=$(vsg "$@" -f "$f" 2>&1); then
          bad="$bad $f"
          printf '%s\n' "$out" >&2
        fi
      fi
    done
  else
    missing_tool_notice vsg "VHDL style/format check"
  fi
fi

if [ -n "$bad" ]; then
  if [ "$autofmt" = "1" ]; then
    log_error "could not auto-format:$bad"
  else
    log_error "these files are not formatted:$bad"
    log_error "  fix with: make format   (SV: verible-verilog-format --inplace <file>)"
  fi
  exit 1
fi

[ "$autofmt" = "1" ] && [ -n "$fmted" ] && log_info "auto-formatted:$fmted"
exit 0
