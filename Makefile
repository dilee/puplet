APP := build/Puplet.app
MSG ?= hi pup

.DEFAULT_GOAL := help

.PHONY: help build bundle run quit icon frames gif chat release clean

help:
	@echo "Puplet"
	@echo ""
	@echo "  make build      debug build"
	@echo "  make bundle     release build wrapped as $(APP)"
	@echo "  make run        bundle, then (re)launch the app"
	@echo "  make quit       quit the running app"
	@echo "  make icon       re-render Resources/AppIcon.icns"
	@echo "  make frames     render every animation pose to ./frames"
	@echo "  make gif        regenerate the README demo animation"
	@echo "  make chat       talk to the chat brains: make chat MSG=\"who are you?\""
	@echo "  make release    sign + notarize + package: make release VERSION=0.1.0"
	@echo "  make clean      remove build artifacts and rendered frames"

build:
	swift build

bundle:
	./scripts/bundle.sh release

run: bundle
	@osascript -e 'quit app "Puplet"' 2>/dev/null || true
	@sleep 1
	open $(APP)

quit:
	@osascript -e 'quit app "Puplet"' 2>/dev/null || true

icon:
	./scripts/icon.sh

frames:
	swift run Puplet --dump-frames ./frames

gif:
	swift run Puplet --dump-gif docs/demo.gif

chat:
	swift run Puplet --chat "$(MSG)"

release:
ifndef VERSION
	$(error VERSION is required, e.g. make release VERSION=0.1.0)
endif
	./scripts/release.sh $(VERSION)

clean:
	rm -rf .build build frames
