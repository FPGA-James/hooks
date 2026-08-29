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
