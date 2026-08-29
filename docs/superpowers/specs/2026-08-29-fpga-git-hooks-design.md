# FPGA Git Hooks — Design

Date: 2026-08-29
Status: Approved for planning
Repo: https://github.com/FPGA-James/hooks.git

## 1. Purpose

Provide a small, dependency-light set of Git hooks that help enforce HDL code
quality and keep file-header metadata current for an FPGA project that may be
written in SystemVerilog, VHDL, or a mix of both.

The hooks must:

- Format and lint staged HDL on every commit, fast and per-file.
- Keep the `Date Updated :` line in file headers current automatically.
- Optionally enforce a Conventional Commits message format.
- Run a whole-design elaboration lint before push, to catch real RTL bugs.
- Degrade gracefully when a tool is not installed, so a fresh clone can still
  commit; CI is the hard backstop.

### Non-goals

- No automatic injection of commit-message text into an in-file
  `Revision History` table. Git is the authoritative per-file history
  (`git log -p --follow <file>`). The template's `Revision History` table
  remains a manual, reviewed edit made when a line is genuinely warranted.
- No `CHANGELOG.md` generation (`git-cliff` etc.) in this iteration.
- No `post-commit` amend behaviour. Rewriting the just-made commit is fragile
  once anything is pushed or rebased and is explicitly rejected.
- Hooks are not auto-installed on clone. Git never runs a hook installer
  automatically; a one-time `make install` per clone is required and documented.

## 2. Tooling model

| Language | Extensions | Format (pre-commit) | Style/lint (pre-commit) | Elaborate (pre-push / CI) |
|----------|------------|---------------------|-------------------------|---------------------------|
| SystemVerilog / Verilog | `.sv` `.svh` `.v` `.vh` | `verible-verilog-format` | `verible-verilog-lint` | `verilator --lint-only -Wall` |
| VHDL | `.vhd` `.vhdl` | `vsg --fix` (check mode in hook) | `vsg` | `ghdl -s` (syntax) / `ghdl -a` (analysis) |

- Dispatch is by file extension, evaluated per file. An all-SV or all-VHDL repo
  simply never exercises the other path.
- Rationale for the split (Verible vs Verilator): Verible parses a single file
  with no elaboration — fast, no include-path or submodule context needed, ideal
  for `pre-commit`. Verilator elaborates the design and needs context (include
  dirs, packages, submodules, defines); it belongs in `pre-push`/CI where that
  context exists. They are complementary, not alternatives.

## 3. Delivery mechanism

Chosen approach: **versioned `.githooks/` directory + `core.hooksPath`.**

- Hooks are POSIX `sh` scripts committed under `.githooks/`.
- `scripts/install-hooks.sh` runs `git config core.hooksPath .githooks` and
  verifies the scripts are executable. Wrapped as `make install`.
- No external language runtime. Every hook is readable and reviewable in a diff.
- Accepted tradeoffs: `core.hooksPath` replaces `.git/hooks/` wholesale (fine
  for a fresh project); each clone runs `make install` once.

Rejected: the `pre-commit` framework (adds a Python/pip dependency to a
non-Python toolchain; Verible/Verilator/vsg have no maintained upstream hooks
and would be `repo: local` anyway). Rejected: symlinks into `.git/hooks/`
(more fragile install logic, no advantage here).

## 4. Repository layout

```
.githooks/
  pre-commit
  commit-msg
  pre-push
  lib/
    common.sh          # config loading, tool detection, file filtering, logging, skip logic
    hdl-format.sh       # verible-verilog-format / vsg dispatch (check + optional fix)
    hdl-lint.sh         # verible-verilog-lint / vsg dispatch
    hdl-elaborate.sh    # verilator --lint-only / ghdl dispatch
    header-stamp.sh     # "Date Updated :" line bump
scripts/
  install-hooks.sh
hooks.conf              # committed defaults, user-overridable
Makefile                # install, lint, format, stamp, test targets
.rules.verible_lint     # Verible lint rule configuration
.vsg.yaml               # vsg configuration (only needed if VHDL is used)
.gitattributes          # .sv/.svh/.v/.vh/.vhd/.vhdl -> text, eol=lf
.editorconfig           # indentation matching Verible defaults
.github/workflows/hdl.yml  # CI running the same checks
tests/
  test_pre_commit.bats
  test_commit_msg.bats
  test_pre_push.bats
  test_header_stamp.bats
  helpers.bash          # temp-repo fixture setup
```

## 5. Component behaviour

