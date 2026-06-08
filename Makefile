# claude-skeleton — workspace setup
#
# Wraps RTK (Rust Token Killer) so a fresh checkout has a token-optimized
# shell on PATH and a PreToolUse hook that rewrites Claude Code's Bash calls.
#
# Usage:
#   make help     # list targets
#   make dev      # full workspace setup: install + PATH check + init hook
#   make install  # install rtk binary only (idempotent)
#   make init     # register PreToolUse hook in .claude/settings.json
#   make verify   # confirm rtk is on PATH and report version
#   make gain     # show token-savings dashboard
#   make path     # print the shell snippet to add ~/.local/bin to PATH
#   make clean    # remove the rtk binary

# ---- configuration ----------------------------------------------------------

# Override with: make install RTK_INSTALL_DIR=/usr/local/bin
RTK_INSTALL_DIR ?= $(HOME)/.local/bin
RTK_BIN         := $(RTK_INSTALL_DIR)/rtk
RTK_VERSION     ?= latest
# One of: claude-md (legacy), claude-code, cursor, global.
# Only the legacy '--claude-md' flag is supported by current rtk releases;
# the other targets are accepted as forward-compat no-ops.
RTK_INIT_TARGET ?= claude-md

# Detect OS for the install command (the upstream script handles arch itself).
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Linux)
  RTK_INSTALL_CMD := curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh
else ifeq ($(UNAME_S),Darwin)
  RTK_INSTALL_CMD := curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh
else ifeq ($(UNAME_S),Windows_NT)
  # Git-Bash / WSL on Windows. Adjust if you have a different shell.
  RTK_INSTALL_CMD := curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh
else
  $(error Unsupported OS: $(UNAME_S). Install rtk manually: https://www.rtk-ai.app/)
endif

# ---- targets ----------------------------------------------------------------

.PHONY: help
help: ## Show this help
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.PHONY: dev
dev: install init verify ## Full workspace setup: install rtk, wire init hook, verify

.PHONY: install
install: ## Install rtk to $(RTK_INSTALL_DIR) (idempotent)
	@if [ -x "$(RTK_BIN)" ]; then \
		echo "rtk already installed at $(RTK_BIN), skipping"; \
	else \
		echo "Installing rtk to $(RTK_INSTALL_DIR)..."; \
		RTK_VERSION='$(RTK_VERSION)' RTK_INSTALL_DIR='$(RTK_INSTALL_DIR)' sh -c "$(RTK_INSTALL_CMD)"; \
	fi
	@$(MAKE) --no-print-directory path-check

.PHONY: init
init: ## Inject RTK instructions into CLAUDE.md (idempotent)
	@if [ ! -x "$(RTK_BIN)" ]; then \
		echo "error: rtk not installed. Run 'make install' first." >&2; \
		exit 1; \
	fi
	@case '$(RTK_INIT_TARGET)' in \
		claude-md) ;; \
		claude-code|cursor|global) \
			echo "note: '$(RTK_INIT_TARGET)' is a forward-compat alias; the installed rtk only supports 'claude-md'."; \
			echo "      The Claude Code PreToolUse hook is configured separately by Claude Code itself."; \
			exit 0 ;; \
		*) echo "error: RTK_INIT_TARGET must be one of: claude-md, claude-code, cursor, global (got '$(RTK_INIT_TARGET)')" >&2; exit 1 ;; \
	esac
	@echo "Running rtk init --$(RTK_INIT_TARGET)..."
	@$(RTK_BIN) init --$(RTK_INIT_TARGET)

.PHONY: verify
verify: ## Confirm rtk is on PATH and report version
	@if ! command -v rtk >/dev/null 2>&1; then \
		echo "error: rtk not found on PATH." >&2; \
		echo "       Add to your shell profile: export PATH=\"$(RTK_INSTALL_DIR):\$$PATH\"" >&2; \
		exit 1; \
	fi
	@echo "rtk: $$(command -v rtk)"
	@rtk --version

.PHONY: path
path: ## Print the export snippet to add rtk to PATH
	@echo "Add this to your ~/.bashrc, ~/.zshrc, or equivalent:"
	@echo ""
	@echo "  export PATH=\"$(RTK_INSTALL_DIR):\$$PATH\""
	@echo ""

.PHONY: path-check
path-check:
	@case ":$$PATH:" in \
		*:$(RTK_INSTALL_DIR):*) ;; \
		*) echo ""; \
		   echo "warning: $(RTK_INSTALL_DIR) is not on PATH."; \
		   echo "         Add it now with: export PATH=\"$(RTK_INSTALL_DIR):\$$PATH\""; \
		   echo "         Or run 'make path' to see the snippet."; \
		   echo "" ;; \
	esac

.PHONY: gain
gain: ## Show token-savings dashboard
	@if ! command -v rtk >/dev/null 2>&1; then \
		echo "error: rtk not installed. Run 'make install' first." >&2; \
		exit 1; \
	fi
	@rtk gain

.PHONY: clean
clean: ## Remove the rtk binary from $(RTK_INSTALL_DIR)
	@if [ -x "$(RTK_BIN)" ]; then \
		echo "Removing $(RTK_BIN)"; \
		rm -f "$(RTK_BIN)"; \
	else \
		echo "No rtk binary at $(RTK_BIN), nothing to remove"; \
	fi
