load helpers

setup() { setup_repo; }
teardown() { teardown_repo; }

@test "lang_of classifies extensions" {
  run sh -c '. .githooks/lib/common.sh; lang_of a.sv; lang_of b.vhd; lang_of c.txt'
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "sv" ]
  [ "${lines[1]}" = "vhdl" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "config defaults load when hooks.conf absent" {
  rm -f hooks.conf
  run sh -c '. .githooks/lib/common.sh; echo "$commit_msg_max_subject/$enable_format"'
  [ "$output" = "72/1" ]
}

@test "hooks.conf overrides a default" {
  echo 'commit_msg_max_subject=50' > hooks.conf
  run sh -c '. .githooks/lib/common.sh; echo "$commit_msg_max_subject"'
  [ "$output" = "50" ]
}

@test "staged_hdl_files lists only staged, on-disk HDL" {
  printf 'module m; endmodule\n' > keep.sv
  printf 'entity e is end;\n'   > keep.vhd
  echo hi > notes.txt
  git add keep.sv keep.vhd notes.txt
  run sh -c '. .githooks/lib/common.sh; staged_hdl_files'
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qx keep.sv
  printf '%s\n' "$output" | grep -qx keep.vhd
  ! printf '%s\n' "$output" | grep -qx notes.txt
}

@test "skip_requested honours HOOKS_SKIP and 'all'" {
  run sh -c 'HOOKS_SKIP=lint,stamp; . .githooks/lib/common.sh; skip_requested lint && echo yes'
  [ "$output" = "yes" ]
  run sh -c 'HOOKS_SKIP=all; . .githooks/lib/common.sh; skip_requested format && echo yes'
  [ "$output" = "yes" ]
  run sh -c 'HOOKS_SKIP=; . .githooks/lib/common.sh; skip_requested lint || echo no'
  [ "$output" = "no" ]
}

@test "have_tool true for sh, false for a bogus name" {
  run sh -c '. .githooks/lib/common.sh; have_tool sh && ! have_tool definitely-not-a-tool-xyz && echo ok'
  [ "$output" = "ok" ]
}