### 5.1 `lib/common.sh` (shared library)

Responsibilities:

- Locate the repo root (`git rev-parse --show-toplevel`).
- Load `hooks.conf` (simple `key=value`, sourced). Missing file → built-in
  defaults.
- `have_tool <name>` — returns success if the binary is on `PATH`.
- `staged_hdl_files` — `git diff --cached --name-only --diff-filter=ACM`
  filtered to known extensions and to files that still exist on disk.
- `tracked_hdl_files` — `git ls-files` filtered by extension (used by `pre-push`).
- `lang_of <file>` — echoes `sv` or `vhdl` from the extension.
- `skip_requested <step>` — true if `step` appears in the `HOOKS_SKIP`
  comma-separated env var.
- `log_info` / `log_warn` / `log_error` — consistent `hooks:` prefixed output to
  stderr; colour only when stderr is a TTY.
- `missing_tool_notice <tool> <step>` — one standard `log_warn` line, always
  returns "skip this step, do not fail".

Interface contract: hooks call functions from `common.sh` only; no hook
duplicates file-filtering or tool-detection logic.

### 5.2 `pre-commit`

Order of operations:

1. Source `common.sh`. If `HOOKS_SKIP` contains `all`, exit 0.
2. `files=$(staged_hdl_files)`. If empty, exit 0.
3. **Format check** (`enable_format=1`, step name `format`):
   - For each file, run the language's formatter in check/diff mode
     (`verible-verilog-format` to stdout compared against the file; `vsg` in
     check mode).
   - Any file not matching formatter output → collect it.
   - If `HOOKS_AUTOFORMAT=1`: format in place, `git add` the file, log which
     files were reformatted, continue.
   - Else if any collected: print the file list and the exact fix command
     (`make format` / `verible-verilog-format --inplace <files>`), exit 1.
   - Formatter tool missing → `missing_tool_notice`, skip step.
4. **Lint** (`enable_lint=1`, step name `lint`):
   - Run `verible-verilog-lint --rules_config <verible_lint_rules>` / `vsg`
     against the staged files.
   - Any diagnostic → print tool output verbatim, exit 1.
   - Lint tool missing → `missing_tool_notice`, skip step.
5. **Header stamp** (`enable_header_stamp=1`, step name `stamp`):
   - For each staged HDL file containing a line matching
     `^([-/ ]*Date Updated\s*:\s*).*$`, replace the trailing date with
     `date +%Y-%m-%d`. No-op if the value is already today.
   - Comment-leader agnostic: matches whether the line begins with `--` (VHDL)
     or `//` (SV).
   - Only that single line is rewritten. `git add` the file if changed.
   - This step never fails the commit; a write error is a `log_warn`.
6. Exit 0.

Notes:

- All steps run on the staged content of files as they exist in the working
  tree. The project convention is not to stage partial-file hunks of HDL; this
  is documented, not enforced.
- `git commit --no-verify` bypasses the whole hook (standard Git behaviour).

### 5.3 `commit-msg`

- Active only when `commit_msg_enforce=1` in `hooks.conf`.
- Reads the message file passed as `$1`.
- Exempt (exit 0 immediately) when the subject matches any of:
  `^Merge `, `^Revert `, `^fixup! `, `^squash! `, or the message is empty
  (Git aborts the commit itself in that case).
- Validation rules:
  - First non-comment line matches
    `^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([a-z0-9._-]+\))?(!)?: .+`
  - Subject (text after `: `) length ≤ `commit_msg_max_subject` (default 72).
  - Blank line between subject and body if a body is present.
- On failure: print the offending line, the rule violated, and a one-line
  example of a valid message; exit 1.
- Allowed types and max length are config keys so the list can be adjusted
  without editing the script.

### 5.4 `pre-push`

- Source `common.sh`. If `HOOKS_SKIP` contains `all` or `push`, exit 0.
- `files=$(tracked_hdl_files)`. If empty, exit 0.
- **SystemVerilog**: if any `.sv/.v` tracked and `have_tool verilator`:
  - Requires the `hooks.conf` key `verilator_filelist` to point at a
    developer-maintained `.f` file (command-file with sources, `+incdir+`,
    `+define+`, top module). Invocation:
    `verilator --lint-only -Wall -f <verilator_filelist>`.
  - If `verilator_filelist` is unset or the file does not exist → `log_warn`
    that the SV elaboration lint is unconfigured, and pass (do not block the
    push). CI treats the same condition as a hard failure.
  - Non-zero `verilator` exit → print output, exit 1.
