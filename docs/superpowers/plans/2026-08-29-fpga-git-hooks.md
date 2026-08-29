# FPGA Git Hooks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a dependency-light set of Git hooks that format/lint staged HDL, keep file-header `Date Updated:` current, enforce Conventional Commits, and run a whole-design elaboration lint before push.

**Architecture:** Hooks are POSIX `sh` scripts under a versioned `.githooks/` directory, activated per clone with `git config core.hooksPath .githooks` via `make install`. A shared `lib/common.sh` provides config loading, tool detection, and file filtering; per-concern dispatch scripts (`hdl-format.sh`, `hdl-lint.sh`, `hdl-elaborate.sh`, `header-stamp.sh`) are called by the `pre-commit`, `commit-msg`, and `pre-push` hooks and reused by `make` targets and CI so local and CI checks cannot drift.

**Tech Stack:** POSIX shell, Git hooks (`core.hooksPath`), `bats-core` for tests, Verible (`verible-verilog-format`, `verible-verilog-lint`), Verilator, VHDL Style Guide (`vsg`), GHDL, GNU Make, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-08-29-fpga-git-hooks-design.md`

## Global Constraints

- Hook scripts are POSIX `sh` (`#!/usr/bin/env sh`), no Bash-only syntax; `bats`, `vsg`, Verible, Verilator, GHDL are dev/CI tools, never required for a hook to run.
- Delivery is `git config core.hooksPath .githooks`; hooks are never auto-installed on clone — `make install` is a documented one-time step.
- Missing tool locally ⇒ `log_warn` and skip that step, never fail. The same condition in CI (`mode = ci`) ⇒ hard fail.
- No `post-commit` and no `git commit --amend` anywhere. Commit-message text is never written into files.
- The template `Revision History` table is a manual, reviewed edit — no hook touches it. Only the single `Date Updated :` header line is auto-stamped.
- Conventional Commits types: `feat fix docs style refactor perf test build ci chore revert`. Subject (text after `: `) length limit default 72, config key `commit_msg_max_subject`.
- HDL file extensions: SystemVerilog/Verilog `.sv .svh .v .vh`; VHDL `.vhd .vhdl`.
- File paths handled by the hooks are assumed free of spaces and newlines (standard HDL project convention); this is documented, not defended against.
- Every commit in this plan uses a Conventional Commits message (the repo will enforce it once Task 5 lands).

## File Structure

Created by this plan:

```
.githooks/
  pre-commit              # Task 4  — orchestrates format -> lint -> stamp on staged HDL
  commit-msg              # Task 5  — Conventional Commits validation
  pre-push                # Task 6  — whole-design elaboration lint
  lib/
    common.sh             # Task 1  — config load, logging, tool + file helpers (sourced)
    header-stamp.sh        # Task 2  — bump "Date Updated :" line; standalone + testable
    hdl-format.sh          # Task 3  — verible-verilog-format check / vsg (VHDL) style check
    hdl-lint.sh            # Task 3  — verible-verilog-lint (SV only)
    hdl-elaborate.sh       # Task 6  — verilator --lint-only / ghdl, local|ci modes
scripts/
  install-hooks.sh         # Task 1  — chmod + set core.hooksPath + report tool availability
hooks.conf                 # Task 1  — committed default config, sourced by common.sh
Makefile                   # Task 1 (skeleton), extended in Tasks 2,3,6
.rules.verible_lint        # Task 3  — Verible lint rule config (starting set)
.vsg.yaml                  # Task 3  — vsg config (only consulted when VHDL present)
.gitattributes             # Task 1  — force LF on HDL + shell sources
.editorconfig              # Task 1  — indentation matching Verible/vsg defaults
.github/workflows/hdl.yml  # Task 7  — CI running make lint + make elaborate + make test
docs/hooks.md              # Task 7  — developer documentation
tests/
  helpers.bash             # Task 1  — temp-repo fixture setup for bats
  test_common.bats         # Task 1
  test_header_stamp.bats   # Task 2
  test_format_lint.bats    # Task 3
  test_pre_commit.bats     # Task 4
  test_commit_msg.bats     # Task 5
  test_pre_push.bats       # Task 6
```

`README.md` gets a "Git hooks" section in Task 7.

---

## Task 1: Foundation — shared library, config, installer, fixtures

**Files:**
- Create: `.githooks/lib/common.sh`
- Create: `hooks.conf`
- Create: `scripts/install-hooks.sh`
- Create: `Makefile`
- Create: `.gitattributes`
- Create: `.editorconfig`
- Create: `tests/helpers.bash`
- Test: `tests/test_common.bats`

**Interfaces:**
- Consumes: nothing (first task).
- Produces, all defined in `.githooks/lib/common.sh` and available to any script that does `. "$HOOK_DIR/lib/common.sh"`:
  - Shell variable `REPO_ROOT` — absolute path to the work-tree root.
  - Config variables with defaults, overridable by `hooks.conf`: `enable_format` `enable_lint` `enable_header_stamp` `commit_msg_enforce` (all `1`), `commit_msg_max_subject` (`72`), `verible_lint_rules` (`.rules.verible_lint`), `vhdl_std` (`08`), `ghdl_analyze` (`0`), `verilator_filelist` (`rtl.f`), `vsg_config` (`.vsg.yaml`).
  - `have_tool NAME` → exit 0 if `NAME` is on `PATH`.
  - `lang_of PATH` → prints `sv` or `vhdl` or nothing (newline-terminated when non-empty).
  - `staged_hdl_files` → prints staged (A/C/M) HDL paths that exist on disk, one per line.
  - `tracked_hdl_files` → prints all tracked HDL paths, one per line.
  - `skip_requested STEP` → exit 0 if `STEP` or `all` is in comma-separated `HOOKS_SKIP`.
  - `log_info MSG` / `log_warn MSG` / `log_error MSG` → `hooks:`-prefixed line on stderr, colour only on a TTY.
  - `missing_tool_notice TOOL STEP` → one standard `log_warn` line; callers then skip the step.
- Produces `tests/helpers.bash` with shell functions `setup_repo` (creates a temp git repo, copies `.githooks/`, `hooks.conf`, and any dotfile configs into it, sets `core.hooksPath`, `chmod +x` the hooks) and `teardown_repo` (removes the temp dir). Sets `$TESTDIR` and leaves the shell `cd`'d into it.

