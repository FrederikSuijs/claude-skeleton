# claude.mk — claude-skeleton make rules.
# Invoke with `make -f claude.mk <target>`, or include it from your own
# Makefile (e.g. `include claude.mk`) to add these targets as first-class.
#
# claude-skeleton — workspace setup
#
# Wraps RTK (Rust Token Killer) so a fresh checkout has a token-optimized
# shell on PATH, and wires the pre-commit secrets-scanning hooks so every
# commit (human or agent) is scanned before it lands.
#
# Usage:
#   make help           # list targets
#   make dev            # full workspace setup: rtk + skills + graphify + pre-commit + verify
#   make install        # install rtk binary only (idempotent)
#   make init           # inject RTK instructions into CLAUDE.md (idempotent)
#   make hooks          # install pre-commit framework + gitleaks + git hook
#   make hooks-baseline # generate gitleaks baseline for repos with history
#   make skills         # fetch skills from skills-lock.json into .claude/skills/
#   make skills-verify  # confirm in-tree skills match skills-lock.json
#   make graphify       # install the graphify CLI and register its skill
#   make lint           # run pre-commit against all files
#   make verify         # confirm rtk is on PATH and report version
#   make gain           # show token-savings dashboard
#   make path           # print the shell snippet to add ~/.local/bin to PATH
#   make clean          # remove the rtk binary

# ---- configuration ----------------------------------------------------------

# Override with: make install RTK_INSTALL_DIR=/usr/local/bin
RTK_INSTALL_DIR ?= $(HOME)/.local/bin
RTK_BIN         := $(RTK_INSTALL_DIR)/rtk
# 'latest' is resolved to the actual release tag at parse time. Override
# with: make install RTK_VERSION=v0.42.3  (or any tag from the GitHub API).
RTK_VERSION     ?= $(shell command -v curl >/dev/null 2>&1 && \
	curl -fsSL https://api.github.com/repos/rtk-ai/rtk/releases/latest 2>/dev/null | \
	awk -F'"' '/"tag_name":/ {print $$4; exit}' || echo latest)
# Gitleaks release tag. Resolved via GitHub API at parse time; override with
# 'make hooks GITLEAKS_VERSION=v8.30.1'. Strip the leading 'v' for the URL.
GITLEAKS_VERSION ?= $(shell command -v curl >/dev/null 2>&1 && \
	curl -fsSL https://api.github.com/repos/gitleaks/gitleaks/releases/latest 2>/dev/null | \
	awk -F'"' '/"tag_name":/ {print $$4; exit}' || echo v8.30.1)
# One of: claude-md (legacy), claude-code, cursor, global.
# Only the legacy '--claude-md' flag is supported by current rtk releases;
# the other targets are accepted as forward-compat no-ops.
RTK_INIT_TARGET ?= claude-md

# Detect OS for the install command (the upstream script handles arch itself).
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Linux)
  RTK_INSTALL_CMD := curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh
  SHA256_CMD      := sha256sum
else ifeq ($(UNAME_S),Darwin)
  RTK_INSTALL_CMD := curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh
  SHA256_CMD      := shasum -a 256
else ifeq ($(UNAME_S),Windows_NT)
  # Git-Bash / WSL on Windows. Adjust if you have a different shell.
  RTK_INSTALL_CMD := curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh
  SHA256_CMD      := sha256sum
