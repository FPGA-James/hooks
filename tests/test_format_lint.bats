load helpers

setup() { setup_repo; }
teardown() { teardown_repo; }

# Scratch PATH holding only git (plus the system dirs); verible and vsg live in
# homebrew / ~/.local, so the hooks hit their missing-tool branch for real
# instead of skipping the case on machines that have the tools installed.
scrub_path() {
  mkdir -p "$TESTDIR/nobin"
  ln -sf "$(command -v git)" "$TESTDIR/nobin/git"
  printf '%s' "$TESTDIR/nobin:/usr/bin:/bin"
}

@test "hdl-format: missing tool warns and passes" {
  printf 'module   m ;endmodule\n' > m.sv
  run env PATH="$(scrub_path)" .githooks/lib/hdl-format.sh m.sv
  [ "$status" -eq 0 ]
  assert_output_contains "skipping"
}

@test "hdl-format: well-formatted SV passes" {
  command -v verible-verilog-format >/dev/null || skip "verible not installed"
  # This verible build needs '-' to read stdin.
  verible-verilog-format - <<'EOF' > m.sv
module m (
    input logic clk
);
endmodule
EOF
  run .githooks/lib/hdl-format.sh m.sv
  [ "$status" -eq 0 ]
}

@test "hdl-format: badly formatted SV fails with a fix hint" {
  command -v verible-verilog-format >/dev/null || skip "verible not installed"
  printf 'module   m ;\nendmodule\n' > m.sv
  run .githooks/lib/hdl-format.sh m.sv
  [ "$status" -eq 1 ]
  [[ "$output" == *"not formatted"* ]]
  [[ "$output" == *"make format"* ]]
}

@test "hdl-format: HOOKS_AUTOFORMAT rewrites and passes" {
  command -v verible-verilog-format >/dev/null || skip "verible not installed"
  printf 'module   m ;\nendmodule\n' > m.sv
  run env HOOKS_AUTOFORMAT=1 .githooks/lib/hdl-format.sh m.sv
  [ "$status" -eq 0 ]
  run .githooks/lib/hdl-format.sh m.sv
  [ "$status" -eq 0 ]
}

@test "hdl-format: well-formatted VHDL passes" {
  command -v vsg >/dev/null || skip "vsg not installed"
  # Exactly as `vsg --fix` leaves it, so the check has nothing to report.
  cat > e.vhd <<'EOF'
library ieee;
    use ieee.std_logic_1164.all;

entity example is
    port (
        clk : in    std_logic
    );
end entity example;

architecture rtl of example is

begin

end architecture rtl;
EOF
  run .githooks/lib/hdl-format.sh e.vhd
  [ "$status" -eq 0 ]
}

@test "hdl-format: badly styled VHDL fails and shows the vsg rule violations" {
  command -v vsg >/dev/null || skip "vsg not installed"
  printf 'entity e is end entity;\n' > e.vhd
  run .githooks/lib/hdl-format.sh e.vhd
  [ "$status" -eq 1 ]
  assert_output_contains "not formatted"
  # the specific rules must reach the developer, not /dev/null
  assert_output_contains "entity_021"
  assert_output_contains "Rule"
}

@test "checkout path containing a space: format + lint still work" {
  command -v verible-verilog-lint >/dev/null || skip "verible not installed"
  d="$BATS_TEST_TMPDIR/hook test"
  mkdir -p "$d"
  cd "$d" || return 1
  git init -q
  git config user.email test@example.com
  git config user.name "Hook Test"
  cp -R "$BATS_TEST_DIRNAME/../.githooks" .
  cp "$BATS_TEST_DIRNAME/../hooks.conf" .
  for f in .rules.verible_lint .vsg.yaml; do
    [ -f "$BATS_TEST_DIRNAME/../$f" ] && cp "$BATS_TEST_DIRNAME/../$f" .
  done
  chmod +x .githooks/lib/*.sh

  printf 'module m;\nendmodule\n' > m.sv
  run .githooks/lib/hdl-lint.sh m.sv
  [ "$status" -eq 0 ]
  assert_output_missing "No such file or directory"
  run .githooks/lib/hdl-format.sh m.sv
  [ "$status" -eq 0 ]
  assert_output_missing "No such file or directory"

  if command -v vsg >/dev/null; then
    cat > e.vhd <<'EOF'
library ieee;
    use ieee.std_logic_1164.all;

entity example is
    port (
        clk : in    std_logic
    );
end entity example;

architecture rtl of example is

begin

end architecture rtl;
EOF
    run .githooks/lib/hdl-format.sh e.vhd
    [ "$status" -eq 0 ]
    assert_output_missing "No such file or directory"
  fi
}

@test "hdl-lint: clean SV passes" {
  command -v verible-verilog-lint >/dev/null || skip "verible not installed"
  printf 'module m;\nendmodule\n' > m.sv
  run .githooks/lib/hdl-lint.sh m.sv
  [ "$status" -eq 0 ]
}

@test "hdl-lint: a lint violation fails the check" {
  command -v verible-verilog-lint >/dev/null || skip "verible not installed"
  # A hard tab in source trips +no-tabs from .rules.verible_lint.
  printf 'module m;\n\tendmodule\n' > m.sv
  run .githooks/lib/hdl-lint.sh m.sv
  [ "$status" -eq 1 ]
}

@test "hdl-lint: missing tool warns and passes" {
  printf 'module m; endmodule\n' > m.sv
  run env PATH="$(scrub_path)" .githooks/lib/hdl-lint.sh m.sv
  [ "$status" -eq 0 ]
  assert_output_contains "skipping"
}

@test "hdl-lint: ignores VHDL files" {
  printf 'entity e is end entity;\n' > e.vhd
  run .githooks/lib/hdl-lint.sh e.vhd
  [ "$status" -eq 0 ]
}

@test "hdl-lint: no HDL files is a pass" {
  printf 'hello\n' > notes.txt
  run .githooks/lib/hdl-lint.sh notes.txt
  [ "$status" -eq 0 ]
}