- [ ] **Step 1: Write the failing test**

Create `tests/test_common.bats`:

```bash
load helpers

setup() { setup_repo; }
teardown() { teardown_repo; }

@test "lang_of classifies extensions" {
  run sh -c '. .githooks/lib/common.sh; lang_of a.sv; lang_of b.vhd; lang_of c.txt'
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "sv" ]
  [ "${lines[1]}" = "vhdl" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "config defaults load when hooks.conf absent" {
  rm -f hooks.conf
  run sh -c '. .githooks/lib/common.sh; echo "$commit_msg_max_subject/$enable_format"'
  [ "$output" = "72/1" ]
}

@test "hooks.conf overrides a default" {
  echo 'commit_msg_max_subject=50' > hooks.conf
  run sh -c '. .githooks/lib/common.sh; echo "$commit_msg_max_subject"'
  [ "$output" = "50" ]
}

@test "staged_hdl_files lists only staged, on-disk HDL" {
  printf 'module m; endmodule\n' > keep.sv
  printf 'entity e is end;\n'   > keep.vhd
  echo hi > notes.txt
  git add keep.sv keep.vhd notes.txt
  run sh -c '. .githooks/lib/common.sh; staged_hdl_files'
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qx keep.sv
  printf '%s\n' "$output" | grep -qx keep.vhd
  ! printf '%s\n' "$output" | grep -qx notes.txt
}

@test "skip_requested honours HOOKS_SKIP and 'all'" {
  run sh -c 'HOOKS_SKIP=lint,stamp; . .githooks/lib/common.sh; skip_requested lint && echo yes'
  [ "$output" = "yes" ]
  run sh -c 'HOOKS_SKIP=all; . .githooks/lib/common.sh; skip_requested format && echo yes'
  [ "$output" = "yes" ]
  run sh -c 'HOOKS_SKIP=; . .githooks/lib/common.sh; skip_requested lint || echo no'
  [ "$output" = "no" ]
}

@test "have_tool true for sh, false for a bogus name" {
  run sh -c '. .githooks/lib/common.sh; have_tool sh && ! have_tool definitely-not-a-tool-xyz && echo ok'
  [ "$output" = "ok" ]
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bats tests/test_common.bats`
Expected: FAIL — `.githooks/lib/common.sh` does not exist, `setup_repo` undefined.

- [ ] **Step 3: Write `tests/helpers.bash`**

```bash
# Fixture helpers for the git-hooks bats suite.
# setup_repo builds a throwaway git repo with the hooks installed and cd's into it.

setup_repo() {
  TESTDIR="$(mktemp -d)"
  cd "$TESTDIR" || return 1
  git init -q
  git config user.email test@example.com
  git config user.name "Hook Test"
  git config commit.gpgsign false

  cp -R "$BATS_TEST_DIRNAME/../.githooks" .
  cp "$BATS_TEST_DIRNAME/../hooks.conf" .
  for f in .rules.verible_lint .vsg.yaml; do
    [ -f "$BATS_TEST_DIRNAME/../$f" ] && cp "$BATS_TEST_DIRNAME/../$f" .
  done

  chmod +x .githooks/pre-commit .githooks/commit-msg .githooks/pre-push 2>/dev/null || true
  chmod +x .githooks/lib/*.sh 2>/dev/null || true
  git config core.hooksPath .githooks
}

teardown_repo() {
  cd /
  [ -n "${TESTDIR:-}" ] && rm -rf "$TESTDIR"
}
```

- [ ] **Step 4: Write `.githooks/lib/common.sh`**

```sh
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
```

- [ ] **Step 5: Write `hooks.conf`**

```sh
# Project git-hook configuration. Sourced by .githooks/lib/common.sh.
# Commit changes here so every clone shares the same behaviour.

# --- feature toggles ---------------------------------------------------
enable_format=1        # pre-commit: check formatting of staged HDL
enable_lint=1          # pre-commit: run verible-verilog-lint on staged SV
enable_header_stamp=1  # pre-commit: bump "Date Updated :" in changed headers
commit_msg_enforce=1   # commit-msg: require Conventional Commits format

# --- commit-msg ------------------------------------------------------
commit_msg_max_subject=72

# --- Verible ---------------------------------------------------------
verible_lint_rules=.rules.verible_lint

# --- VHDL ----------------------------------------------------------
vhdl_std=08            # passed to ghdl --std=
ghdl_analyze=0         # 1 => pre-push runs `ghdl -a` instead of `ghdl -s`
vsg_config=.vsg.yaml

# --- Verilator -----------------------------------------------------
# Path (repo-relative) to a developer-maintained .f command file listing
# sources, +incdir+, +define+ and the top module. Required for the pre-push
# SystemVerilog elaboration lint; if the file is absent the step is skipped
# locally and fails in CI.
verilator_filelist=rtl.f
```

- [ ] **Step 6: Write `scripts/install-hooks.sh`**

```sh
#!/usr/bin/env sh
# One-time per clone: point git at .githooks/ and report tool availability.
set -eu

root=$(git rev-parse --show-toplevel)
cd "$root"

chmod +x .githooks/pre-commit .githooks/commit-msg .githooks/pre-push
chmod +x .githooks/lib/*.sh

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
```

- [ ] **Step 7: Write `Makefile` skeleton**

```make
SHELL := /bin/sh

# All tracked HDL sources, space separated.
HDL := $(shell git ls-files '*.sv' '*.svh' '*.v' '*.vh' '*.vhd' '*.vhdl')

.PHONY: install test

install:
	./scripts/install-hooks.sh

test:
	bats tests/
```

- [ ] **Step 8: Write `.gitattributes`**

```gitattributes
*.sv    text eol=lf
*.svh   text eol=lf
*.v     text eol=lf
*.vh    text eol=lf
*.vhd   text eol=lf
*.vhdl  text eol=lf
*.sh    text eol=lf
Makefile text eol=lf
```

- [ ] **Step 9: Write `.editorconfig`**

```ini
root = true

[*]
end_of_line = lf
insert_final_newline = true
charset = utf-8
trim_trailing_whitespace = true

[*.{sv,svh,v,vh}]
indent_style = space
indent_size = 2

[*.{vhd,vhdl}]
indent_style = space
indent_size = 4

[Makefile]
indent_style = tab
```