- **VHDL**: if any `.vhd` tracked and `have_tool ghdl`:
  - `ghdl -s --std=<vhdl_std> <files>` (syntax). `ghdl_analyze=1` upgrades this
    to `ghdl -a` into a scratch workdir.
  - Non-zero exit → print output, exit 1.
- Tool missing → `missing_tool_notice`, pass. CI is expected to have the tool
  and run the same command (see §7).
- `git push --no-verify` bypasses.

### 5.5 `header-stamp.sh`

Standalone so `make stamp` can run it over an arbitrary file set and so
`test_header_stamp.bats` can test it in isolation.

- Input: list of file paths.
- For each: locate the `Date Updated :` line (regex above), substitute today's
  date, write back only if changed. Echo changed paths on stdout.
- Never touches `Date Created :` or `Revision History` rows.
- Idempotent.

### 5.6 `scripts/install-hooks.sh`

- `git rev-parse` sanity check (must be inside this repo).
- `chmod +x .githooks/pre-commit .githooks/commit-msg .githooks/pre-push`.
- `git config core.hooksPath .githooks`.
- Print which tools are found / missing (`verible-verilog-format`,
  `verible-verilog-lint`, `verilator`, `vsg`, `ghdl`, `bats`) so the developer
  knows what will be skipped.
- Idempotent; safe to re-run.

## 6. Configuration

`hooks.conf` (committed, developers may edit locally; changes tracked):

```
# Feature toggles
enable_format=1
enable_lint=1
enable_header_stamp=1
commit_msg_enforce=1

# commit-msg
commit_msg_max_subject=72

# Verible
verible_lint_rules=.rules.verible_lint

# VHDL
vhdl_std=08
ghdl_analyze=0

# Verilator: path to a developer-maintained .f command file (required for
# the pre-push SV elaboration lint; unset => step is skipped locally)
verilator_filelist=rtl.f

# vsg
vsg_config=.vsg.yaml
```

Per-invocation environment overrides (not persisted):

| Variable | Effect |
|----------|--------|
| `HOOKS_SKIP=lint,stamp` | Skip named steps (`format`, `lint`, `stamp`, `push`, `all`) for this run |
| `HOOKS_AUTOFORMAT=1` | `pre-commit` formats in place and re-stages instead of failing |
| `git commit --no-verify` / `git push --no-verify` | Bypass all hooks (standard Git) |

## 7. CI parity

`.github/workflows/hdl.yml` installs the toolchain and runs:

- `make lint` — the same formatter check + Verible lint used by `pre-commit`,
  over all tracked files (not just staged).
- The `pre-push` elaboration commands (`verilator --lint-only`, `ghdl -s`).
- `make test` — the bats suite.

The hook scripts are the single source of truth: CI calls the same `lib/*.sh`
entry points (via `make` targets) rather than re-implementing the commands, so
local hooks and CI cannot drift.

## 8. Testing

`bats` suite; each test builds a throwaway repo in a temp dir via
`helpers.bash` and installs the hooks with `core.hooksPath`.

| File | Cases |
|------|-------|
| `test_pre_commit.bats` | clean SV passes; badly-formatted SV fails with fix hint; `HOOKS_AUTOFORMAT=1` reformats and stages; lint violation fails; VHDL equivalents; missing tool warns and passes; no staged HDL → no-op |
| `test_commit_msg.bats` | valid `feat: x` passes; `bad message` fails; over-length subject fails; `Merge ...` exempt; `commit_msg_enforce=0` disables |
| `test_pre_push.bats` | clean design passes; width mismatch fails (verilator); VHDL syntax error fails (ghdl); missing tool warns and passes |
| `test_header_stamp.bats` | `Date Updated :` line bumped in SV header; bumped in VHDL header; already-today is a no-op; `Date Created :` untouched; `Revision History` untouched; file with no header untouched |

`make test` runs the suite. CI runs `make test`.

## 9. Documentation deliverable

A `README` section (or `docs/hooks.md`) covering: what each hook does, the
one-time `make install`, required vs optional tools and how to get them, the
config keys, and the bypass mechanisms. Explicitly states that the
`Revision History` table is a manual edit and why.

## 10. Open items / future

- `git-cliff` `CHANGELOG.md` generation from the now-enforced Conventional
  Commits — deferred, not in this iteration.
- Optional `pre-commit` guard rejecting stale `Date Updated :` when
  `enable_header_stamp=0`.
- Formal-tool or synthesis lint (e.g. `slang`, vendor lint) in CI.
