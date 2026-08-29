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