- [ ] **Step 10: Run the test to verify it passes**

Run: `bats tests/test_common.bats`
Expected: PASS — all 6 tests green. (`bats` must be installed: `brew install bats-core`.)

- [ ] **Step 11: Commit**

```bash
chmod +x scripts/install-hooks.sh .githooks/lib/common.sh
git add .githooks/lib/common.sh hooks.conf scripts/install-hooks.sh Makefile \
        .gitattributes .editorconfig tests/helpers.bash tests/test_common.bats
git commit -m "feat: add git-hook foundation (common.sh, config, installer)"
```

---

## Task 2: Header stamping — `header-stamp.sh` + `make stamp`

**Files:**
- Create: `.githooks/lib/header-stamp.sh`
- Modify: `Makefile` (add `stamp` target)
- Test: `tests/test_header_stamp.bats`

**Interfaces:**
- Consumes: nothing from `common.sh` (kept standalone so `make stamp` and the tests can run it in isolation).
- Produces: executable `.githooks/lib/header-stamp.sh`, usage `header-stamp.sh FILE [FILE ...]`. For each file containing a comment line matching `Date Updated :`, rewrites the date portion to today (`date +%Y-%m-%d`) in place; prints the path of every file it changed, one per line; exit 0 always (a write failure is a warning on stderr, not an error). Idempotent. Never touches `Date Created :` or `Revision History` rows.

- [ ] **Step 1: Write the failing test**

Create `tests/test_header_stamp.bats`:

```bash
load helpers

setup() { setup_repo; }
teardown() { teardown_repo; }

TODAY() { date +%Y-%m-%d; }

@test "bumps Date Updated in a SystemVerilog header" {
  printf '// Date Updated : 2000-01-01\nmodule m; endmodule\n' > m.sv
  run .githooks/lib/header-stamp.sh m.sv
  [ "$status" -eq 0 ]
  [ "$output" = "m.sv" ]
  grep -q "Date Updated : $(TODAY)" m.sv
}

@test "bumps Date Updated in a VHDL header" {
  printf -- '-- Date Updated : 2000-01-01\nentity e is end entity;\n' > e.vhd
  run .githooks/lib/header-stamp.sh e.vhd
  [ "$status" -eq 0 ]
  grep -q -- "-- Date Updated : $(TODAY)" e.vhd
}

@test "already-today prints nothing and changes nothing" {
  printf '// Date Updated : %s\nmodule m; endmodule\n' "$(TODAY)" > m.sv
  cp m.sv ref
  run .githooks/lib/header-stamp.sh m.sv
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  cmp m.sv ref
}

@test "leaves Date Created untouched" {
  printf '// Date Created : 2000-01-01\n// Date Updated : 2000-01-01\n' > m.sv
  .githooks/lib/header-stamp.sh m.sv
  grep -q "Date Created : 2000-01-01" m.sv
}

@test "leaves a Revision History row untouched" {
  printf '// YYYY-MM-DD  jdoe  Initial creation\n// Date Updated : 2000-01-01\n' > m.sv
  .githooks/lib/header-stamp.sh m.sv
  grep -q "YYYY-MM-DD  jdoe  Initial creation" m.sv
}

@test "file without the header line is left byte-for-byte identical" {
  printf 'module m; endmodule\n' > m.sv
  cp m.sv ref
  run .githooks/lib/header-stamp.sh m.sv
  [ -z "$output" ]
  cmp m.sv ref
}

@test "handles multiple files, prints only the changed ones" {
  printf '// Date Updated : 2000-01-01\n' > a.sv
  printf '// Date Updated : %s\n' "$(TODAY)" > b.sv
  printf 'no header\n' > c.sv
  run .githooks/lib/header-stamp.sh a.sv b.sv c.sv
  [ "$output" = "a.sv" ]
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bats tests/test_header_stamp.bats`
Expected: FAIL — `.githooks/lib/header-stamp.sh` does not exist.

- [ ] **Step 3: Write `.githooks/lib/header-stamp.sh`**

```sh
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
  sed -E "s|$re|\\1${today}|" "$f" > "$tmp"

  if cmp -s "$f" "$tmp"; then
    rm -f "$tmp"
  else
    cat "$tmp" > "$f" && printf '%s\n' "$f"
    rm -f "$tmp"
  fi
done

exit 0
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bats tests/test_header_stamp.bats`
Expected: PASS — all 7 tests green.

- [ ] **Step 5: Add the `stamp` target to `Makefile`**

Add after the `install` target:

```make
.PHONY: stamp
stamp:
	@.githooks/lib/header-stamp.sh $(HDL) || true
```

Update the `.PHONY` line at the top-level to include `stamp` if you keep a single consolidated `.PHONY` (either style is fine; match what Task 1 left).

- [ ] **Step 6: Verify the Make target**

Run: `printf '// Date Updated : 1999-01-01\n' > /tmp/h.sv && git -C . ls-files >/dev/null; make stamp`
Expected: any tracked HDL file with the header line is bumped to today; command exits 0. (No tracked HDL yet is also fine — target is a no-op.)

- [ ] **Step 7: Commit**

```bash
chmod +x .githooks/lib/header-stamp.sh
git add .githooks/lib/header-stamp.sh Makefile tests/test_header_stamp.bats
git commit -m "feat: add Date Updated header stamping"
```

---

## Task 3: Format + lint dispatch — `hdl-format.sh`, `hdl-lint.sh`, configs

**Files:**
- Create: `.githooks/lib/hdl-format.sh`
- Create: `.githooks/lib/hdl-lint.sh`
- Create: `.rules.verible_lint`
- Create: `.vsg.yaml`
- Modify: `Makefile` (add `format` and `lint` targets)
- Test: `tests/test_format_lint.bats`

