SHELL := bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help

LUA_COVERAGE_MIN ?= 80
GO_COVERAGE_MIN ?= 80
MAIN ?= main
REMOTE ?= origin
DRY_RUN ?=
BUSTED_FLAGS ?=

LR_PATH := $(shell luarocks --lua-version=5.1 --local path --lr-path 2>/dev/null)
LR_CPATH := $(shell luarocks --lua-version=5.1 --local path --lr-cpath 2>/dev/null)
export PATH := $(HOME)/.luarocks/bin:$(PATH)
export LUA_PATH := $(LR_PATH);$(LUA_PATH);;
export LUA_CPATH := $(LR_CPATH);$(LUA_CPATH);;

.PHONY: help check-tools deps lint lint-lua lint-go fmt-check fmt test test-lua test-go test-release coverage coverage-lua coverage-go build export link install clean

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

lint: lint-lua lint-go fmt-check ## Run all linters

lint-lua: ## Run luacheck
	luacheck .

lint-go: ## Run gofmt and go vet
	test -z "$$(gofmt -l .)"
	go vet ./...

fmt-check: ## Check the Lua format
	stylua --check .

fmt: ## Format the Lua and Go code
	stylua .
	gofmt -w .

test: test-lua test-go test-release ## Run all tests

test-lua: ## Run the busted tests
	busted $(BUSTED_FLAGS)

coverage: coverage-lua coverage-go ## Run tests with coverage thresholds

coverage-lua: ## Run busted with luacov
	rm -f luacov.stats.out luacov.report.out
	busted --coverage $(BUSTED_FLAGS)
	luacov
	@total=$$(awk '$$1 == "Total" { gsub("%", "", $$NF); print $$NF }' luacov.report.out); \
	echo "Lua coverage: $$total% (min $(LUA_COVERAGE_MIN)%)"; \
	awk -v t="$$total" -v m="$(LUA_COVERAGE_MIN)" 'BEGIN { exit (t + 0 < m + 0) }'

test-go: ## Run the Go tests with the race detector
	go test -race ./...

coverage-go: ## Run Go tests with the coverage threshold
	go test -coverprofile=coverage.out ./internal/...
	@total=$$(go tool cover -func=coverage.out | awk '$$1 == "total:" { gsub("%", "", $$NF); print $$NF }'); \
	echo "Go coverage: $$total% (min $(GO_COVERAGE_MIN)%)"; \
	awk -v t="$$total" -v m="$(GO_COVERAGE_MIN)" 'BEGIN { exit (t + 0 < m + 0) }'

build: ## Build the exporter into build/
	CGO_ENABLED=0 go build -o build/paparazzi-export ./cmd/paparazzi-export

export: ## Run the exporter on WOW_DIR (a flavor folder)
	@if [ -z "$${WOW_DIR:-}" ]; then echo "WOW_DIR is required, for example .../World of Warcraft/_retail_" >&2; exit 2; fi
	go run ./cmd/paparazzi-export --wow-dir "$(WOW_DIR)"

test-release: ## Test the release targets in a temporary repository
	bash scripts/test-release.sh

release-check: ## Check that the tree is ready for a release
	@if [ -n "$$(git status --porcelain)" ]; then echo "release: the working tree is dirty" >&2; exit 1; fi
	@branch=$$(git rev-parse --abbrev-ref HEAD); \
	if [ "$$branch" != "$(MAIN)" ]; then echo "release: the branch is $$branch, not $(MAIN)" >&2; exit 1; fi
	@git fetch --quiet --tags $(REMOTE) $(MAIN)
	@if [ "$$(git rev-parse HEAD)" != "$$(git rev-parse $(REMOTE)/$(MAIN))" ]; then \
		echo "release: HEAD differs from $(REMOTE)/$(MAIN)" >&2; exit 1; \
	fi

define bump
	@last=$$(git tag --list 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | grep -v -- '-' | head -n 1 || true); \
	last=$${last:-v0.0.0}; \
	IFS=. read -r major minor patch <<< "$${last#v}"; \
	case "$(1)" in \
		major) major=$$((major + 1)); minor=0; patch=0 ;; \
		minor) minor=$$((minor + 1)); patch=0 ;; \
		patch) patch=$$((patch + 1)) ;; \
	esac; \
	next="v$$major.$$minor.$$patch"; \
	echo "$$last -> $$next"; \
	if [ -n "$(DRY_RUN)" ]; then exit 0; fi; \
	git tag -a "$$next" -m "Release $$next"; \
	git push $(REMOTE) "$$next"
endef

release-patch: release-check ## Tag and push the next patch version
	$(call bump,patch)

release-minor: release-check ## Tag and push the next minor version
	$(call bump,minor)

release-major: release-check ## Tag and push the next major version
	$(call bump,major)

link: ## Link the addon into WOW_DIR (a flavor folder)
	@if [ -z "$${WOW_DIR:-}" ]; then echo "WOW_DIR is required, for example .../World of Warcraft/_retail_" >&2; exit 2; fi
	ln -sfn "$(CURDIR)" "$(WOW_DIR)/Interface/AddOns/Paparazzi"

install: ## Copy the addon files into WOW_DIR (a flavor folder)
	@if [ -z "$${WOW_DIR:-}" ]; then echo "WOW_DIR is required, for example .../World of Warcraft/_retail_" >&2; exit 2; fi
	@if [ ! -d "$(WOW_DIR)/Interface/AddOns" ]; then echo "install: $(WOW_DIR)/Interface/AddOns does not exist" >&2; exit 1; fi
	rm -rf "$(WOW_DIR)/Interface/AddOns/Paparazzi"
	mkdir -p "$(WOW_DIR)/Interface/AddOns/Paparazzi"
	cp -R Paparazzi.toc src assets "$(WOW_DIR)/Interface/AddOns/Paparazzi/"

clean: ## Remove build output
	rm -rf build .release luacov.*.out coverage.out
