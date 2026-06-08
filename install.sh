#!/usr/bin/env bash
# install.sh — one-liner installer for the claude-skeleton template.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/FrederikSuijs/claude-skeleton/main/install.sh | sh
#   curl -fsSL ... | sh -s -- check
#   curl -fsSL ... | sh -s -- setup --no-tools
#   curl -fsSL ... | sh -s -- --help
#
# Subcommands:
#   setup   (default) Fetch the template files into the current directory and
#                     run `make -f claude.mk dev` (or `init skills-verify` with
#                     `--no-tools`).
#   check             Fetch `claude.mk` (no-clobber) and run
#                     `make -f claude.mk check`.
#
# Flags:
#   --force           Overwrite existing template files (default: skip with
#                     a "kept existing" message).
#   --no-tools        Skip the system tool install (rtk / pre-commit /
#                     gitleaks / graphify). Only drops files and runs
#                     `make -f claude.mk init skills-verify`.
#   --dry-run         Print every action; make no changes.
#   --ref <ref>       Override the ref to fetch (default: main).
#   -h, --help        Show this help.
#
# Environment overrides:
#   CLAUDE_SKELETON_REPO   (default: frederik/claude-skeleton)
#   CLAUDE_SKELETON_REF    (default: main)
#   CLAUDE_SKELETON_TARBALL  Override the tarball URL entirely (useful for
#                            local testing or private mirrors).
#
# Notes:
#   - Idempotent. Re-running on an already-set-up project is a no-op.
#   - The Makefile content is always dropped as `claude.mk` (never as
#     `Makefile`) to avoid clobbering a user's existing Makefile. A 1-line
#     `Makefile` stub (`include claude.mk`) is also dropped — skipped
#     automatically if `Makefile` already exists.
#   - Targets macOS and Linux. Windows is not supported.

set -euo pipefail

REPO="${CLAUDE_SKELETON_REPO:-frederik/claude-skeleton}"
REF="${CLAUDE_SKELETON_REF:-main}"
TARBALL_URL="${CLAUDE_SKELETON_TARBALL:-https://github.com/${REPO}/archive/${REF}.tar.gz}"

# Defaults
SUBCOMMAND="setup"
FORCE=0
NO_TOOLS=0
DRY_RUN=0

# Allowlist of paths to drop into cwd. `claude.mk` and `Makefile` are
# handled separately below.
ENTRIES=(
  CLAUDE.md
  .pre-commit-config.yaml
  .pre-commit-hooks.yaml
  skills-lock.json
  .env.example
  .gitignore
  .claude
  .githooks
  tasks
  .mcp
)

# ---- helpers ----------------------------------------------------------------

log()  { printf '%s\n' "$*"; }
warn() { log "  warn:  $*" >&2; }
err()  { log "  error: $*" >&2; }
die()  { err "$@"; exit 1; }

usage() {
  sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//' | sed '$d'
}

# Print intended action: skip / drop / over (overwrite).
# Args: $1=src-path  $2=dst-path  $3=label
plan_or_copy() {
  local src="$1" dst="$2" label="$3"
  if [ "$DRY_RUN" -eq 1 ]; then
    if [ -e "$dst" ] && [ "$FORCE" -ne 1 ]; then
      log "    keep $label (exists; --force to overwrite)"
    else
      log "    drop $label"
    fi
    return
  fi
  if [ -e "$dst" ] && [ "$FORCE" -ne 1 ]; then
    log "    keep $label (exists; --force to overwrite)"
  else
    cp "$src" "$dst"
    log "    drop $label"
  fi
}

plan_or_copy_dir() {
  local src="$1" dst="$2" label="$3"
  if [ "$DRY_RUN" -eq 1 ]; then
    if [ -e "$dst" ] && [ "$FORCE" -ne 1 ]; then
      log "    keep $label/ (exists; --force to overwrite)"
    else
      log "    drop $label/"
    fi
    return
  fi
  if [ -e "$dst" ] && [ "$FORCE" -ne 1 ]; then
    log "    keep $label/ (exists; --force to overwrite)"
  else
    cp -R "$src" "$dst"
    log "    drop $label/"
  fi
}

# ---- arg parsing -----------------------------------------------------------

while [ $# -gt 0 ]; do
  case "$1" in
    setup|check)   SUBCOMMAND="$1" ;;
    --force)       FORCE=1 ;;
    --no-tools)    NO_TOOLS=1 ;;
    --dry-run)     DRY_RUN=1 ;;
    --ref)         [ $# -ge 2 ] || die "--ref requires an argument"; REF="$2"; shift ;;
    --ref=*)       REF="${1#--ref=}" ;;
    -h|--help)     usage; exit 0 ;;
    --)            shift; break ;;
    -*)            err "unknown flag: $1 (use --help)"; exit 2 ;;
    *)             err "unknown argument: $1 (use --help)"; exit 2 ;;
  esac
  shift
done

# Refresh the tarball URL if --ref changed it and the user didn't override it
# via CLAUDE_SKELETON_TARBALL.
if [ -z "${CLAUDE_SKELETON_TARBALL:-}" ]; then
  TARBALL_URL="https://github.com/${REPO}/archive/${REF}.tar.gz"
fi

# ---- preflight -------------------------------------------------------------

command -v curl >/dev/null 2>&1 || die "curl is required but not installed"
command -v tar  >/dev/null 2>&1 || die "tar is required but not installed"
if [ "$SUBCOMMAND" = "setup" ]; then
  command -v make >/dev/null 2>&1 || die "make is required for 'setup' but not installed"
fi

# ---- main ------------------------------------------------------------------

