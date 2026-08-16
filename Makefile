SHELL := /bin/sh
.DEFAULT_GOAL := help

APP := Vimshot.app
INSTALL_DIR ?= $(HOME)/Applications

.PHONY: help build release app stop run dev install clean

help: ## Show available commands
	@printf '%s\n' 'Vimshot development commands:'
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z_-]+:.*## / {printf "  %-10s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

build: ## Build a debug executable
	swift build

release: ## Build an optimized executable
	swift build -c release

app: ## Build and sign Vimshot.app
	./build-app.sh

stop: ## Stop every running Vimshot instance
	@pkill -x vimshot 2>/dev/null || true
	@sleep 1

dev: stop ## Stop stale instances and run the debug executable
	swift run vimshot

run: app ## Build, stop stale instances, and open this exact app bundle
	@$(MAKE) --no-print-directory stop
	open "$(CURDIR)/$(APP)"

install: app ## Replace the app in INSTALL_DIR (default: ~/Applications)
	@$(MAKE) --no-print-directory stop
	@mkdir -p "$(INSTALL_DIR)"
	@rm -rf "$(INSTALL_DIR)/$(APP)"
	@cp -R "$(APP)" "$(INSTALL_DIR)/$(APP)"
	@printf 'Installed %s\n' "$(INSTALL_DIR)/$(APP)"

clean: stop ## Stop Vimshot and remove generated build output
	swift package clean
	rm -rf "$(APP)"
