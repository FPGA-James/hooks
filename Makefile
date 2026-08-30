SHELL := /bin/sh

# Standalone use: the hooks live at the repo root, so hooks.mk sits alongside
# this file and `_HOOKS_DIR` resolves to `.`. The short aliases below just
# forward to the `hooks-` targets so `make lint` etc. keep working here.
include hooks.mk

.PHONY: install test stamp format lint elaborate

install:   hooks-install

test:
	bats tests/

stamp:     hooks-stamp
format:    hooks-format
lint:      hooks-lint
elaborate: hooks-elaborate
