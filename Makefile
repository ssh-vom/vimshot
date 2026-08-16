SHELL := /bin/sh
.DEFAULT_GOAL := help

APP := Vimshot.app
INSTALL_DIR ?= $(HOME)/Applications

.PHONY: help build release app run dev install clean

help: ## Show available commands
	@printf '%s\n' 'Vimshot development commands:'
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z_-]+:.*## / {printf "  %-10s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

build: ## Build a debug executable
	swift build

release: ## Build an optimized executable
	swift build -c release

app: ## Build and sign Vimshot.app
	./build-app.sh

dev: ## Run the debug executable directly
	swift run vimshot

run: app ## Build and open the menu-bar app
	open "$(APP)"

install: app ## Install the app (default: ~/Applications)
	@mkdir -p "$(INSTALL_DIR)"
	@rm -rf "$(INSTALL_DIR)/$(APP)"
	@cp -R "$(APP)" "$(INSTALL_DIR)/$(APP)"
	@printf 'Installed %s\n' "$(INSTALL_DIR)/$(APP)"

clean: ## Remove Swift build output and the app bundle
	swift package clean
	rm -rf "$(APP)"
