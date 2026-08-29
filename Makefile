SHELL := /bin/sh

# All tracked HDL sources, space separated.
HDL := $(shell git ls-files '*.sv' '*.svh' '*.v' '*.vh' '*.vhd' '*.vhdl')

.PHONY: install test

install:
	./scripts/install-hooks.sh

test:
	bats tests/
