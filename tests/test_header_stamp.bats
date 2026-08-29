load helpers

setup() { setup_repo; }
teardown() { teardown_repo; }

TODAY() { date +%Y-%m-%d; }

@test "bumps Date Updated in a SystemVerilog header" {
  printf '// Date Updated : 2000-01-01\nmodule m; endmodule\n' > m.sv
  run .githooks/lib/header-stamp.sh m.sv
  [ "$status" -eq 0 ]
  [ "$output" = "m.sv" ]
  grep -q "Date Updated : $(TODAY)" m.sv
}

@test "bumps Date Updated in a VHDL header" {
  printf -- '-- Date Updated : 2000-01-01\nentity e is end entity;\n' > e.vhd
  run .githooks/lib/header-stamp.sh e.vhd
  [ "$status" -eq 0 ]
  grep -q -- "-- Date Updated : $(TODAY)" e.vhd
}

@test "already-today prints nothing and changes nothing" {
  printf '// Date Updated : %s\nmodule m; endmodule\n' "$(TODAY)" > m.sv
  cp m.sv ref
  run .githooks/lib/header-stamp.sh m.sv
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  cmp m.sv ref
}

@test "leaves Date Created untouched" {
  printf '// Date Created : 2000-01-01\n// Date Updated : 2000-01-01\n' > m.sv
  .githooks/lib/header-stamp.sh m.sv
  grep -q "Date Created : 2000-01-01" m.sv
}

@test "leaves a Revision History row untouched" {
  printf '// YYYY-MM-DD  jdoe  Initial creation\n// Date Updated : 2000-01-01\n' > m.sv
  .githooks/lib/header-stamp.sh m.sv
  grep -q "YYYY-MM-DD  jdoe  Initial creation" m.sv
}

@test "file without the header line is left byte-for-byte identical" {
  printf 'module m; endmodule\n' > m.sv
  cp m.sv ref
  run .githooks/lib/header-stamp.sh m.sv
  [ -z "$output" ]
  cmp m.sv ref
}

@test "handles multiple files, prints only the changed ones" {
  printf '// Date Updated : 2000-01-01\n' > a.sv
  printf '// Date Updated : %s\n' "$(TODAY)" > b.sv
  printf 'no header\n' > c.sv
  run .githooks/lib/header-stamp.sh a.sv b.sv c.sv
  [ "$output" = "a.sv" ]
}
