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
