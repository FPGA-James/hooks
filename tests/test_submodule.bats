load helpers

# These tests cover using this repo vendored inside a larger project (the
# "submodule" case): install-hooks.sh path resolution, the hooks acting on the
# enclosing repo, and the layered hooks.conf / resolve_conf behaviour.

HOOKS_SRC="" # set in setup

setup() {
  HOOKS_SRC="$BATS_TEST_DIRNAME/.."
  # pwd -P so paths compare cleanly against git's physical paths (macOS puts
  # mktemp dirs under a symlinked /var -> /private/var).
  TESTROOT="$(cd "$(mktemp -d)" && pwd -P)"
}

teardown() {
  cd /
  [ -n "${TESTROOT:-}" ] && rm -rf "$TESTROOT"
}

# Copy the hook tree into <dir> as a plain subdirectory (no nested git repo).
vendor_into() {
  dest=$1
  mkdir -p "$dest"
  cp -R "$HOOKS_SRC/.githooks" "$dest/"
  cp -R "$HOOKS_SRC/scripts" "$dest/"
  cp "$HOOKS_SRC/hooks.mk" "$dest/"
  for f in hooks.conf .rules.verible_lint .vsg.yaml; do
    [ -f "$HOOKS_SRC/$f" ] && cp "$HOOKS_SRC/$f" "$dest/"
  done
  chmod +x "$dest"/.githooks/pre-commit "$dest"/.githooks/commit-msg \
           "$dest"/.githooks/pre-push 2>/dev/null || true
  chmod +x "$dest"/.githooks/lib/*.sh "$dest"/scripts/*.sh 2>/dev/null || true
}

new_repo() {
  git init -q "$1"
  git -C "$1" config user.email test@example.com
  git -C "$1" config user.name "Hook Test"
  git -C "$1" config commit.gpgsign false
}

@test "install-hooks.sh standalone still sets core.hooksPath to .githooks" {
  new_repo "$TESTROOT/solo"
  vendor_into "$TESTROOT/solo/tmp"
  # move the vendored tree to the repo root to mimic a standalone checkout
  mv "$TESTROOT/solo/tmp/.githooks" "$TESTROOT/solo/tmp/scripts" \
     "$TESTROOT/solo/tmp/hooks.mk" "$TESTROOT/solo/"
  [ -f "$TESTROOT/solo/tmp/hooks.conf" ] && mv "$TESTROOT/solo/tmp/hooks.conf" "$TESTROOT/solo/"
  rmdir "$TESTROOT/solo/tmp" 2>/dev/null || rm -rf "$TESTROOT/solo/tmp"

  cd "$TESTROOT/solo"
  run ./scripts/install-hooks.sh
  [ "$status" -eq 0 ]
  [ "$(git config core.hooksPath)" = ".githooks" ]
}

@test "install-hooks.sh from a subdir sets a worktree-relative hooksPath" {
  new_repo "$TESTROOT/proj"
  vendor_into "$TESTROOT/proj/deps/hooks"
  cd "$TESTROOT/proj"

  run deps/hooks/scripts/install-hooks.sh
  [ "$status" -eq 0 ]
  [ "$(git config core.hooksPath)" = "deps/hooks/.githooks" ]
  assert_output_contains "deps/hooks/.githooks"
}

@test "vendored hooks lint the enclosing repo's files" {
  command -v verible-verilog-format >/dev/null || skip "verible not installed"
  new_repo "$TESTROOT/proj"
  vendor_into "$TESTROOT/proj/deps/hooks"
  cd "$TESTROOT/proj"
  deps/hooks/scripts/install-hooks.sh >/dev/null

  printf 'module   m ;\nendmodule\n' > top.sv
  git add top.sv
  run git commit -m "feat: add top"
  [ "$status" -ne 0 ]
  assert_output_contains "not formatted"
  run git rev-parse HEAD
  [ "$status" -ne 0 ]
}

@test "vendored hooks stamp a clean enclosing-repo file and commit it" {
  command -v verible-verilog-format >/dev/null || skip "verible not installed"
  new_repo "$TESTROOT/proj"
  vendor_into "$TESTROOT/proj/deps/hooks"
  cd "$TESTROOT/proj"
  deps/hooks/scripts/install-hooks.sh >/dev/null

  # module name must match the file stem: .rules.verible_lint enables module-filename
  verible-verilog-format - > top.sv <<'EOF'
// Date Updated : 2000-01-01
module top (
    input logic clk
);
endmodule
EOF
  git add top.sv
  run git commit -m "feat: add top"
  [ "$status" -eq 0 ]
  git show HEAD:top.sv | grep -q "Date Updated : $(date +%Y-%m-%d)"
}

@test "project hooks.conf overrides the bundled one" {
  new_repo "$TESTROOT/proj"
  vendor_into "$TESTROOT/proj/deps/hooks"
  cd "$TESTROOT/proj"
  printf 'commit_msg_max_subject=999\n' > deps/hooks/hooks.conf
  printf 'commit_msg_max_subject=11\n' > hooks.conf

  run env HOOK_DIR="$PWD/deps/hooks/.githooks" \
      sh -c '. deps/hooks/.githooks/lib/common.sh; printf "%s\n" "$commit_msg_max_subject"'
  [ "$status" -eq 0 ]
  [ "$output" = "11" ]
}

@test "bundled hooks.conf applies when the project has none" {
  new_repo "$TESTROOT/proj"
  vendor_into "$TESTROOT/proj/deps/hooks"
  cd "$TESTROOT/proj"
  printf 'enable_lint=0\n' > deps/hooks/hooks.conf
  rm -f hooks.conf

  run env HOOK_DIR="$PWD/deps/hooks/.githooks" \
      sh -c '. deps/hooks/.githooks/lib/common.sh; printf "%s\n" "$enable_lint"'
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "resolve_conf falls back to the bundled config, prefers the project's" {
  new_repo "$TESTROOT/proj"
  vendor_into "$TESTROOT/proj/deps/hooks"
  cd "$TESTROOT/proj"
  printf 'x\n' > deps/hooks/.rules.verible_lint
  rm -f .rules.verible_lint

  run env HOOK_DIR="$PWD/deps/hooks/.githooks" \
      sh -c '. deps/hooks/.githooks/lib/common.sh; resolve_conf .rules.verible_lint'
  [ "$status" -eq 0 ]
  [ "$output" = "$TESTROOT/proj/deps/hooks/.rules.verible_lint" ]

  printf 'y\n' > .rules.verible_lint
  run env HOOK_DIR="$PWD/deps/hooks/.githooks" \
      sh -c '. deps/hooks/.githooks/lib/common.sh; resolve_conf .rules.verible_lint'
  [ "$output" = "$TESTROOT/proj/.rules.verible_lint" ]
}

@test "real git submodule: installer targets the superproject, hooks fire on it" {
  command -v verible-verilog-format >/dev/null || skip "verible not installed"

  # Build an origin repo from the current hook tree.
  origin="$TESTROOT/hooks-origin"
  vendor_into "$origin"
  ( cd "$origin" && git init -q && git config user.email t@e && git config user.name t \
    && git config commit.gpgsign false && git add -A && git commit -qm "hooks" )

  # Superproject that adds it as a submodule at deps/hooks.
  new_repo "$TESTROOT/super"
  cd "$TESTROOT/super"
  git -c protocol.file.allow=always submodule add -q "$origin" deps/hooks
  git commit -qm "add hooks submodule"

  run deps/hooks/scripts/install-hooks.sh
  [ "$status" -eq 0 ]
  [ "$(git config core.hooksPath)" = "deps/hooks/.githooks" ]

  printf 'module   m ;\nendmodule\n' > top.sv
  git add top.sv
  run git commit -m "feat: add top"
  [ "$status" -ne 0 ]
  assert_output_contains "not formatted"
}
