load helpers

setup() { setup_repo; }
teardown() { teardown_repo; }

@test "no tracked HDL: elaborate passes trivially" {
  run sh -c ': | .githooks/lib/hdl-elaborate.sh local'
  [ "$status" -eq 0 ]
}

@test "SV, verilator present, no filelist: warn + pass in local" {
  command -v verilator >/dev/null || skip "verilator not installed"
  printf 'module top; endmodule\n' > top.sv
  run sh -c 'printf "top.sv\n" | .githooks/lib/hdl-elaborate.sh local'
  [ "$status" -eq 0 ]
  [[ "$output" == *"unconfigured"* || "$output" == *"not found"* ]]
}

@test "SV, verilator present, no filelist: hard fail in ci" {
  command -v verilator >/dev/null || skip "verilator not installed"
  printf 'module top; endmodule\n' > top.sv
  run sh -c 'printf "top.sv\n" | .githooks/lib/hdl-elaborate.sh ci'
  [ "$status" -ne 0 ]
}

@test "SV clean design with a filelist passes" {
  command -v verilator >/dev/null || skip "verilator not installed"
  printf 'module top (input logic a, output logic b);\n  assign b = a;\nendmodule\n' > top.sv
  printf 'top.sv\n' > rtl.f
  run sh -c 'printf "top.sv\n" | .githooks/lib/hdl-elaborate.sh local'
  [ "$status" -eq 0 ]
}

@test "SV width mismatch is caught" {
  command -v verilator >/dev/null || skip "verilator not installed"
  cat > top.sv <<'EOF'
module top (output logic [3:0] q);
  logic [7:0] wide;
  assign wide = 8'hAA;
  assign q = wide;
endmodule
EOF
  printf 'top.sv\n' > rtl.f
  run sh -c 'printf "top.sv\n" | .githooks/lib/hdl-elaborate.sh local'
  [ "$status" -ne 0 ]
}

@test "VHDL syntax error is caught by ghdl" {
  command -v ghdl >/dev/null || skip "ghdl not installed"
  printf 'entity e is end entity\n' > e.vhd   # missing terminating ;
  run sh -c 'printf "e.vhd\n" | .githooks/lib/hdl-elaborate.sh local'
  [ "$status" -ne 0 ]
}

@test "pre-push consumes stdin refs and passes when no HDL tracked" {
  echo hi > README.md; git add README.md
  git -c core.hooksPath= commit -q -m "docs: readme"
  run sh -c 'printf "refs/heads/main abc refs/heads/main def\n" | .githooks/pre-push origin git@example:repo.git'
  [ "$status" -eq 0 ]
}

@test "pre-push skips on HOOKS_SKIP=push" {
  command -v verilator >/dev/null || skip "verilator not installed"
  printf 'module top; endmodule\n' > top.sv
  git -c core.hooksPath= add top.sv
  git -c core.hooksPath= commit -q -m "feat: top"
  run sh -c 'printf "\n" | env HOOKS_SKIP=push .githooks/pre-push origin url'
  [ "$status" -eq 0 ]
}
