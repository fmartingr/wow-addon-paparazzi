SHELL := bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help

LUA_COVERAGE_MIN ?= 80
BUSTED_FLAGS ?=

LR_PATH := $(shell luarocks --lua-version=5.1 --local path --lr-path 2>/dev/null)
LR_CPATH := $(shell luarocks --lua-version=5.1 --local path --lr-cpath 2>/dev/null)
export PATH := $(HOME)/.luarocks/bin:$(PATH)
export LUA_PATH := $(LR_PATH);$(LUA_PATH);;
export LUA_CPATH := $(LR_CPATH);$(LUA_CPATH);;

.PHONY: help check-tools deps lint lint-lua fmt-check fmt test test-lua coverage coverage-lua link clean

help: ## List the targets
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "%-16s %s\n", $$1, $$2}'

check-tools: ## Report each missing tool
	@missing=0; for t in lua5.1 luarocks busted luacheck stylua go; do \
		if ! command -v $$t >/dev/null; then echo "missing: $$t"; missing=1; fi; \
	done; exit $$missing

deps: ## Install the Lua test and lint tools with luarocks
	luarocks --lua-version=5.1 --local install busted 2.3.0-1
	luarocks --lua-version=5.1 --local install luacov 0.17.0-1
	luarocks --lua-version=5.1 --local install luacheck 1.2.0-1

lint: lint-lua fmt-check ## Run all linters

lint-lua: ## Run luacheck
	luacheck .

fmt-check: ## Check the Lua format
	stylua --check .

fmt: ## Format the Lua code
	stylua .

test: test-lua ## Run all tests

test-lua: ## Run the busted tests
	busted $(BUSTED_FLAGS)

coverage: coverage-lua ## Run tests with coverage thresholds

coverage-lua: ## Run busted with luacov
	rm -f luacov.stats.out luacov.report.out
	busted --coverage $(BUSTED_FLAGS)
	luacov
	@total=$$(awk '$$1 == "Total" { gsub("%", "", $$NF); print $$NF }' luacov.report.out); \
	echo "Lua coverage: $$total% (min $(LUA_COVERAGE_MIN)%)"; \
	awk -v t="$$total" -v m="$(LUA_COVERAGE_MIN)" 'BEGIN { exit (t + 0 < m + 0) }'

link: ## Link the addon into WOW_DIR (a flavor folder)
	@if [ -z "$${WOW_DIR:-}" ]; then echo "WOW_DIR is required, for example .../World of Warcraft/_retail_" >&2; exit 2; fi
	ln -sfn "$(CURDIR)" "$(WOW_DIR)/Interface/AddOns/Paparazzi"

clean: ## Remove build output
	rm -rf build .release luacov.*.out coverage.out
