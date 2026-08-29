load helpers

setup() { setup_repo; }
teardown() { teardown_repo; }

@test "hdl-format: missing tool warns and passes" {
  # Only meaningful on a machine without verible; otherwise skip.
  if command -v verible-verilog-format >/dev/null; then skip "verible present"; fi
  printf 'module   m ;endmodule\n' > m.sv
  run .githooks/lib/hdl-format.sh m.sv
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipping"* ]]
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

@test "hdl-format: badly styled VHDL fails" {
  command -v vsg >/dev/null || skip "vsg not installed"
  printf 'entity e is end entity;\n' > e.vhd
  run .githooks/lib/hdl-format.sh e.vhd
  [ "$status" -eq 1 ]
  [[ "$output" == *"not formatted"* ]]
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
  if command -v verible-verilog-lint >/dev/null; then skip "verible present"; fi
  printf 'module m; endmodule\n' > m.sv
  run .githooks/lib/hdl-lint.sh m.sv
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipping"* ]]
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
