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

# Assertions on $output. Use these instead of a bare `[[ "$output" == *x* ]]`:
# `[[ ]]` is a shell keyword, so on bash 3.2 (the system bash on macOS) a failing
# one does NOT trip bats' errexit and the assertion silently passes.
assert_output_contains() {
  case "$output" in
    *"$1"*) return 0 ;;
  esac
  printf 'expected output to contain: %s\n--- output ---\n%s\n' "$1" "$output" >&2
  return 1
}

assert_output_missing() {
  case "$output" in
    *"$1"*)
      printf 'expected output NOT to contain: %s\n--- output ---\n%s\n' "$1" "$output" >&2
      return 1
      ;;
  esac
  return 0
}

teardown_repo() {
  cd /
  [ -n "${TESTDIR:-}" ] && rm -rf "$TESTDIR"
}
