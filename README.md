# claude-skeleton

Opinionated starter template for LLM-assisted projects. Pre-configured `CLAUDE.md` with scoped context, lean token hygiene, MCP plugin stubs, and agent task scaffolding. Drop in, vibe code. Stop re-solving the same Claude setup every project.

## What's inside

| Path | Purpose |
|------|---------|
| `CLAUDE.md` | Behavioral guidelines for Claude (think first, simplify, surgical changes, goal-driven) plus the full RTK (Rust Token Killer) command reference. |
| `.claude/` | Project-local Claude Code configuration (settings, hooks). |
| `.rtk/` | RTK state directory. |
| `skills-lock.json` | Pinned versions of installed skills (e.g. `caveman`, `find-skills`) for reproducible installs. |
| `.gitignore` | General-purpose ignores covering Python, Node, Go, Rust, JVM, .NET, C/C++, Ruby, PHP, Docker, Terraform, and common editors/OSes. |
| `Makefile` | Workspace setup — installs RTK, registers the PreToolUse hook, and verifies the toolchain. |

## Quick start

```bash
make dev        # install rtk, wire the Claude Code hook, verify
```

That target is idempotent — re-run it any time and it skips steps that are already done.

If you only want one piece:

```bash
make install    # install rtk binary
make init       # register the PreToolUse hook (RTK_INIT_TARGET=claude-code|cursor|global)
make verify     # confirm rtk is on PATH and print its version
make gain       # token-savings dashboard
```

`make help` lists every target with a one-liner.

### PATH note

The upstream RTK installer drops the binary in `~/.local/bin/rtk` and does **not** edit your shell rc. If `~/.local/bin` is not already on your `PATH`, `make install` will print a warning. Add this to `~/.bashrc` / `~/.zshrc`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Or run `make path` to print the snippet.

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

## Project-specific instructions

Add a second `## Project` section to `CLAUDE.md` (or a separate `CLAUDE.local.md` if you prefer not to commit project guidance) covering the bits that aren't derivable from the code: deployment targets, owned services, on-call rotation, etc. Keep it short — every line is loaded into context.

## License

See [`LICENSE`](./LICENSE). This project is licensed under the **GNU General Public License v3.0**.
