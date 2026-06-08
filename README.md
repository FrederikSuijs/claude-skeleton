# claude-skeleton

Opinionated starter template for LLM-assisted projects. Pre-configured `CLAUDE.md` with scoped context, lean token hygiene, RTK (Rust Token Killer) wired through Make, a two-layer secrets-scanning pre-commit setup, MCP server stubs, agent task scaffolding, and an `.env.example` for safe local config. Drop in, vibe code. Stop re-solving the same Claude setup every project.

## What's inside

| Path | Purpose |
|------|---------|
| `CLAUDE.md` | Behavioral guidelines for Claude (think first, simplify, surgical changes, goal-driven) plus the RTK (Rust Token Killer) command reference. |
| `.claude/` | Project-local Claude Code configuration (settings, skills). |
| `.claude/skills/` | Pinned skills (`caveman`, `find-skills`), fetched from upstream on `make dev` and verified against `skills-lock.json`. Plus `graphify/` (installed by `make graphify`). |
| `.rtk/` | RTK state directory + a starter `filters.toml` for project-local overrides. |
| `skills-lock.json` | Lockfile of skill sources, treated like `package.json`: `make skills` fetches, `make skills-verify` checks. |
| `.mcp/` | Stub MCP servers. `example-server/` is a runnable Python reference; copy it to add real servers. |
| `tasks/` | Agent task scaffolding. `TEMPLATE.md` is the spec format; copy it to author a new task. |
| `.pre-commit-config.yaml` | Two-layer secrets scan: pattern-based `secrets-scanner` + `gitleaks` (entropy/context). |
| `.githooks/secrets-scanner.sh` | Local pattern scanner, vendored from `github/awesome-copilot`. |
| `.env.example` | Template for local secrets — copy to `.env` (gitignored) and fill in real values. |
| `.gitignore` | General-purpose ignores covering Python, Node, Go, Rust, JVM, .NET, C/C++, Ruby, PHP, Docker, Terraform, and common editors/OSes. |
| `claude.mk` | Workspace setup — installs RTK, fetches skills, installs graphify, installs pre-commit hooks, and verifies the toolchain. Targets: `make dev`, `make skills`, `make skills-verify`, `make graphify`, `make check`. |
| `Makefile` | 1-line stub: `include claude.mk`. Lets `make dev` work without `-f`. If you already have a `Makefile`, the one-liner installs only `claude.mk` and you invoke it as `make -f claude.mk dev` (or include it from your own `Makefile`). |
| `install.sh` | One-liner installer — fetches the template into the current directory and runs `make -f claude.mk dev`. See [One-liner install](#one-liner-install). |

## Quick start

If you cloned the repo:

```bash
make dev        # install rtk, fetch skills, install graphify, install pre-commit hooks, verify
```

That target is idempotent — re-run it any time and it skips steps that are already done.

If you only want one piece:

```bash
make install    # install rtk binary
make init       # inject RTK instructions into CLAUDE.md
make hooks      # install pre-commit framework, install gitleaks if missing, git hook install
make skills     # fetch skills from skills-lock.json into .claude/skills/
make graphify   # install the graphify CLI and register its skill
make verify     # confirm rtk is on PATH and print its version
make gain       # token-savings dashboard
make lint       # run pre-commit against the whole repo
make check      # diagnose the workspace (tools, files, hooks); exits non-zero on failure
```

`make help` lists every target with a one-liner.

### PATH note

The upstream RTK installer drops the binary in `~/.local/bin/rtk` and does **not** edit your shell rc. If `~/.local/bin` is not already on your `PATH`, `make install` will print a warning. Add this to `~/.bashrc` / `~/.zshrc`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Or run `make path` to print the snippet.

## One-liner install

Skip the clone — drop `claude-skeleton` straight into any directory (empty or existing) and run full setup with a single command:

```bash
# Full setup in the current directory (mirror of `make dev`)
curl -fsSL https://raw.githubusercontent.com/FrederikSuijs/claude-skeleton/main/install.sh | sh

# Diagnose an existing setup
curl -fsSL https://raw.githubusercontent.com/FrederikSuijs/claude-skeleton/main/install.sh | sh -s -- check
```

The installer fetches the template as a tarball, drops the relevant files into the current directory (no-clobber by default), and runs `make -f claude.mk dev`. The Makefile content is **always** installed as `claude.mk` to avoid clobbering a project's existing `Makefile`. A 1-line `Makefile` stub (`include claude.mk`) is also dropped, but skipped automatically if `Makefile` already exists.

### Flags

```bash
curl -fsSL .../install.sh | sh -s -- --force         # overwrite existing files
curl -fsSL .../install.sh | sh -s -- --no-tools      # drop files only, skip system installs
curl -fsSL .../install.sh | sh -s -- --dry-run       # print actions, make no changes
curl -fsSL .../install.sh | sh -s -- --ref v0.4.0    # pin to a specific ref
curl -fsSL .../install.sh | sh -s -- --help          # full help
```

The script is non-interactive and idempotent — re-running it on an already-set-up project is a no-op. It targets macOS and Linux.

## Uninstall

```bash
make clean      # removes ~/.local/bin/rtk
```

## Working with Claude Code + RTK

Once `make dev` finishes, every Bash call Claude makes in this workspace is rewritten through `rtk`, which filters the output down to failures, errors, and grouped summaries. Typical savings:

| Command type | Savings |
|--------------|---------|
| Test runners (`vitest`, `jest`, `cargo test`, `pytest`) | 90–99% |
| Build / typecheck (`tsc`, `cargo build`, `next build`, `lint`) | 70–87% |
| Git (`status`, `log`, `diff`) | 59–80% |
| File tools (`ls`, `read`, `grep`, `find`) | 60–75% |

The `CLAUDE.md` shipped in this repo already instructs Claude to prefix every Bash call with `rtk`. No need to repeat that in your prompts.

To check your actual savings over time: `make gain` (or `rtk gain --history`).

## Graphify (knowledge graph for the codebase)

`make graphify` installs the [`graphify`](https://github.com/safishamsi/graphify) CLI (PyPI package: `graphifyy`) and registers its skill into `.claude/skills/graphify/`. The skill turns the codebase into a queryable knowledge graph — type `/graphify` in Claude Code to index the repo, then ask questions like "where is X defined?" or "what calls Y?" via `graphify query "<question>"`.

### What it writes

Running `make graphify` (or `make dev`, which calls it) mutates the working tree:

| Path | Change | Commit? |
|------|--------|---------|
| `.claude/skills/graphify/SKILL.md` | New (the skill body) | Yes |
| `.claude/skills/graphify/references/` | New (skill sidecar docs) | Yes |
| `.claude/CLAUDE.md` | New (routing hint: "when the user types `/graphify`, invoke the Skill tool") | Yes |
| `CLAUDE.md` | Appends a `## graphify` section with rules for the agent | Yes |
| `.claude/settings.json` | Adds two `PreToolUse` hooks (Bash + Read/Glob) that suggest `graphify query` instead of raw grep/read | Yes |

### About the PreToolUse hooks

The two hooks graphify registers in `.claude/settings.json` fire on every Bash and every Read/Glob call. Each runs a `python3 -c` snippet to decide whether to inject a "use graphify instead" hint into the agent's context. This means:

- **Every Bash call has a small per-invocation overhead** (the python3 check runs before RTK wrapping).
- **The agent is nudged toward `graphify query`** for codebase questions instead of reading files or grepping.
- **The hooks do nothing until you run `graphify build` first** — they check for `graphify-out/graph.json` and only inject the hint if the graph exists.

If you'd rather not have the hooks, remove the `hooks` block from `.claude/settings.json` after `make graphify` finishes. The skill still works (you can still type `/graphify` and use the CLI manually); only the automatic nudging is lost.

## Required tools

Everything `make dev` needs to set up a working workspace, and where each tool comes from. **If you have a recent Linux/macOS box with `uv` or `pipx`, `make dev` will install everything for you.** No other prereqs.

| Tool | Used for | Installed by | Auto? |
|------|----------|--------------|-------|
| `rtk` (Rust Token Killer) | Filters every Bash call Claude makes to ~10–20% of original output | `make install` | Yes — `curl … install.sh \| sh` |
| `pre-commit` | Pre-commit framework that runs hooks on every `git commit` | `make hooks` | Yes — `uv tool` / `pipx` / `pip3 --user` |
| `gitleaks` | Entropy + context-aware secrets detection in commits | `make hooks` | Yes — downloads release tarball to `~/.local/bin/gitleaks` (Linux x64/arm64/armv6/armv7, macOS x64/arm64). Manual: `brew install gitleaks` on other platforms. |
| `graphify` | Knowledge-graph skill for the codebase (`/graphify`, `graphify query`) | `make graphify` | Yes — `uv tool` / `pipx` / `pip3 --user` (PyPI package: `graphifyy`) |
| `caveman`, `find-skills` | Claude Code skills pinned in `skills-lock.json` | `make skills` (run as part of `make dev` via `skills-verify`) | Yes — fetched from upstream GitHub |
| `uv` **or** `pipx` **or** `pip3` | Python package manager used to install `pre-commit` and `graphify` | (you) | **No — install at least one before `make dev`.** Recommended: [`uv`](https://docs.astral.sh/uv/) (single static binary, fastest). |
| `curl` | Downloading RTK, gitleaks, and skill files from GitHub | (you) | **No — install before `make dev`.** Pre-installed on most macOS and Linux distros. |

The `make dev` target runs `install → init → hooks → graphify → skills-verify → verify` in that order. Each step auto-installs what it can and errors clearly when it can't. Re-run `make dev` any time; it's idempotent.

## Secrets scanning (pre-commit)

`.pre-commit-config.yaml` runs two layers on every `git commit` — for **any** committer (human, Claude Code, CI, anything):

1. `.githooks/secrets-scanner.sh` — local pattern-based scanner, 20+ pattern categories (AWS, GitHub PATs, private keys, Stripe, Slack, JWTs, etc.). Zero install cost.
2. `gitleaks` — entropy + context-aware detection with a maintained ruleset. Auto-installed to `~/.local/bin/gitleaks` by `make hooks` on first run (Linux x64/arm64, macOS x64/arm64). For other platforms, install manually: `brew install gitleaks` (macOS) or download from [the gitleaks releases](https://github.com/gitleaks/gitleaks/releases).

`make hooks` auto-installs the `pre-commit` framework and `gitleaks` (if they're not on PATH), then registers the git hook. To bypass for a single commit:

```bash
SKIP_SECRETS_SCAN=true git commit -m "add fixture with fake key"
# or skip all pre-commit hooks:
git commit --no-verify -m "..."
```

See [`.githooks/README.md`](./.githooks/README.md) for the full reference.

## Project-specific instructions

Add a second `## Project` section to `CLAUDE.md` (or a separate `CLAUDE.local.md` if you prefer not to commit project guidance) covering the bits that aren't derivable from the code: deployment targets, owned services, on-call rotation, etc. Keep it short — every line is loaded into context.

For per-project environment variables, copy `.env.example` to `.env` (which is gitignored) and fill in real values.

## License

See [`LICENSE`](./LICENSE). This project is licensed under the **GNU General Public License v3.0**.