**Interfaces:**
- Consumes from `common.sh`: `REPO_ROOT`, `have_tool`, `lang_of`, `missing_tool_notice`, `log_info`, `log_error`, config vars `verible_lint_rules`, `vsg_config`.
- Produces:
  - `.githooks/lib/hdl-format.sh FILE [FILE ...]` — for SV files runs `verible-verilog-format` in check mode (compare tool output to file); for VHDL files runs `vsg` in check mode (vsg covers style + formatting). If `HOOKS_AUTOFORMAT=1`, rewrites in place (`verible-verilog-format --inplace`, `vsg --fix`) and exits 0. Otherwise exit 1 if any file fails its check, printing the list and the fix command; exit 0 if all pass or the relevant tool is missing.
  - `.githooks/lib/hdl-lint.sh FILE [FILE ...]` — runs `verible-verilog-lint` (with `--rules_config` when `$REPO_ROOT/$verible_lint_rules` exists) on SV files only; VHDL files are ignored here (covered by `hdl-format.sh`'s vsg run). Exit 1 on any violation, exit 0 otherwise or if `verible-verilog-lint` is missing.

**Notes:** This deviates slightly from spec §2's table (which lists a separate VHDL lint). `vsg` is a single tool that does both style and formatting, so running it once from `hdl-format.sh` satisfies "VHDL is style-checked on commit" without invoking it twice per commit. `hdl-lint.sh` is therefore SV-only.

- [ ] **Step 1: Write the failing test**

Create `tests/test_format_lint.bats`. Tests that need a real tool `skip` when it is absent, so the suite is green on a bare machine and meaningful on a full one.

```bash
load helpers

setup() { setup_repo; }
teardown() { teardown_repo; }

@test "hdl-format: missing tool warns and passes" {
  # Simulate absence by putting an empty PATH dir first is unreliable; instead
  # assert the pass-through when the tool genuinely is not installed.
  if command -v verible-verilog-format >/dev/null; then skip "verible present"; fi
  printf 'module   m ;endmodule\n' > m.sv
  run .githooks/lib/hdl-format.sh m.sv
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipping"* ]]
}

@test "hdl-format: well-formatted SV passes" {
  command -v verible-verilog-format >/dev/null || skip "verible not installed"
  verible-verilog-format <<'EOF' > m.sv
module m (
    input logic clk
);
endmodule
EOF
  run .githooks/lib/hdl-format.sh m.sv
  [ "$status" -eq 0 ]
}

@test "hdl-format: badly formatted SV fails with a fix hint" {
  command -v verible-verilog-format >/dev/null || skip "verible not installed"
  printf 'module   m ;\nendmodule\n' > m.sv
  run .githooks/lib/hdl-format.sh m.sv
  [ "$status" -eq 1 ]
  [[ "$output" == *"not formatted"* ]]
  [[ "$output" == *"make format"* ]]
}

@test "hdl-format: HOOKS_AUTOFORMAT rewrites and passes" {
  command -v verible-verilog-format >/dev/null || skip "verible not installed"
  printf 'module   m ;\nendmodule\n' > m.sv
  run env HOOKS_AUTOFORMAT=1 .githooks/lib/hdl-format.sh m.sv
  [ "$status" -eq 0 ]
  run .githooks/lib/hdl-format.sh m.sv
  [ "$status" -eq 0 ]
}

@test "hdl-lint: clean SV passes" {
  command -v verible-verilog-lint >/dev/null || skip "verible not installed"
  printf 'module m;\nendmodule\n' > m.sv
  run .githooks/lib/hdl-lint.sh m.sv
  [ "$status" -eq 0 ]
}

@test "hdl-lint: a lint violation fails the check" {
  command -v verible-verilog-lint >/dev/null || skip "verible not installed"
  # Trailing whitespace / tab rules: a hard tab in source trips +no-tabs.
  printf 'module m;\n\tendmodule\n' > m.sv
  run .githooks/lib/hdl-lint.sh m.sv
  [ "$status" -eq 1 ]
}

@test "hdl-lint: missing tool warns and passes" {
  if command -v verible-verilog-lint >/dev/null; then skip "verible present"; fi
  printf 'module m; endmodule\n' > m.sv
  run .githooks/lib/hdl-lint.sh m.sv
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipping"* ]]
}

@test "hdl-lint: ignores VHDL files" {
  printf 'entity e is end entity;\n' > e.vhd
  run .githooks/lib/hdl-lint.sh e.vhd
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bats tests/test_format_lint.bats`
Expected: FAIL — dispatch scripts do not exist.

- [ ] **Step 3: Write `.rules.verible_lint`**

```
# Verible SystemVerilog lint rules. One directive per line:
#   +rule           enable
#   -rule           disable
#   rule=key:value  configure
# Full list: https://chipsalliance.github.io/verible/lint.html
# This is a conservative starting set; tune it as the project's style settles.
-line-length
+no-tabs
+no-trailing-spaces
+parameter-name-style
+module-filename
+explicit-parameter-storage-type
+packed-dimensions-range-ordering
+generate-label-prefix
```

- [ ] **Step 4: Write `.vsg.yaml`**

```yaml
# VHDL Style Guide configuration (https://vsg.readthedocs.io).
# Only consulted when the repo contains .vhd/.vhdl files.
rule:
  global:
    indentSize: 4
  # Example project override: keep port maps aligned but do not force a
  # specific case for keywords beyond the default lower-case.
  keyword_0500:
    disable: false
```

- [ ] **Step 5: Write `.githooks/lib/hdl-format.sh`**

```sh
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
```

- [ ] **Step 6: Write `.githooks/lib/hdl-lint.sh`**

```sh
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
```

- [ ] **Step 7: Run the test to verify it passes**

Run: `bats tests/test_format_lint.bats`
Expected: PASS — tests run and pass; tool-dependent tests either run (if Verible installed) or `skip`.

- [ ] **Step 8: Add `format` and `lint` targets to `Makefile`**

```make
.PHONY: format lint
format:
	@HOOKS_AUTOFORMAT=1 .githooks/lib/hdl-format.sh $(HDL)

lint:
	@.githooks/lib/hdl-format.sh $(HDL)
	@.githooks/lib/hdl-lint.sh $(HDL)
```

- [ ] **Step 9: Commit**

```bash
chmod +x .githooks/lib/hdl-format.sh .githooks/lib/hdl-lint.sh
git add .githooks/lib/hdl-format.sh .githooks/lib/hdl-lint.sh \
        .rules.verible_lint .vsg.yaml Makefile tests/test_format_lint.bats
git commit -m "feat: add HDL format and lint dispatch scripts"
```

---

## Task 4: `pre-commit` hook

**Files:**
- Create: `.githooks/pre-commit`
- Test: `tests/test_pre_commit.bats`

**Interfaces:**
- Consumes from `common.sh`: `staged_hdl_files`, `skip_requested`, `log_info`, config vars `enable_format` `enable_lint` `enable_header_stamp`. Calls `.githooks/lib/hdl-format.sh`, `.githooks/lib/hdl-lint.sh`, `.githooks/lib/header-stamp.sh` (all from Tasks 2–3) with the staged file list as arguments.
- Produces: an executable `.githooks/pre-commit` that, on `git commit`, runs format → lint → stamp against staged HDL, aborts the commit (non-zero exit) if format or lint fails, and `git add`s any file whose header it stamps so the stamp is part of the commit. No staged HDL ⇒ exit 0 immediately. `HOOKS_SKIP=all` ⇒ exit 0 immediately.

- [ ] **Step 1: Write the failing test**

Create `tests/test_pre_commit.bats`:

```bash
load helpers

setup() { setup_repo; }
teardown() { teardown_repo; }

@test "commit with no HDL changes is allowed" {
  echo hello > README.md
  git add README.md
  run git commit -m "docs: add readme"
  [ "$status" -eq 0 ]
}

@test "well-formed SV commit stamps the header and is committed" {
  command -v verible-verilog-format >/dev/null || skip "verible not installed"
  verible-verilog-format > m.sv <<'EOF'
// Date Updated : 2000-01-01
module m (
    input logic clk
);
endmodule
EOF
  # the format pass strips the comment? No: verible preserves comments.
  git add m.sv
  run git commit -m "feat: add module m"
  [ "$status" -eq 0 ]
  git show HEAD:m.sv | grep -q "Date Updated : $(date +%Y-%m-%d)"
}

@test "badly formatted SV aborts the commit" {
  command -v verible-verilog-format >/dev/null || skip "verible not installed"
  printf '// Date Updated : 2000-01-01\nmodule   m ;\nendmodule\n' > m.sv
  git add m.sv
  run git commit -m "feat: add module m"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not formatted"* ]]
  # nothing committed
  run git rev-parse HEAD
  [ "$status" -ne 0 ]
}

@test "stamp runs even when Verible is absent" {
  if command -v verible-verilog-format >/dev/null; then skip "verible present"; fi
  printf '// Date Updated : 2000-01-01\nmodule m; endmodule\n' > m.sv
  git add m.sv
  run git commit -m "feat: add m"
  [ "$status" -eq 0 ]
  git show HEAD:m.sv | grep -q "Date Updated : $(date +%Y-%m-%d)"
}

@test "HOOKS_SKIP=stamp leaves the header date alone" {
  printf '// Date Updated : 2000-01-01\nmodule m; endmodule\n' > m.sv
  git add m.sv
  run env HOOKS_SKIP=stamp,format,lint git commit -m "feat: add m"
  [ "$status" -eq 0 ]
  git show HEAD:m.sv | grep -q "Date Updated : 2000-01-01"
}

@test "HOOKS_SKIP=all bypasses everything" {
  printf 'module   m ;endmodule\n' > m.sv
  git add m.sv
  run env HOOKS_SKIP=all git commit -m "feat: messy but skipped"
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bats tests/test_pre_commit.bats`
Expected: FAIL — `.githooks/pre-commit` does not exist (commits succeed without stamping / without rejecting bad format).

- [ ] **Step 3: Write `.githooks/pre-commit`**

```sh
#!/usr/bin/env sh
# Format-check, lint, and header-stamp staged HDL before the commit is created.
set -u
HOOK_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$HOOK_DIR/lib/common.sh"

skip_requested all && exit 0

files=$(staged_hdl_files)
[ -n "$files" ] || exit 0

# hdl-* scripts take the list as positional args; project convention forbids
# spaces/newlines in HDL paths (see plan Global Constraints).
# shellcheck disable=SC2086
set -- $files

if [ "${enable_format:-1}" = "1" ] && ! skip_requested format; then
  "$HOOK_DIR/lib/hdl-format.sh" "$@" || exit $?
fi

if [ "${enable_lint:-1}" = "1" ] && ! skip_requested lint; then
  "$HOOK_DIR/lib/hdl-lint.sh" "$@" || exit $?
fi

if [ "${enable_header_stamp:-1}" = "1" ] && ! skip_requested stamp; then
  changed=$("$HOOK_DIR/lib/header-stamp.sh" "$@")
  if [ -n "$changed" ]; then
    printf '%s\n' "$changed" | while IFS= read -r f; do
      [ -n "$f" ] && git add -- "$f"
    done
    log_info "stamped Date Updated: $(printf '%s' "$changed" | tr '\n' ' ')"
  fi
fi

exit 0
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bats tests/test_pre_commit.bats`
Expected: PASS — all tests green (tool-dependent ones run or `skip`).

- [ ] **Step 5: Run the whole suite so far**

Run: `bats tests/`
Expected: PASS — `test_common`, `test_header_stamp`, `test_format_lint`, `test_pre_commit` all green.

- [ ] **Step 6: Commit**

```bash
chmod +x .githooks/pre-commit
git add .githooks/pre-commit tests/test_pre_commit.bats
git commit -m "feat: add pre-commit hook (format, lint, header stamp)"
```

---

## Task 5: `commit-msg` hook — Conventional Commits

**Files:**
- Create: `.githooks/commit-msg`
- Test: `tests/test_commit_msg.bats`

**Interfaces:**
- Consumes from `common.sh`: `log_error`, config vars `commit_msg_enforce`, `commit_msg_max_subject`.
- Produces: an executable `.githooks/commit-msg` taking the message-file path as `$1`. Exit 0 (allow) when `commit_msg_enforce != 1`, when the first real line starts with `Merge `/`Revert `/`fixup! `/`squash! `, or when that line is empty. Otherwise require `^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\(<scope>\))?(!)?: <subject>` and `len(subject) <= commit_msg_max_subject`; exit 1 with a diagnostic otherwise.

- [ ] **Step 1: Write the failing test**

Create `tests/test_commit_msg.bats`:

```bash
load helpers

setup() { setup_repo; }
teardown() { teardown_repo; }

run_hook() { printf '%s\n' "$1" > "$TESTDIR/MSG"; run .githooks/commit-msg "$TESTDIR/MSG"; }

@test "valid: feat with scope" {
  run_hook "feat(uart): add parity bit generation"
  [ "$status" -eq 0 ]
}

@test "valid: fix without scope" {
  run_hook "fix: correct reset polarity in fifo"
  [ "$status" -eq 0 ]
}

@test "valid: breaking-change bang" {
  run_hook "refactor(axi)!: split read and write channels"
  [ "$status" -eq 0 ]
}

@test "invalid: no type prefix" {
  run_hook "added parity bit"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Conventional Commits"* ]]
}

@test "invalid: unknown type" {
  run_hook "wip: poking at things"
  [ "$status" -eq 1 ]
}

@test "invalid: subject over the length limit" {
  long=$(printf 'x%.0s' $(seq 1 80))
  run_hook "feat: $long"
  [ "$status" -eq 1 ]
  [[ "$output" == *"limit"* ]]
}

@test "exempt: merge commit" {
  run_hook "Merge branch 'feature/uart' into main"
  [ "$status" -eq 0 ]
}

@test "exempt: revert commit" {
  run_hook "Revert \"feat(uart): add parity bit\""
  [ "$status" -eq 0 ]
}

@test "disabled: commit_msg_enforce=0 allows anything" {
  echo 'commit_msg_enforce=0' >> hooks.conf
  run_hook "total nonsense here"
  [ "$status" -eq 0 ]
}

@test "end to end: bad message blocks git commit, good one passes" {
  printf 'module m; endmodule\n' > m.sv
  git add m.sv
  run env HOOKS_SKIP=format,lint,stamp git commit -m "nope not conventional"
  [ "$status" -ne 0 ]
  run env HOOKS_SKIP=format,lint,stamp git commit -m "feat: add module m"
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bats tests/test_commit_msg.bats`
Expected: FAIL — `.githooks/commit-msg` does not exist.

- [ ] **Step 3: Write `.githooks/commit-msg`**

```sh
#!/usr/bin/env sh
# Validate the commit message against Conventional Commits.
set -u
HOOK_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$HOOK_DIR/lib/common.sh"

[ "${commit_msg_enforce:-1}" = "1" ] || exit 0

msg_file=$1
subject=$(grep -vE '^[[:space:]]*#' "$msg_file" | grep -vE '^[[:space:]]*$' | head -n1)

case $subject in
  "Merge "*|"Revert "*|"fixup! "*|"squash! "*|"") exit 0 ;;
esac

types='feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert'

if ! printf '%s\n' "$subject" | grep -Eq "^(${types})(\([a-z0-9._/-]+\))?(!)?: .+"; then
  log_error "commit message is not Conventional Commits"
  log_error "  got:      $subject"
  log_error "  want:     <type>(<scope>)?: <subject>   e.g. feat(uart): add parity bit"
  log_error "  types:    ${types}"
  exit 1
fi

body=${subject#*: }
len=$(printf '%s' "$body" | wc -c | tr -d ' ')
limit=${commit_msg_max_subject:-72}
if [ "$len" -gt "$limit" ]; then
  log_error "commit subject is ${len} characters; limit is ${limit}"
  exit 1
fi

exit 0
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bats tests/test_commit_msg.bats`
Expected: PASS — all 10 tests green.

- [ ] **Step 5: Commit**

```bash
chmod +x .githooks/commit-msg
git add .githooks/commit-msg tests/test_commit_msg.bats
git commit -m "feat: add commit-msg hook enforcing Conventional Commits"
```

---

## Task 6: `pre-push` hook — elaboration lint

**Files:**
- Create: `.githooks/lib/hdl-elaborate.sh`
- Create: `.githooks/pre-push`
- Modify: `Makefile` (add `elaborate` target)
- Test: `tests/test_pre_push.bats`

**Interfaces:**
- Consumes from `common.sh`: `REPO_ROOT`, `have_tool`, `lang_of`, `tracked_hdl_files`, `skip_requested`, `log_warn`, `log_error`, `missing_tool_notice`, config vars `verilator_filelist`, `vhdl_std`, `ghdl_analyze`.
- Produces:
  - `.githooks/lib/hdl-elaborate.sh MODE` where `MODE` is `local` or `ci`. Reads a newline-separated HDL file list on stdin. For SV: if `verilator` present and `$REPO_ROOT/$verilator_filelist` exists, run `verilator --lint-only -Wall -f <filelist>` from `$REPO_ROOT`; missing tool or missing filelist ⇒ `log_warn` + pass in `local`, `log_error` + fail in `ci`. For VHDL: if `ghdl` present, run `ghdl -s --std=$vhdl_std <files>` (or `ghdl -a --workdir=<tmp> --std=$vhdl_std <files>` when `ghdl_analyze=1`) from `$REPO_ROOT`; missing tool ⇒ warn+pass local / error+fail ci. Exit non-zero if any executed check fails.
  - `.githooks/pre-push` — exits 0 on `HOOKS_SKIP` containing `all` or `push`, or when there is no tracked HDL; otherwise pipes `tracked_hdl_files` into `hdl-elaborate.sh local`. Git passes push refs on stdin to the hook, so `pre-push` must read/ignore them before delegating.

- [ ] **Step 1: Write the failing test**

Create `tests/test_pre_push.bats`:

```bash
load helpers

setup() { setup_repo; }
teardown() { teardown_repo; }

@test "no tracked HDL: elaborate passes trivially" {
  run sh -c ': | .githooks/lib/hdl-elaborate.sh local'
  [ "$status" -eq 0 ]
}

@test "SV, verilator present, no filelist: warn + pass in local" {
  command -v verilator >/dev/null || skip "verilator not installed"
  printf 'module top; endmodule\n' > top.sv
  run sh -c 'printf "top.sv\n" | .githooks/lib/hdl-elaborate.sh local'
  [ "$status" -eq 0 ]
  [[ "$output" == *"unconfigured"* || "$output" == *"not found"* ]]
}

@test "SV, verilator present, no filelist: hard fail in ci" {
  command -v verilator >/dev/null || skip "verilator not installed"
  printf 'module top; endmodule\n' > top.sv
  run sh -c 'printf "top.sv\n" | .githooks/lib/hdl-elaborate.sh ci'
  [ "$status" -ne 0 ]
}

@test "SV clean design with a filelist passes" {
  command -v verilator >/dev/null || skip "verilator not installed"
  printf 'module top (input logic a, output logic b);\n  assign b = a;\nendmodule\n' > top.sv
  printf 'top.sv\n' > rtl.f
  run sh -c 'printf "top.sv\n" | .githooks/lib/hdl-elaborate.sh local'
  [ "$status" -eq 0 ]
}

@test "SV width mismatch is caught" {
  command -v verilator >/dev/null || skip "verilator not installed"
  cat > top.sv <<'EOF'
module top (output logic [3:0] q);
  logic [7:0] wide;
  assign wide = 8'hAA;
  assign q = wide;
endmodule
EOF
  printf 'top.sv\n' > rtl.f
  run sh -c 'printf "top.sv\n" | .githooks/lib/hdl-elaborate.sh local'
  [ "$status" -ne 0 ]
}

@test "VHDL syntax error is caught by ghdl" {
  command -v ghdl >/dev/null || skip "ghdl not installed"
  printf 'entity e is end entity\n' > e.vhd   # missing terminating ;
  run sh -c 'printf "e.vhd\n" | .githooks/lib/hdl-elaborate.sh local'
  [ "$status" -ne 0 ]
}

@test "pre-push consumes stdin refs and passes when no HDL tracked" {
  echo hi > README.md; git add README.md
  git -c core.hooksPath= commit -q -m "docs: readme"
  run sh -c 'printf "refs/heads/main abc refs/heads/main def\n" | .githooks/pre-push origin git@example:repo.git'
  [ "$status" -eq 0 ]
}

@test "pre-push skips on HOOKS_SKIP=push" {
  command -v verilator >/dev/null || skip "verilator not installed"
  printf 'module top; endmodule\n' > top.sv
  git -c core.hooksPath= add top.sv
  git -c core.hooksPath= commit -q -m "feat: top"
  run sh -c 'printf "\n" | env HOOKS_SKIP=push .githooks/pre-push origin url'
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bats tests/test_pre_push.bats`
Expected: FAIL — `.githooks/lib/hdl-elaborate.sh` and `.githooks/pre-push` do not exist.

- [ ] **Step 3: Write `.githooks/lib/hdl-elaborate.sh`**

```sh
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
  case $(lang_of "$f") in
    sv)   have_sv=1 ;;
    vhdl) vhd="$vhd $f" ;;
  esac
done

fail=0
_miss() {  # tool, step  -> warn+ok in local, error+fail in ci
  if [ "$mode" = ci ]; then log_error "$1 required in CI: $2"; fail=1
  else missing_tool_notice "$1" "$2"; fi
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
      if [ "$mode" = ci ]; then log_error "$msg"; fail=1; else log_warn "$msg"; fi
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
```

- [ ] **Step 4: Write `.githooks/pre-push`**

```sh
#!/usr/bin/env sh
# Whole-design elaboration lint before a push. Git streams the ref updates
# being pushed on stdin; we do not need them, but must not leave them unread
# in a way that surprises git, so drain stdin first.
set -u
HOOK_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$HOOK_DIR/lib/common.sh"

cat >/dev/null 2>&1 || true   # drain the ref list git passes on stdin

{ skip_requested all || skip_requested push; } && exit 0

files=$(tracked_hdl_files)
[ -n "$files" ] || exit 0

printf '%s\n' "$files" | "$HOOK_DIR/lib/hdl-elaborate.sh" local
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `bats tests/test_pre_push.bats`
Expected: PASS — tool-dependent tests run or `skip`; stdin-drain and skip tests pass unconditionally.

- [ ] **Step 6: Add the `elaborate` target to `Makefile`**

```make
.PHONY: elaborate
elaborate:
	@printf '%s\n' $(HDL) | .githooks/lib/hdl-elaborate.sh ci
```

- [ ] **Step 7: Commit**

```bash
chmod +x .githooks/lib/hdl-elaborate.sh .githooks/pre-push
git add .githooks/lib/hdl-elaborate.sh .githooks/pre-push Makefile tests/test_pre_push.bats
git commit -m "feat: add pre-push elaboration lint (verilator/ghdl)"
```

---

## Task 7: CI parity + documentation

**Files:**
- Create: `.github/workflows/hdl.yml`
- Create: `docs/hooks.md`
- Modify: `README.md` (add a "Git hooks" section; create the file if absent)
- Test: none new — CI *is* the test surface here; verify `make lint`/`make elaborate`/`make test` run locally.

**Interfaces:**
- Consumes: the `install`, `lint`, `elaborate`, `test` `make` targets from Tasks 1–6.
- Produces: a GitHub Actions workflow that installs the toolchain and runs the same `make` targets the hooks use, so CI and local checks cannot diverge; developer docs.

- [ ] **Step 1: Write `.github/workflows/hdl.yml`**

```yaml
name: hdl
on:
  push:
    branches: ["**"]
  pull_request:

jobs:
  checks:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install Verilator, GHDL, bats
        run: |
          sudo apt-get update
          sudo apt-get install -y verilator ghdl bats

      - name: Install Verible
        run: |
          set -eu
          ver="v0.0-3946-g851d3ff4"   # bump periodically; see github.com/chipsalliance/verible/releases
          url="https://github.com/chipsalliance/verible/releases/download/${ver}/verible-${ver}-linux-static-x86_64.tar.gz"
          curl -fsSL "$url" | sudo tar -xz --strip-components=1 -C /usr/local
          verible-verilog-lint --version

      - name: Install vsg
        run: pipx install vsg || pip install --user vsg

      - name: Lint + format check (same as pre-commit)
        run: make lint

      - name: Elaboration lint (same as pre-push, CI mode)
        run: make elaborate

      - name: Hook test suite
        run: make test
```

- [ ] **Step 2: Write `docs/hooks.md`**

```markdown
# Git hooks

This repo ships Git hooks under [`.githooks/`](../.githooks) that help keep the
HDL clean and the file headers current.

## Install (once per clone)

```sh
make install
```

This runs `git config core.hooksPath .githooks` and prints which optional
tools are present. Missing tools are skipped locally; CI enforces all of them.

## What runs when

| Hook | Action |
|------|--------|
| `pre-commit` | On staged `.sv/.svh/.v/.vh` and `.vhd/.vhdl`: format check (`verible-verilog-format`; `vsg` for VHDL), lint (`verible-verilog-lint`), and bump the `Date Updated :` header line (re-staged automatically). |
| `commit-msg` | Require [Conventional Commits](https://www.conventionalcommits.org/): `type(scope)?: subject`, subject ≤ 72 chars. Merge/revert/fixup/squash exempt. |
| `pre-push` | Whole-design elaboration lint: `verilator --lint-only` (needs `rtl.f`) and `ghdl -s`. |

## Tools

| Tool | Used by | Install |
|------|---------|---------|
| `verible-verilog-format`, `verible-verilog-lint` | pre-commit | https://github.com/chipsalliance/verible/releases |
| `verilator` | pre-push | `brew install verilator` / `apt install verilator` |
| `vsg` | pre-commit (VHDL) | `pipx install vsg` |
| `ghdl` | pre-push (VHDL) | `brew install ghdl` / `apt install ghdl` |
| `bats` | `make test` | `brew install bats-core` |

## Configuration

Edit [`hooks.conf`](../hooks.conf) (committed, shared by every clone):

- `enable_format` / `enable_lint` / `enable_header_stamp` / `commit_msg_enforce` — feature toggles.
- `commit_msg_max_subject` — subject length limit.
- `verilator_filelist` — path to the `.f` command file for the pre-push SV lint. Maintain this by hand as the design grows; without it the SV elaboration lint is skipped locally and fails in CI.
- `vhdl_std`, `ghdl_analyze`, `verible_lint_rules`, `vsg_config`.

## Bypassing

- `HOOKS_SKIP=lint,stamp git commit …` — skip named steps (`format`, `lint`, `stamp`, `push`, `all`).
- `HOOKS_AUTOFORMAT=1 git commit …` — reformat staged files in place instead of failing.
- `git commit --no-verify` / `git push --no-verify` — skip the hook entirely.

## Not automated on purpose

The `Revision History` table in the file templates is a **manual** edit. Add a
row when a change is worth a line; the authoritative per-file history is
`git log -p --follow <file>`. Commit-message text is never written into files.
```

- [ ] **Step 3: Add a "Git hooks" section to `README.md`**

If `README.md` does not exist, create it with a project title line, then add:

```markdown
## Git hooks

After cloning, run `make install` once to enable the project Git hooks
(formatting, linting, header date-stamping, Conventional Commits, pre-push
elaboration lint). See [docs/hooks.md](docs/hooks.md) for details, required
tools, and how to bypass a hook.
```

- [ ] **Step 4: Verify the Make targets run end to end**

Run:
```sh
make install
make lint
make elaborate
make test
```
Expected: `make install` sets `core.hooksPath` and lists tools. `make lint` / `make elaborate` pass on the current (template-only) tree or clearly report a missing tool. `make test` runs the full bats suite green.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/hdl.yml docs/hooks.md README.md
git commit -m "ci: run hook checks in GitHub Actions; document the hooks"
```

---

## Self-Review

**1. Spec coverage:**

| Spec section | Task |
|---|---|
| §1 purpose, non-goals (no amend, no msg-in-file, manual Revision History, no auto-install) | Global Constraints; enforced by design across Tasks 2, 4, 5 |
| §2 tooling model, per-extension dispatch, Verible vs Verilator split | Task 1 (`lang_of`), Task 3 (format/lint), Task 6 (elaborate) |
| §3 delivery via `.githooks/` + `core.hooksPath` | Task 1 (`install-hooks.sh`, `make install`) |
| §4 repository layout | All tasks; file map at top of plan |
| §5.1 `common.sh` helpers | Task 1 (each helper has a `test_common.bats` case) |
| §5.2 `pre-commit` (format check, autoformat flag, lint, stamp+restage, missing-tool skip) | Task 4, using Task 3 + Task 2 scripts |
| §5.3 `commit-msg` (toggle, exemptions, regex, length) | Task 5 |
| §5.4 `pre-push` (SV filelist required, VHDL ghdl, missing-tool warn/pass, CI hard-fail) | Task 6 |
| §5.5 `header-stamp.sh` standalone + idempotent | Task 2 |
| §5.6 `install-hooks.sh` (chmod, config, tool report, idempotent) | Task 1 |
| §6 config keys + env overrides (`HOOKS_SKIP`, `HOOKS_AUTOFORMAT`, `--no-verify`) | Task 1 (`hooks.conf`, `skip_requested`), Task 3 (`HOOKS_AUTOFORMAT`), Task 4 (`HOOKS_SKIP=all`) |
| §7 CI parity via shared `make` targets | Task 7 |
| §8 bats suite, per-hook cases, `make test` | Tasks 1–6 each add a `.bats` file; Task 1 adds `make test` |
| §9 documentation deliverable | Task 7 (`docs/hooks.md`, README section) |
| §10 open items (git-cliff, formal lint) | Explicitly deferred; not in plan |

No gaps.

**2. Placeholder scan:** No `TBD`/`TODO`/"handle edge cases"/"similar to Task N". Every code step contains the full file or the exact fragment with insertion point. The Verible release tag in Task 7 is a real pinned value with a documented "bump periodically" note, not a placeholder.

**3. Type / name consistency:** Helper names (`have_tool`, `lang_of`, `staged_hdl_files`, `tracked_hdl_files`, `skip_requested`, `log_info/warn/error`, `missing_tool_notice`) and config variable names (`enable_format`, `enable_lint`, `enable_header_stamp`, `commit_msg_enforce`, `commit_msg_max_subject`, `verible_lint_rules`, `vhdl_std`, `ghdl_analyze`, `verilator_filelist`, `vsg_config`) are used identically in Tasks 1, 3, 4, 5, 6. Script paths (`.githooks/lib/hdl-format.sh`, `hdl-lint.sh`, `hdl-elaborate.sh`, `header-stamp.sh`) match between definition and call sites. `hdl-elaborate.sh` mode argument (`local`/`ci`) consistent between Task 6 definition, `pre-push` caller, and the `make elaborate` target. `HOOKS_SKIP` step tokens (`format`, `lint`, `stamp`, `push`, `all`) consistent across `common.sh`, `pre-commit`, `pre-push`, and docs.