log "claude-skeleton installer  (${REPO}@${REF})"
log "  subcommand : ${SUBCOMMAND}"
[ "$FORCE"    -eq 1 ] && log "  --force    : overwrite existing files"
[ "$NO_TOOLS" -eq 1 ] && log "  --no-tools : skip system tool install"
[ "$DRY_RUN"  -eq 1 ] && log "  --dry-run  : no changes will be made"
log ""

# Fetch + extract the tarball
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

if [ "$DRY_RUN" -eq 1 ]; then
  log "  fetch: (dry-run, skipping download of ${TARBALL_URL})"
  SRC=""
else
  log "  fetch: ${TARBALL_URL}"
  if ! curl -fsSL -o "$TMPDIR/repo.tgz" "$TARBALL_URL"; then
    die "failed to download ${TARBALL_URL}"
  fi
  if ! tar -xzf "$TMPDIR/repo.tgz" -C "$TMPDIR" 2>/dev/null; then
    die "failed to extract tarball"
  fi
  # Find the source root: a top-level directory containing `claude.mk` (the
  # marker file). Handles GitHub-style tarballs (<repo>-<ref>/), tag-based
  # archives (claude-skeleton-v0.4.0/), and flat tarballs (no top dir).
  SRC=""
  for d in "$TMPDIR"/*/; do
    [ -d "$d" ] || continue
    if [ -f "$d/claude.mk" ]; then
      SRC="${d%/}"
      break
    fi
  done
  if [ -z "$SRC" ] && [ -f "$TMPDIR/claude.mk" ]; then
    SRC="$TMPDIR"
  fi
  [ -n "$SRC" ] || die "could not locate extracted source directory (no claude.mk found)"
  log "  extracted: $SRC"
fi

log ""
log "  drop:"

# In `check` mode, only ensure `claude.mk` is present (no-clobber). The bulk
# of the template is irrelevant to running diagnostics.
if [ "$SUBCOMMAND" = "check" ]; then
  if [ "$DRY_RUN" -eq 1 ]; then
    if [ -e "./claude.mk" ] && [ "$FORCE" -ne 1 ]; then
      log "    keep claude.mk (exists)"
    else
      log "    drop claude.mk"
    fi
  else
    if [ -e "$SRC/claude.mk" ]; then
      plan_or_copy "$SRC/claude.mk" "./claude.mk" "claude.mk"
    else
      warn "claude.mk not in template (skipped)"
    fi
  fi
else
  # `setup` mode — drop the full template allowlist.
  for entry in "${ENTRIES[@]}"; do
    if [ "$DRY_RUN" -eq 1 ]; then
      if [ -e "$entry" ] && [ "$FORCE" -ne 1 ]; then
        log "    keep $entry (exists; --force to overwrite)"
      else
        log "    drop $entry"
      fi
    else
      if [ ! -e "$SRC/$entry" ]; then
        warn "$entry not in template (skipped)"
        continue
      fi
      if [ -d "$SRC/$entry" ]; then
        plan_or_copy_dir "$SRC/$entry" "./$entry" "$entry"
      else
        plan_or_copy "$SRC/$entry" "./$entry" "$entry"
      fi
    fi
  done

  # Drop `claude.mk` (the source of truth for make rules)
  if [ "$DRY_RUN" -eq 1 ]; then
    [ -e "./claude.mk" ] && [ "$FORCE" -ne 1 ] \
      && log "    keep claude.mk (exists; --force to overwrite)" \
      || log "    drop claude.mk"
  else
    if [ -e "$SRC/claude.mk" ]; then
      plan_or_copy "$SRC/claude.mk" "./claude.mk" "claude.mk"
    else
      warn "claude.mk not in template (skipped)"
    fi
  fi

  # Drop the `Makefile` stub (`include claude.mk`) — skip if user has one
  if [ "$DRY_RUN" -eq 1 ]; then
    if [ -e "./Makefile" ] && [ "$FORCE" -ne 1 ]; then
      log "    keep claude.mk only — existing Makefile preserved (invoke with 'make -f claude.mk dev')"
    else
      log "    drop Makefile stub (include claude.mk)"
    fi
  else
    if [ -e "$SRC/Makefile" ]; then
      if [ -e "./Makefile" ] && [ "$FORCE" -ne 1 ]; then
        log "    keep claude.mk only — existing Makefile preserved (invoke with 'make -f claude.mk dev')"
      else
        plan_or_copy "$SRC/Makefile" "./Makefile" "Makefile stub (include claude.mk)"
      fi
    fi
  fi
fi

log ""

# ---- delegate to claude.mk -------------------------------------------------

if [ "$DRY_RUN" -eq 1 ]; then
  if [ "$SUBCOMMAND" = "setup" ]; then
    if [ "$NO_TOOLS" -eq 1 ]; then
      log "  would run: make -f claude.mk init skills-verify"
    else
      log "  would run: make -f claude.mk dev"
    fi
  else
    log "  would run: make -f claude.mk check"
  fi
  log ""
  log "  (dry-run, exiting)"
  exit 0
fi

# Real run — delegate to claude.mk
if [ ! -e "./claude.mk" ]; then
  die "claude.mk was not dropped; cannot continue. Check the fetch step above for errors."
fi

case "$SUBCOMMAND" in
  setup)
    if [ "$NO_TOOLS" -eq 1 ]; then
      log "  run: make -f claude.mk init skills-verify"
      log ""
      make -f claude.mk init skills-verify
    else
      log "  run: make -f claude.mk dev"
      log ""
      make -f claude.mk dev
    fi
    ;;
  check)
    log "  run: make -f claude.mk check"
    log ""
    make -f claude.mk check
    ;;
esac
