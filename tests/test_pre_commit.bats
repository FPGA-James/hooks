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
  # Written directly in verible's canonical layout (piping the heredoc through
  # `verible-verilog-format` without the explicit `-` stdin arg errors on this
  # build and leaves an empty file). Intent is unchanged: a well-formed staged
  # .sv gets its "Date Updated" bumped and lands in the commit.
  printf '// Date Updated : 2000-01-01\nmodule m (\n    input logic clk\n);\nendmodule\n' > m.sv
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
  # Point the hook's PATH at a scratch dir holding only git; verible lives in
  # homebrew (not /usr/bin or /bin), so format/lint hit their missing-tool
  # branch and are skipped, while header-stamp must still bump the date.
  mkdir "$TESTDIR/nobin"
  ln -s "$(command -v git)" "$TESTDIR/nobin/git"
  printf '// Date Updated : 2000-01-01\nmodule m; endmodule\n' > m.sv
  git add m.sv
  run env PATH="$TESTDIR/nobin:/usr/bin:/bin" git commit -m "feat: add m"
  [ "$status" -eq 0 ]
  git show HEAD:m.sv | grep -q "Date Updated : $(date +%Y-%m-%d)"
}

@test "HOOKS_AUTOFORMAT commits the formatted content, not the staged original" {
  command -v verible-verilog-format >/dev/null || skip "verible not installed"
  printf 'module   m ;\nendmodule\n' > m.sv
  git add m.sv
  run env HOOKS_AUTOFORMAT=1 git commit -m "feat: add m"
  [ "$status" -eq 0 ]
  # m.sv must be clean in both index and worktree: the reformatted content was
  # re-staged rather than left behind as an unstaged edit. (The fixture's own
  # .githooks/ and hooks.conf are untracked, so scope the check to m.sv.)
  [ -z "$(git status --porcelain -- m.sv)" ]
  # and the committed blob must be byte-identical to verible's output
  verible-verilog-format m.sv > "$BATS_TEST_TMPDIR/expected.sv"
  git show HEAD:m.sv > "$BATS_TEST_TMPDIR/committed.sv"
  cmp "$BATS_TEST_TMPDIR/expected.sv" "$BATS_TEST_TMPDIR/committed.sv"
}

@test "partial staging: stamped file is re-staged whole, with a warning" {
  printf '// Date Updated : 2000-01-01\nmodule m; endmodule\n' > m.sv
  git add m.sv
  # extra edit that was deliberately NOT staged
  printf '// Date Updated : 2000-01-01\nmodule m; endmodule\n// unstaged marker\n' > m.sv
  run env HOOKS_SKIP=format,lint git commit -m "feat: add m"
  [ "$status" -eq 0 ]
  assert_output_contains "re-staged"
  # documents the actual behaviour: the unstaged edit rode along
  git show HEAD:m.sv | grep -q "unstaged marker"
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
  # committed verbatim: unformatted (triple space) and unstamped
  git show HEAD:m.sv | grep -q 'module   m'
}
