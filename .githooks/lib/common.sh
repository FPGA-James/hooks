# Shared helpers for the project git hooks. Sourced by hooks and dispatch
# scripts; never executed directly.

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'hooks: not inside a git work tree\n' >&2
  exit 1
}

# --- configuration: defaults, then hooks.conf overrides ---------------------

enable_format=1
enable_lint=1
enable_header_stamp=1
commit_msg_enforce=1
commit_msg_max_subject=72
verible_lint_rules=.rules.verible_lint
vhdl_std=08
ghdl_analyze=0
verilator_filelist=rtl.f
vsg_config=.vsg.yaml

if [ -f "$REPO_ROOT/hooks.conf" ]; then
  # shellcheck disable=SC1091
  . "$REPO_ROOT/hooks.conf"
fi

# --- logging --------------------------------------------------------------

if [ -t 2 ]; then
  _c_red=$(printf '\033[31m'); _c_yel=$(printf '\033[33m')
  _c_dim=$(printf '\033[2m'); _c_rst=$(printf '\033[0m')
else
  _c_red=''; _c_yel=''; _c_dim=''; _c_rst=''
fi

log_info()  { printf '%shooks:%s %s\n' "$_c_dim" "$_c_rst" "$*" >&2; }
log_warn()  { printf '%shooks: %s%s\n' "$_c_yel" "$*" "$_c_rst" >&2; }
log_error() { printf '%shooks: %s%s\n' "$_c_red" "$*" "$_c_rst" >&2; }

missing_tool_notice() {
  log_warn "$1 not found on PATH; skipping $2 (CI still enforces it)"
}

# --- tool + file helpers ------------------------------------------------

have_tool() { command -v "$1" >/dev/null 2>&1; }

lang_of() {
  case $1 in
    *.sv|*.svh|*.v|*.vh) printf 'sv\n' ;;
    *.vhd|*.vhdl)        printf 'vhdl\n' ;;
    *)                   : ;;
  esac
}

_is_hdl() { [ -n "$(lang_of "$1")" ]; }

staged_hdl_files() {
  git diff --cached --name-only --diff-filter=ACM | while IFS= read -r f; do
    if _is_hdl "$f" && [ -f "$REPO_ROOT/$f" ]; then
      printf '%s\n' "$f"
    fi
  done
}

tracked_hdl_files() {
  git ls-files | while IFS= read -r f; do
    _is_hdl "$f" && printf '%s\n' "$f"
  done
}

skip_requested() {
  case ",${HOOKS_SKIP:-}," in
    *",$1,"*|*",all,"*) return 0 ;;
    *) return 1 ;;
  esac
}
