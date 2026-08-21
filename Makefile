SHELL=/bin/bash

.DEFAULT_GOAL := help
.SILENT:

APP        := VibeBuddy
DEBUG_BIN  := .build/debug/$(APP)
RELEASE_BIN:= .build/release/$(APP)
BUNDLE     := dist/$(APP).app
BUNDLE_BIN := $(BUNDLE)/Contents/MacOS/$(APP)
# Where an icon preview lands. Never in the repo: the icon is drawn by a
# script, and dist/ is ignored — see scripts/generate-icon.swift.
ICON_OUT   := /tmp/vibebuddy-icon

BIYellow = \033[1;93m
WHITE=\033[1;37m
GREEN=\033[0;32m
CYAN=\033[0;36m
RED=\033[0;31m
NC = \033[0m

define title
	@echo ""
	@printf "${BIYellow}▸ %s${NC}\n" $(1)
endef

## Display this help dialog
help:
	echo ""
	printf "${BIYellow}  VibeBuddy${NC} — la notch en tableau de bord des agents de code\n"
	awk '/^[a-zA-Z\-\_0-9]+:/ { \
		separator = match(lastLine, /^## --/); \
		if (separator) { \
			helpCommand = substr($$1, 0, index($$1, ":")-1); \
			printf "\n${BIYellow}= %s =${NC}\n", helpCommand; \
			lastLine = $$0; next; \
		} \
		helpMessage = match(lastLine, /^## (.*)/); \
		if (helpMessage) { \
			helpCommand = substr($$1, 0, index($$1, ":")); \
			helpMessage = substr(lastLine, RSTART + 3, RLENGTH); \
			printf "${GREEN}%-22s${NC} %s\n", helpCommand, helpMessage; \
		} \
	} \
	{ lastLine = $$0 }' $(MAKEFILE_LIST)
	echo ""
.PHONY: help

## -- Build
Build:

## Compile in debug
build:
	$(call title,"Compilation (debug)…")
	swift build
.PHONY: build

## Compile in release
build-release:
	$(call title,"Compilation (release)…")
	swift build -c release
.PHONY: build-release

## Build the signed .app bundle (universal, icon, signature)
app:
	$(call title,"Bundle signé…")
	./scripts/build.sh
.PHONY: app

## Build the DMG from the bundle
dmg: app
	$(call title,"DMG…")
	./scripts/make-dmg.sh
.PHONY: dmg

## Remove build products
clean:
	$(call title,"Nettoyage…")
	rm -rf .build dist
.PHONY: clean

## -- Run
Run:

## Run the debug build (Ctrl-C to stop)
run: build
	$(call title,"$(DEBUG_BIN)")
	$(DEBUG_BIN)
.PHONY: run

## Run the release build (Ctrl-C to stop)
run-release: build-release
	$(call title,"$(RELEASE_BIN)")
	$(RELEASE_BIN)
.PHONY: run-release

## Run the signed bundle
run-app: app
	$(call title,"$(BUNDLE)")
	open $(BUNDLE)
.PHONY: run-app

# Two instances fight over ~/.vibebuddy/buddy.sock: the second unlinks it and
# binds its own, so the first listens on a dead inode while still showing its
# pill. Silent, and thoroughly confusing.
## Stop every running instance
stop:
	$(call title,"Arrêt des instances…")
	pkill -f '$(APP)$$' 2>/dev/null || true
	rm -f "$$HOME/.vibebuddy/buddy.sock"
	echo "  instances restantes : $$(pgrep -fc '$(APP)$$' 2>/dev/null || echo 0)"
.PHONY: stop

## Full diagnostic: screens, geometry, buddy, sessions, usage, login item
info: build-release
	$(RELEASE_BIN) --info
.PHONY: info

## Show a fake permission panel — kind=shell|diff|write|read|url|question|other
simulate: build-release
	$(call title,"Permission simulée : $(or $(kind),shell)")
	$(RELEASE_BIN) --simulate-permission $(or $(kind),shell)
.PHONY: simulate

## -- Quality
Quality:

## Run the whole test suite
test:
	$(call title,"Tests…")
	swift test
.PHONY: test

## Run one suite or test — filter=PermissionQueue
test-filter:
	$(call title,"Tests filtrés : $(filter)")
	swift test --filter '$(filter)'
.PHONY: test-filter

## Fail on any compiler warning
lint:
	$(call title,"Avertissements…")
	swift build 2>&1 | grep -E 'warning:' && { printf "${RED}  des avertissements subsistent${NC}\n"; exit 1; } || printf "${GREEN}  aucun avertissement${NC}\n"
.PHONY: lint

## -- Performance
Performance:

# The governing metric is idle wakeups, not CPU percent: a process at 0,4 %
# with 70 wakeups a second drains a battery and trips no threshold.
#
# Run it in the foreground. Launched detached (nohup … &) the process gets
# reaped and the run stops early — 149 s, 40 s and 265 s were measured that
# way on 2026-08-21, with contradictory verdicts.
## Scenario A — at rest, 10 min. The gate every RFC must pass.
perf: build-release
	./scripts/perfcheck.sh A $(or $(seconds),600) $(or $(rfc),001)
.PHONY: perf

## Scenario B — three live sessions, 5 min
perf-busy: build-release
	./scripts/perfcheck.sh B $(or $(seconds),300) $(or $(rfc),001)
.PHONY: perf-busy

## Scenario C — panel open, cursor moving, 90 s
perf-panel: build-release
	./scripts/perfcheck.sh C $(or $(seconds),90) $(or $(rfc),001)
.PHONY: perf-panel

## -- Icon
Icon:

## Draw the ten sizes and open them — nothing is stored in the repo
icon:
	$(call title,"Icône…")
	rm -rf $(ICON_OUT)
	swift scripts/generate-icon.swift $(ICON_OUT)
	open $(ICON_OUT)
.PHONY: icon

## -- Hook
Hook:

# Pass settings=<path> to aim at a copy instead of the real file. Needed
# because NSHomeDirectory() ignores $HOME: without it there is no way to
# rehearse this anywhere but the user's own settings.
## Register vibe-hook in settings.json — shows the diff and asks
install-hook: build-release
	$(RELEASE_BIN) --install-hook $(if $(settings),--settings $(settings),)
.PHONY: install-hook

## Remove our entries — a diff against the backup must show exactly ours
uninstall-hook: build-release
	$(RELEASE_BIN) --uninstall-hook $(if $(settings),--settings $(settings),)
.PHONY: uninstall-hook
