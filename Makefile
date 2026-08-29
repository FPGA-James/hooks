SHELL := /bin/sh

# All tracked HDL sources, space separated.
HDL := $(shell git ls-files '*.sv' '*.svh' '*.v' '*.vh' '*.vhd' '*.vhdl')

.PHONY: install test stamp format lint

install:
	./scripts/install-hooks.sh

test:
	bats tests/

stamp:
	@.githooks/lib/header-stamp.sh $(HDL) || true

format:
	@HOOKS_AUTOFORMAT=1 .githooks/lib/hdl-format.sh $(HDL)

lint:
	@.githooks/lib/hdl-format.sh $(HDL)
	@.githooks/lib/hdl-lint.sh $(HDL)
