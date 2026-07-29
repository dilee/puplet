APP := build/Puplet.app
MSG ?= hi pup

.DEFAULT_GOAL := help

.PHONY: help build bundle run quit frames chat clean

help:
	@echo "Puplet"
	@echo ""
	@echo "  make build      debug build"
	@echo "  make bundle     release build wrapped as $(APP)"
	@echo "  make run        bundle, then (re)launch the app"
	@echo "  make quit       quit the running app"
	@echo "  make frames     render every animation pose to ./frames"
	@echo "  make chat       talk to the chat brains: make chat MSG=\"who are you?\""
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

frames:
	swift run Puplet --dump-frames ./frames

chat:
	swift run Puplet --chat "$(MSG)"

clean:
	rm -rf .build build frames
