# Makefile fragment for projects that vendor this hooks repo.
#
#   include deps/hooks/hooks.mk          # from your project Makefile
#   make -f deps/hooks/hooks.mk hooks-lint   # or run directly
#
# Targets are prefixed `hooks-` so they never collide with your own. Override
# the HDL file set with `make HDL='a.sv b.vhd' hooks-lint` if the default
# `git ls-files` glob is not what you want.

# Directory this fragment lives in (works for include and -f).
_HOOKS_DIR := $(patsubst %/,%,$(dir $(lastword $(MAKEFILE_LIST))))

HDL ?= $(shell git ls-files '*.sv' '*.svh' '*.v' '*.vh' '*.vhd' '*.vhdl')

.PHONY: hooks-install hooks-stamp hooks-format hooks-lint hooks-elaborate

hooks-install:
	$(_HOOKS_DIR)/scripts/install-hooks.sh

hooks-stamp:
	@$(_HOOKS_DIR)/.githooks/lib/header-stamp.sh $(HDL) || true

hooks-format:
	@HOOKS_AUTOFORMAT=1 $(_HOOKS_DIR)/.githooks/lib/hdl-format.sh $(HDL)

hooks-lint:
	@$(_HOOKS_DIR)/.githooks/lib/hdl-format.sh $(HDL)
	@$(_HOOKS_DIR)/.githooks/lib/hdl-lint.sh $(HDL)

hooks-elaborate:
	@printf '%s\n' $(HDL) | $(_HOOKS_DIR)/.githooks/lib/hdl-elaborate.sh ci
