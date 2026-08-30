# hdl-git-hooks

Dependency-light Git hooks for FPGA / HDL projects: format and lint staged
SystemVerilog and VHDL on every commit, keep file-header `Date Updated :` lines
current, enforce Conventional Commits, and run a whole-design elaboration lint
before push. Plain POSIX `sh` — no Python, no Node, no framework.

Use it standalone (this repo *is* your project) or vendor it as a git submodule
into a larger HDL project.

## What the hooks do

| Hook | Action |
|------|--------|
| **`pre-commit`** | For staged `.sv .svh .v .vh` and `.vhd .vhdl`: format check (`verible-verilog-format`; `vsg` for VHDL), lint (`verible-verilog-lint`), then bump the `Date Updated :` header line and re-stage. `HOOKS_AUTOFORMAT=1` fixes formatting in place instead of failing. A missing tool is a warning locally, an error in CI. |
| **`commit-msg`** | Require [Conventional Commits](https://www.conventionalcommits.org/) — `type(scope)?: subject`, subject ≤ 72 chars, blank line before any body. `merge` / `revert` / `fixup!` / `squash!` exempt. Toggle with `commit_msg_enforce=0`. |
| **`pre-push`** | Whole-design elaboration lint: `verilator --lint-only` (needs an `rtl.f` command file) for SV, `ghdl -s` for VHDL. Catches width mismatches, inferred latches, undriven nets, incomplete `case`. |

The `Revision History` table in HDL file headers is **not** touched — that stays
a deliberate manual edit. Git is the authoritative per-file history.

## Requirements

The hooks run without any of these installed (steps that need a missing tool are
skipped locally); CI enforces them.

| Tool | Used by | Install |
|------|---------|---------|
| [`verible`](https://github.com/chipsalliance/verible/releases) (`verible-verilog-format`, `verible-verilog-lint`) | pre-commit | download a release tarball |
| [`verilator`](https://verilator.org) | pre-push | `brew install verilator` / `apt install verilator` |
| [`vsg`](https://vsg.readthedocs.io) (VHDL Style Guide) | pre-commit (VHDL) | `pipx install vsg` |
| [`ghdl`](https://ghdl.github.io/ghdl/) | pre-push (VHDL) | `brew install ghdl` / `apt install ghdl` |
| [`bats`](https://github.com/bats-core/bats-core) | `make test` only | `brew install bats-core` |

Git ≥ 2.13 (2.9 if you never run the installer from inside a submodule dir).

## Install — standalone

```sh
make install
```

Sets `core.hooksPath` to `.githooks` and prints which tools are present. Re-run
after every fresh clone — `core.hooksPath` lives in `.git/config`, which is not
cloned.

## Install — as a git submodule

```sh
# path is your choice: deps/hooks, tools/hooks, third_party/hooks, ...
git submodule add <url-of-this-repo> deps/hooks
deps/hooks/scripts/install-hooks.sh
```

The installer detects it is inside a submodule and points the **superproject's**
`core.hooksPath` at `deps/hooks/.githooks`. The hooks then act on the
superproject's files. Re-run `deps/hooks/scripts/install-hooks.sh` after every
fresh clone (`git submodule update --init` does not do it).

Then, at your **project root**:

```sh
cp deps/hooks/examples/gitattributes .gitattributes   # stable line endings
cp deps/hooks/examples/editorconfig  .editorconfig    # indentation
cp deps/hooks/examples/hdl.yml       .github/workflows/hdl.yml   # CI; edit HOOKS_DIR
echo 'include deps/hooks/hooks.mk'  >> Makefile        # make hooks-lint, hooks-format, ...
```

Put your project's `hooks.conf`, `.rules.verible_lint`, `.vsg.yaml` and `rtl.f`
at the project root; they override the copies bundled in the submodule
(`rtl.f` has no fallback — it is project-specific).

See [docs/hooks.md](docs/hooks.md) for the full submodule guide.

## Configuration

Edit `hooks.conf` (precedence: built-in defaults → submodule's `hooks.conf` →
your project's `hooks.conf`):

| Key | Default | Meaning |
|-----|---------|---------|
| `enable_format` / `enable_lint` / `enable_header_stamp` | `1` | per-step toggles for `pre-commit` |
| `commit_msg_enforce` | `1` | Conventional Commits check |
| `commit_msg_max_subject` | `72` | subject length limit |
| `verible_lint_rules` | `.rules.verible_lint` | Verible rule file |
| `vsg_config` | `.vsg.yaml` | vsg config file |
| `verilator_filelist` | `rtl.f` | Verilator `-f` command file for `pre-push` (sources, `+incdir+`, `+define+`, top module) |
| `vhdl_std` | `08` | passed to `ghdl --std=` |
| `ghdl_analyze` | `0` | `1` runs `ghdl -a` instead of `ghdl -s` |

## Make targets

`make install` `lint` `format` `stamp` `elaborate` `test` — standalone. When
vendored, the same via `make hooks-install`, `hooks-lint`, `hooks-format`,
`hooks-stamp`, `hooks-elaborate` (from `hooks.mk`).

## Bypassing

| | |
|---|---|
| `HOOKS_SKIP=lint,stamp git commit …` | skip named steps (`format` `lint` `stamp` `push` `all`) |
| `HOOKS_AUTOFORMAT=1 git commit …` | reformat in place instead of failing |
| `git commit --no-verify` / `git push --no-verify` | skip the hook entirely |

## Development

```sh
make test        # bats suite (needs bats + the HDL tools for full coverage)
```

Design rationale and the implementation history are under
[docs/superpowers/](docs/superpowers/). Treat everything in `.githooks/` and
`hooks.conf` as executable code in review — it runs on contributors' machines,
not just in CI.
