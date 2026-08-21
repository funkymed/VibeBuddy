SHELL=/bin/bash

.DEFAULT_GOAL := help
.SILENT:

APP        := VibeBuddy
DEBUG_BIN  := .build/debug/$(APP)
RELEASE_BIN:= .build/release/$(APP)
BUNDLE     := dist/$(APP).app
BUNDLE_BIN := $(BUNDLE)/Contents/MacOS/$(APP)
# One source of truth for the version: the source file the app itself reads.
VERSION    := $(shell grep -m1 'static let number' Sources/VibeBuddy/AppVersion.swift | sed 's/.*"\(.*\)".*/\1/')
REPO       := funkymed/VibeBuddy
TAP        := funkymed/homebrew-vibebuddy
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

# The tap is its own repository — github.com/funkymed/homebrew-vibebuddy.
# This writes the file; pushing it is a separate decision, because releasing a
# version and pointing the tap at it are two acts, and doing them as one is how
# a tap ends up naming a DMG nobody uploaded.
## Write the Homebrew cask for the current version (needs `make dmg` first)
cask:
	$(call title,"Cask…")
	./scripts/make-cask.sh Casks/vibebuddy.rb
	echo "  copie-le dans le tap : github.com/funkymed/homebrew-vibebuddy"
.PHONY: cask

# `version=` is a **guard**, not an input: the version lives in
# AppVersion.swift, and passing it here only asserts that you know which one
# you are shipping. Bump the file first, with `make bump version=0.2.0`.
#
# The checks before the upload are the point. A release built from a dirty tree
# cannot be reproduced from the tag it claims to be, and an unsigned DMG
# installs an app whose identity changes on the next build — which revokes
# every permission macOS had granted it.
## Build, sign, package and publish a release — make publish version=0.1.0
publish:
	$(call title,"Publication $(VERSION)…")
	if [ -n "$(version)" ] && [ "$(version)" != "$(VERSION)" ]; then \
		printf "${RED}  version demandée $(version), source à $(VERSION)${NC}\n"; \
		printf "  bump d'abord : make bump version=$(version)\n"; exit 1; \
	fi
	command -v gh >/dev/null || { printf "${RED}  gh absent${NC}\n"; exit 1; }
	gh auth status >/dev/null 2>&1 || { printf "${RED}  gh non authentifié${NC}\n"; exit 1; }
	test -z "$$(git status --porcelain)" || { printf "${RED}  arbre de travail sale — une release doit être reproductible depuis son tag${NC}\n"; exit 1; }
	! git rev-parse "v$(VERSION)" >/dev/null 2>&1 || { printf "${RED}  le tag v$(VERSION) existe déjà${NC}\n"; exit 1; }
	$(MAKE) dmg
	codesign --verify --strict --deep $(BUNDLE) || { printf "${RED}  bundle non signé — refus de publier${NC}\n"; exit 1; }
	$(MAKE) cask
	git tag -a "v$(VERSION)" -m "VibeBuddy $(VERSION)"
	git push origin "v$(VERSION)"
	gh release create "v$(VERSION)" "dist/$(APP)-$(VERSION).dmg" \
		--repo $(REPO) --title "$(APP) $(VERSION)" --generate-notes
	printf "${GREEN}  publié${NC} — copie Casks/vibebuddy.rb dans $(TAP)\n"
.PHONY: publish

## Set the version — make bump version=0.2.0
bump:
	test -n "$(version)" || { printf "${RED}  usage : make bump version=0.2.0${NC}\n"; exit 1; }
	sed -i '' 's/static let number = "[^"]*"/static let number = "$(version)"/' Sources/VibeBuddy/AppVersion.swift
	printf "${GREEN}  version → $(version)${NC}\n"
.PHONY: bump

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
