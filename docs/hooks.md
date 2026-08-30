# Git hooks

This repo ships Git hooks under [`.githooks/`](../.githooks) that help keep the
HDL clean and the file headers current.

## Install (once per clone)

```sh
make install          # standalone repo
# or, when vendored:  deps/hooks/scripts/install-hooks.sh
```

This runs `git config core.hooksPath …` (pointing at this repo's `.githooks/`,
wherever it sits) and prints which optional tools are present. Missing tools
are skipped locally; CI enforces all of them. See
[Using it as a git submodule](#using-it-as-a-git-submodule) for the vendored
case.

## Using it as a git submodule

You can vendor this repo into a larger HDL project instead of copying the
scripts. The hooks then lint, format and stamp the **enclosing project's**
files — nothing needs to change in the hook logic, because everything keys off
`git rev-parse --show-toplevel`, which resolves to the superproject when the
superproject's `git commit` / `git push` fires a hook.

```sh
# path is your choice — deps/hooks, tools/hooks, third_party/hooks, ...
git submodule add <url> deps/hooks
deps/hooks/scripts/install-hooks.sh
```

`install-hooks.sh` detects that it lives inside a submodule and sets
`core.hooksPath` in the **superproject** to `deps/hooks/.githooks` (relative to
the superproject root, whatever path you chose). Like any `core.hooksPath`
setting it lives in `.git/config`, so **every fresh clone of your project must
re-run it** — `git submodule update --init` does not. Add a bootstrap line to
your project README or a setup script.

Requires git ≥ 2.13 (submodule detection) / ≥ 2.9 (relative `core.hooksPath`).

### Project-level configuration

Put these at your **project root**; they override the copies bundled in the
submodule:

| File | Purpose |
|------|---------|
| `hooks.conf` | feature toggles / limits — see [Configuration](#configuration) |
| `.rules.verible_lint` | Verible lint rules (falls back to the submodule's copy) |
| `.vsg.yaml` | vsg config (falls back to the submodule's copy) |
| `rtl.f` | Verilator command file — **no fallback**, this is project-specific |

Config precedence: built-in defaults → `deps/hooks/hooks.conf` → your
project's `hooks.conf`.

### Project scaffolding

```sh
deps/hooks/scripts/scaffold.sh
```

Run from the superproject after adding the submodule. It:

- **creates or extends** `.gitattributes` and `.editorconfig` at your project
  root — the added lines live between
  `# >>> hdl-git-hooks (managed) >>>` and `# <<< hdl-git-hooks <<<`, so a
  re-run refreshes only that block and anything you added outside it is kept.
  `root = true` is only written when the `.editorconfig` is created fresh.
- **appends `include <path>/hooks.mk`** to your `Makefile` (or creates a
  minimal one), giving you `make hooks-lint`, `hooks-format`, `hooks-stamp`,
  `hooks-elaborate`, `hooks-install`. Paths auto-resolve to wherever you put
  the submodule. Or skip the include: `make -f deps/hooks/hooks.mk hooks-lint`.
- **installs `.github/workflows/hdl.yml`** (from `examples/hdl.yml`, with the
  submodule path substituted in) *only if you don't already have one*. If you
  do, merge the hook steps from `examples/hdl.yml` yourself.

It is idempotent — safe to re-run after a `git submodule update` to pick up
template changes.

The submodule keeps its own `.github/workflows/hdl.yml` (it runs its own bats
suite); that workflow does nothing in your project — use `examples/hdl.yml`.

## What runs when

| Hook | Action |
|------|--------|
| `pre-commit` | On staged `.sv/.svh/.v/.vh` and `.vhd/.vhdl`: format check (`verible-verilog-format`; `vsg` for VHDL), lint (`verible-verilog-lint`), and bump the `Date Updated :` header line (re-staged automatically). |
| `commit-msg` | Require [Conventional Commits](https://www.conventionalcommits.org/): `type(scope)?: subject`, subject ≤ 72 chars. Merge/revert/fixup/squash exempt. |
| `pre-push` | Whole-design elaboration lint: `verilator --lint-only` (needs `rtl.f`) and `ghdl -s`. |

### Caveats

**Partial staging.** The `pre-commit` header-stamp step runs `git add` on every
HDL file whose `Date Updated :` line it bumps. `git add` stages the *whole*
file, so any **other** unstaged modification sitting in that file is swept into
the commit as well. When that happens the stamp step warns (`re-staged <file> —
unstaged changes in it are now part of this commit`) but never blocks.

`HOOKS_AUTOFORMAT=1` has the same effect for a different reason: files it
rewrites are re-staged so the commit contains the formatted content. That
re-stage is silent — no `re-staged` warning is printed for it.

Commit HDL files whole. If you are deliberately committing only part of a file
(`git add -p`), use `HOOKS_SKIP=stamp git commit …` and bump the header date by
hand.

## Tools

| Tool | Used by | Install |
|------|---------|---------|
| `verible-verilog-format`, `verible-verilog-lint` | pre-commit | https://github.com/chipsalliance/verible/releases |
| `verilator` | pre-push | `brew install verilator` / `apt install verilator` |
| `vsg` | pre-commit (VHDL) | `pipx install vsg` |
| `ghdl` | pre-push (VHDL) | `brew install ghdl` / `apt install ghdl` |
| `bats` | `make test` | `brew install bats-core` |

**Verible version.** CI pins `v0.0-3946-g851d3ff4` (see
[`.github/workflows/hdl.yml`](../.github/workflows/hdl.yml)); that is the
supported reference version. `verible-verilog-format` output is not stable
across releases, so a local formatter on a different version can produce a file
that CI then rejects. Match the pinned version locally.

## Configuration

Edit [`hooks.conf`](../hooks.conf) (committed, shared by every clone):

- `enable_format` / `enable_lint` / `enable_header_stamp` / `commit_msg_enforce` — feature toggles.
- `commit_msg_max_subject` — subject length limit.
- `verilator_filelist` — path to the `.f` command file for the pre-push SV lint. Maintain this by hand as the design grows; without it the SV elaboration lint is skipped locally and fails in CI.
- `vhdl_std`, `ghdl_analyze`, `verible_lint_rules`, `vsg_config`.

## For PR reviewers

Treat everything under `.githooks/` and `hooks.conf` as **executable code**.
Once a developer has run `make install`, `hooks.conf` is `.`-sourced and the
`.githooks/` scripts run on every commit and push — a change to either executes
on contributors' machines, not just in CI. Review them with the same care as
any other code that runs locally.

## Bypassing

- `HOOKS_SKIP=lint,stamp git commit …` — skip named steps (`format`, `lint`, `stamp`, `push`, `all`).
- `HOOKS_AUTOFORMAT=1 git commit …` — reformat staged files in place instead of failing.
- `git commit --no-verify` / `git push --no-verify` — skip the hook entirely.

## Not automated on purpose

The `Revision History` table in the file templates is a **manual** edit. Add a
row when a change is worth a line; the authoritative per-file history is
`git log -p --follow <file>`. Commit-message text is never written into files.