else
  $(error Unsupported OS: $(UNAME_S). Install rtk manually: https://www.rtk-ai.app/)
endif

# Gitleaks release asset suffix. Maps 'uname -m' output to gitleaks's naming.
UNAME_M := $(shell uname -m)
ifeq ($(UNAME_S),Linux)
  GITLEAKS_OS := linux
else ifeq ($(UNAME_S),Darwin)
  GITLEAKS_OS := darwin
endif
ifeq ($(UNAME_M),x86_64)
  GITLEAKS_ARCH := x64
else ifeq ($(UNAME_M),aarch64)
  GITLEAKS_ARCH := arm64
else ifeq ($(UNAME_M),arm64)
  GITLEAKS_ARCH := arm64
else ifeq ($(UNAME_M),armv6l)
  GITLEAKS_ARCH := armv6
else ifeq ($(UNAME_M),armv7l)
  GITLEAKS_ARCH := armv7
endif
GITLEAKS_BIN := $(RTK_INSTALL_DIR)/gitleaks
GITLEAKS_ASSET := gitleaks_$(GITLEAKS_VERSION:v%=%)_$(GITLEAKS_OS)_$(GITLEAKS_ARCH).tar.gz

# Skills lockfile (manifest of upstream sources) and install directory.
SKILLS_LOCK := skills-lock.json
SKILLS_DIR  := .claude/skills

# ---- targets ----------------------------------------------------------------

.PHONY: help
help: ## Show this help
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.PHONY: dev
dev: install init hooks graphify skills-verify verify ## Full workspace setup: rtk, skills, graphify, pre-commit hooks, verify

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

.PHONY: hooks
hooks: ## Install pre-commit framework, install gitleaks if missing, register git hook
	@if ! command -v pre-commit >/dev/null 2>&1; then \
		echo "Installing pre-commit framework..."; \
		if command -v uv >/dev/null 2>&1; then \
			uv tool install pre-commit || { \
				echo "error: 'uv tool install pre-commit' failed." >&2; \
				exit 1; \
			}; \
		elif command -v pipx >/dev/null 2>&1; then \
			pipx install pre-commit || { \
				echo "error: 'pipx install pre-commit' failed." >&2; \
				exit 1; \
			}; \
		elif command -v pip3 >/dev/null 2>&1; then \
			pip3 install --user pre-commit || { \
				echo "error: 'pip3 install --user pre-commit' failed." >&2; \
				exit 1; \
			}; \
		else \
			echo "error: no Python package manager found." >&2; \
			echo "       Install one of: uv (https://docs.astral.sh/uv/), pipx, or pip3." >&2; \
			exit 1; \
		fi; \
	fi
	@if ! command -v pre-commit >/dev/null 2>&1; then \
		echo "error: pre-commit still not on PATH after install." >&2; \
		echo "       You may need a new shell for the 'uv tool' / 'pipx' PATH changes to take effect." >&2; \
		exit 1; \
	fi
	@if ! command -v gitleaks >/dev/null 2>&1; then \
		if [ -n "$(GITLEAKS_OS)" ] && [ -n "$(GITLEAKS_ARCH)" ]; then \
			echo "Installing gitleaks $(GITLEAKS_VERSION) to $(RTK_INSTALL_DIR)..."; \
			mkdir -p "$(RTK_INSTALL_DIR)"; \
			tmpdir=$$(mktemp -d); \
			trap 'rm -rf "$$tmpdir"' EXIT; \
			url="https://github.com/gitleaks/gitleaks/releases/download/$(GITLEAKS_VERSION)/$(GITLEAKS_ASSET)"; \
			if ! curl -fsSL -o "$$tmpdir/gitleaks.tgz" "$$url"; then \
				echo "error: failed to download $$url" >&2; \
				exit 1; \
			fi; \
			if ! tar -xzf "$$tmpdir/gitleaks.tgz" -C "$$tmpdir" gitleaks; then \
				echo "error: failed to extract gitleaks from $$tmpdir/gitleaks.tgz" >&2; \
				exit 1; \
			fi; \
			mv "$$tmpdir/gitleaks" "$(GITLEAKS_BIN)"; \
			chmod +x "$(GITLEAKS_BIN)"; \
			echo "gitleaks installed at $(GITLEAKS_BIN)"; \
		else \
			echo ""; \
			echo "warning: gitleaks not found and this platform (UNAME_S=$(UNAME_S), UNAME_M=$(UNAME_M)) is not auto-installable."; \
			echo "         The entropy layer of pre-commit will fail until it is installed."; \
			echo "         Install with: brew install gitleaks (macOS)"; \
			echo "         Or download:   https://github.com/gitleaks/gitleaks/releases"; \
			echo ""; \
		fi; \
	fi
	@if ! command -v gitleaks >/dev/null 2>&1 && [ ! -x "$(GITLEAKS_BIN)" ]; then \
		echo ""; \
		echo "warning: gitleaks still not on PATH."; \
		echo "         Add $(RTK_INSTALL_DIR) to PATH (or re-run 'make hooks' after PATH is fixed)."; \
		echo ""; \
	fi
	@echo "Installing pre-commit git hook..."
	@pre-commit install
	@echo ""
	@echo "Pre-commit hooks installed. To verify against the whole repo: make lint"

.PHONY: hooks-baseline
hooks-baseline: ## Generate a gitleaks baseline for repos with existing history
	@command -v gitleaks >/dev/null 2>&1 || { \
		echo "error: gitleaks not found." >&2; \
		echo "       Install with: brew install gitleaks" >&2; \
		exit 1; \
	}
	@if [ -f .gitleaks-baseline.json ]; then \
		echo "error: .gitleaks-baseline.json already exists. Delete it first to regenerate." >&2; \
		exit 1; \
	fi
	@echo "Generating gitleaks baseline from full history..."
	@gitleaks detect --baseline-path .gitleaks-baseline.json --redact
	@echo ""
	@echo "Baseline written to .gitleaks-baseline.json. Commit it."

.PHONY: skills
skills: ## Fetch skills from $(SKILLS_LOCK) into $(SKILLS_DIR) and update hashes
	@set -e; \
	command -v curl >/dev/null 2>&1 || { \
		echo "error: curl not found. Install curl or run 'make skills' on a machine that has it." >&2; \
		exit 1; \
	}; \
	command -v jq >/dev/null 2>&1 || { \
		echo "error: jq not found." >&2; \
		echo "       Install with: brew install jq (macOS) or apt install jq (Debian/Ubuntu)" >&2; \
		exit 1; \
	}; \
	if [ ! -f "$(SKILLS_LOCK)" ]; then \
		echo "no $(SKILLS_LOCK) found, nothing to do"; \
		exit 0; \
	fi; \
	version=$$(jq -r '.version' "$(SKILLS_LOCK)"); \
	if [ "$$version" != "1" ]; then \
		echo "error: unsupported $(SKILLS_LOCK) version: $$version (expected 1)" >&2; \
		exit 1; \
	fi; \
	tmpdir=$$(mktemp -d); \
	trap 'rm -rf "$$tmpdir"' EXIT; \
	jq -r '.skills | keys[]' "$(SKILLS_LOCK)" > "$$tmpdir/keys"; \
	while read -r name; do \
		source=$$(jq -r ".skills[\"$$name\"].source"     "$(SKILLS_LOCK)"); \
		skillpath=$$(jq -r ".skills[\"$$name\"].skillPath" "$(SKILLS_LOCK)"); \
		dest="$(SKILLS_DIR)/$$name/SKILL.md"; \
		mkdir -p "$(SKILLS_DIR)/$$name"; \
		url="https://raw.githubusercontent.com/$$source/main/$$skillpath"; \
		if ! curl -fsSL -o "$$dest.tmp" "$$url"; then \
			url="https://raw.githubusercontent.com/$$source/master/$$skillpath"; \
			if ! curl -fsSL -o "$$dest.tmp" "$$url"; then \
				echo "error: failed to fetch $$name from $$url" >&2; \
				rm -f "$$dest.tmp"; \
				exit 1; \
			fi; \
		fi; \
		mv "$$dest.tmp" "$$dest"; \
		hash=$$($(SHA256_CMD) "$$dest" | awk '{print $$1}'); \
		jq --arg n "$$name" --arg h "$$hash" '.skills[$$n].computedHash = $$h' "$(SKILLS_LOCK)" > "$$tmpdir/lock.tmp" && mv "$$tmpdir/lock.tmp" "$(SKILLS_LOCK)"; \
		printf '  %-15s fetched from %s (sha256:%s)\n' "$$name" "$$source" "$$hash"; \
	done < "$$tmpdir/keys"; \
	echo ""; \
	echo "Skills synced. Run 'make skills-verify' to confirm."

.PHONY: skills-verify
skills-verify: ## Confirm in-tree skills match the hashes in $(SKILLS_LOCK)
	@set -e; \
	command -v jq >/dev/null 2>&1 || { \
		echo "error: jq not found." >&2; \
		echo "       Install with: brew install jq (macOS) or apt install jq (Debian/Ubuntu)" >&2; \
		exit 1; \
	}; \
	if [ ! -f "$(SKILLS_LOCK)" ]; then \
		echo "no $(SKILLS_LOCK) found, nothing to verify"; \
		exit 0; \
	fi; \
	tmpdir=$$(mktemp -d); \
	trap 'rm -rf "$$tmpdir"' EXIT; \
	jq -r '.skills | keys[]' "$(SKILLS_LOCK)" > "$$tmpdir/keys"; \
	fail=0; \
	total=0; \
	while read -r name; do \
		expected=$$(jq -r ".skills[\"$$name\"].computedHash" "$(SKILLS_LOCK)"); \
		dest="$(SKILLS_DIR)/$$name/SKILL.md"; \
		total=$$((total + 1)); \
		if [ ! -f "$$dest" ]; then \
			echo "  $$name: SKILL.md MISSING (run 'make skills')"; \
			fail=$$((fail + 1)); \
			continue; \
		fi; \
		actual=$$($(SHA256_CMD) "$$dest" | awk '{print $$1}'); \
		if [ "$$expected" != "$$actual" ]; then \
			echo "  $$name: MISMATCH (expected $$expected, got $$actual)"; \
			fail=$$((fail + 1)); \
		else \
			echo "  $$name: OK"; \
		fi; \
	done < "$$tmpdir/keys"; \
	if [ "$$fail" -gt 0 ]; then \
		echo ""; \
		echo "drift detected: $$fail of $$total skills failed verification"; \
		exit 1; \
	fi; \
	echo "verified $$total skills ok"

.PHONY: graphify
graphify: ## Install the graphify CLI (PyPI: graphifyy) and register its skill
	@if command -v graphify >/dev/null 2>&1; then \
		echo "graphify already on PATH, skipping install"; \
	else \
		echo "Installing graphify CLI (PyPI package: graphifyy)..."; \
		if command -v uv >/dev/null 2>&1; then \
			uv tool install graphifyy || { \
				echo "error: 'uv tool install graphifyy' failed." >&2; \
				exit 1; \
			}; \
		elif command -v pipx >/dev/null 2>&1; then \
			pipx install graphifyy || { \
				echo "error: 'pipx install graphifyy' failed." >&2; \
				exit 1; \
			}; \
		elif command -v pip3 >/dev/null 2>&1; then \
			pip3 install --user graphifyy || { \
				echo "error: 'pip3 install --user graphifyy' failed." >&2; \
				exit 1; \
			}; \
		else \
			echo "error: no Python package manager found." >&2; \
			echo "       Install one of: uv (https://docs.astral.sh/uv/), pipx, or pip3." >&2; \
			exit 1; \
		fi; \
	fi
	@if ! command -v graphify >/dev/null 2>&1; then \
		echo "error: graphify still not on PATH after install." >&2; \
		echo "       You may need a new shell for the 'uv tool' / 'pipx' PATH changes to take effect." >&2; \
		exit 1; \
	fi
	@echo "Registering graphify skill into .claude/skills/..."
	@graphify install --project

.PHONY: lint
lint: ## Run pre-commit against all files in the repo
	@command -v pre-commit >/dev/null 2>&1 || { \
		echo "error: pre-commit not found. Run 'make hooks' first." >&2; \
		exit 1; \
	}
	@pre-commit run --all-files

.PHONY: verify
verify: ## Confirm rtk is on PATH and report version
	@if ! command -v rtk >/dev/null 2>&1; then \
		echo "error: rtk not found on PATH." >&2; \
		echo "       Add to your shell profile: export PATH=\"$(RTK_INSTALL_DIR):\$$PATH\"" >&2; \
		exit 1; \
	fi
	@echo "rtk: $$(command -v rtk)"
	@rtk --version

.PHONY: check
check: ## Diagnose the workspace (tools, files, hooks). Exits non-zero on any failure.
	@set +e; \
	fail=0; warn=0; pass=0; \
	report() { \
		if   [ "$$1" = OK   ]; then pass=$$((pass+1)); printf '  \033[32m[ OK ]\033[0m  %s\n'   "$$2"; \
		elif [ "$$1" = WARN ]; then warn=$$((warn+1)); printf '  \033[33m[WARN]\033[0m  %s\n' "$$2"; \
		elif [ "$$1" = FAIL ]; then fail=$$((fail+1)); printf '  \033[31m[FAIL]\033[0m  %s\n' "$$2"; \
		fi; \
	}; \
	echo "Tools on PATH:"; \
	command -v rtk        >/dev/null 2>&1 && report OK   "rtk"        || report FAIL "rtk (run 'make install')"; \
	command -v pre-commit >/dev/null 2>&1 && report OK   "pre-commit" || report FAIL "pre-commit (run 'make hooks')"; \
	command -v gitleaks   >/dev/null 2>&1 && report OK   "gitleaks"   || report WARN "gitleaks (entropy layer disabled until installed)"; \
	command -v graphify   >/dev/null 2>&1 && report OK   "graphify"   || report WARN "graphify (optional, run 'make graphify')"; \
	echo ""; \
	echo "Workspace files:"; \
	if [ -f CLAUDE.md ]; then \
		grep -q "RTK (Rust Token Killer)" CLAUDE.md 2>/dev/null \
			&& report OK   "CLAUDE.md present with RTK section" \
			|| report WARN "CLAUDE.md missing RTK section (run 'make init')"; \
	else \
		report FAIL "CLAUDE.md missing"; \
	fi; \
	[ -f .pre-commit-config.yaml ] && report OK ".pre-commit-config.yaml present" || report FAIL ".pre-commit-config.yaml missing (run 'make hooks')"; \
	[ -f skills-lock.json ]        && report OK "skills-lock.json present"        || report FAIL "skills-lock.json missing"; \
	[ -x .githooks/secrets-scanner.sh ] && report OK "secrets-scanner.sh executable" || report FAIL "secrets-scanner.sh missing or not executable (chmod +x .githooks/secrets-scanner.sh)"; \
	echo ""; \
	echo "Git hooks:"; \
	if [ -d .git ]; then \
		[ -x .git/hooks/pre-commit ] && report OK "pre-commit git hook installed" || report FAIL "pre-commit git hook not installed (run 'make hooks')"; \
	else \
		report WARN "not a git repo (skipped)"; \
	fi; \
	echo ""; \
	echo "Environment:"; \
	case ":$$PATH:" in *:$(RTK_INSTALL_DIR):*) report OK "~/.local/bin on PATH";; *) report WARN "~/.local/bin not on PATH (rtk/gitleaks may not be reachable)";; esac; \
	echo ""; \
	printf "  passed: %s, warnings: %s, failed: %s\n" "$$pass" "$$warn" "$$fail"; \
	if [ "$$fail" -gt 0 ]; then exit 1; fi

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
		echo "No rtk binary at $(RTK_INSTALL_DIR), nothing to remove"; \
	fi
