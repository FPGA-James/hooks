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

@test "valid: 72 multibyte chars is within the limit (counted in characters, not bytes)" {
  # wc -m honours LC_CTYPE; under a C locale it degrades to byte counting, so
  # pin a UTF-8 locale that actually exists here (en_US.UTF-8 on macOS,
  # C.UTF-8 on CI) to make the character-vs-byte distinction real.
  locale -a 2>/dev/null | grep -qiE 'utf-?8' || skip "no UTF-8 locale"
  loc=$(locale -a 2>/dev/null | grep -iE '\.(utf-?8)$' | grep -iE '^(C|en_US)\.' | head -n1)
  [ -n "$loc" ] || loc=$(locale -a 2>/dev/null | grep -iE 'utf-?8' | head -n1)
  subject=$(printf 'é%.0s' $(seq 1 72))
  printf 'feat: %s\n' "$subject" > "$TESTDIR/MSG"
  run env LC_ALL="$loc" LC_CTYPE="$loc" .githooks/commit-msg "$TESTDIR/MSG"
  [ "$status" -eq 0 ]
}

@test "invalid: body not separated from the subject by a blank line" {
  printf 'feat: x\nno blank line here\n' > "$TESTDIR/MSG"
  run .githooks/commit-msg "$TESTDIR/MSG"
  [ "$status" -eq 1 ]
  assert_output_contains "blank line"
}

@test "valid: git commit -v scissors diff is not mistaken for a body" {
  # `git commit -v` appends the scissors marker and the diff to the message file
  # and strips them only AFTER commit-msg runs, so the hook must cut them itself.
  # NB: git's template puts the comment block immediately after the subject
  # line, with no blank line between them -- so once the '#' lines are stripped
  # the first diff line lands on line 2 and looks exactly like a body.
  {
    printf 'feat: add thing\n'
    printf '# Please enter the commit message for your changes. Lines starting\n'
    printf "# with '#' will be ignored, and an empty message aborts the commit.\n"
    printf '#\n'
    printf '# On branch master\n'
    printf '# ------------------------ >8 ------------------------\n'
    printf '# Do not modify or remove the line above.\n'
    printf '# Everything below it will be ignored.\n'
    printf 'diff --git a/x b/x\n'
    printf 'index e31de1f..0835e4f 100644\n'
    printf -- '--- a/x\n'
    printf '+++ b/x\n'
    printf '@@ -1 +1 @@\n'
    printf -- '-seed\n'
    printf '+change\n'
  } > "$TESTDIR/MSG"
  run .githooks/commit-msg "$TESTDIR/MSG"
  [ "$status" -eq 0 ]
}

@test "valid: body separated from the subject by a blank line" {
  printf 'feat: x\n\nProper body paragraph.\n' > "$TESTDIR/MSG"
  run .githooks/commit-msg "$TESTDIR/MSG"
  [ "$status" -eq 0 ]
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
