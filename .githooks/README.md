# Secrets Scanning (pre-commit hooks)

Two-layer defense-in-depth: a **local pattern-based scanner** plus
**gitleaks** for entropy/context-aware detection. Together they block
`git commit` when staged content contains likely-leaked secrets — for
**any** committer (human, Claude Code, CI script, anything).

## Layers

| Layer | Source | Catches | Misses |
|---|---|---|---|
| `secrets-scanner` (local) | [`github/awesome-copilot`](https://github.com/github/awesome-copilot/tree/main/hooks/secrets-scanner) | Well-known prefixes (`ghp_…`, `AKIA…`, `sk_live_…`), private keys, connection strings, JWTs | Novel high-entropy strings in non-standard positions; context-blind |
| [`gitleaks`](https://github.com/gitleaks/gitleaks) | upstream | Entropy-based + large maintained ruleset + allowlisting | Requires `gitleaks` binary on PATH |

Run in that order on every commit. If either finds a hit, the commit is blocked.

---

## Layer 1: `secrets-scanner` (local)

### What it catches

20+ pattern categories, including:

- AWS access keys, GCP service account JSON, Azure client secrets
- GitHub PATs (`ghp_…`, `gho_…`, `ghs_…`, `github_pat_…`)
- Private keys (RSA, EC, OpenSSH, PGP)
- Stripe live keys, Slack/Discord/Twilio/SendGrid tokens
- Generic high-entropy `secret=…` / `api_key=…` / `password=…` assignments
- Connection strings (Postgres, MongoDB, MySQL, Redis, AMQP, MSSQL)
- JWTs
- Internal IPs with ports

### What it does **not** catch

- Entropy-based detection of novel patterns (layer 2 covers this)
- Binary secrets (DER keystores, encrypted blobs)
- Context-aware false-positive suppression — use `SECRETS_ALLOWLIST` or rename obvious placeholders

### Configuration (secrets-scanner)

| Env var              | Default                    | Notes                                                                 |
| -------------------- | -------------------------- | --------------------------------------------------------------------- |
| `SCAN_MODE`          | `block`                    | `warn` logs only, `block` exits non-zero and aborts the commit.       |
| `SCAN_SCOPE`         | `staged`                   | `staged` scans index content (what will be committed); `diff` scans all modified files. |
| `SKIP_SECRETS_SCAN`  | unset                      | Set to `true` to bypass entirely. Escape hatch only.                  |
| `SECRETS_LOG_DIR`    | `logs/copilot/secrets`     | Where JSON-lines scan logs are written.                               |
| `SECRETS_ALLOWLIST`  | unset                      | Comma-separated substring patterns to ignore.                         |

### Adding patterns

Edit `secrets-scanner.sh` and add a line to the `PATTERNS=()` array:

```bash
PATTERNS=(
  # ... existing entries ...
  "MY_CUSTOM_TOKEN|high|myco_[0-9A-Za-z]{32}"
)
```

Format is `NAME|SEVERITY|REGEX`. Severity is informational only (logged
in JSON output); it does not change blocking behavior.

### Updating the vendored script

```bash
curl -sL https://raw.githubusercontent.com/github/awesome-copilot/main/hooks/secrets-scanner/scan-secrets.sh \
  -o .githooks/secrets-scanner.sh
chmod +x .githooks/secrets-scanner.sh
```

Then re-apply the two default changes at the top of the file:
`SCAN_MODE=${SCAN_MODE:-block}` and `SCAN_SCOPE=${SCAN_SCOPE:-staged}`.

---

## Layer 2: `gitleaks`

Entropy and context-aware detection, backed by a maintained ruleset
covering hundreds of providers and high-entropy patterns the local
scanner misses.

### Install the binary

```bash
brew install gitleaks            # macOS
# or: https://github.com/gitleaks/gitleaks/releases
```

### Baseline for existing repos (do this once)

If your repo has historical secrets already committed (and you accept
that risk, or they've been rotated), generate a baseline so the hooks
don't fire on every old file:

```bash
gitleaks detect --baseline-path .gitleaks-baseline.json --redact
# or for staged-only scanning on first install:
gitleaks git --pre-commit --redact --staged --verbose --baseline-path .gitleaks-baseline.json
```

Add `.gitleaks-baseline.json` to the repo. Subsequent runs will only
flag **new** findings, not the ones in the baseline.

### Per-finding allowlist (gitleaks-native)

Gitleaks uses a `.gitleaks.toml` config for fine-grained allowlisting
(per-rule, per-path, per-regex). See
[gitleaks config docs](https://github.com/gitleaks/gitleaks/blob/master/README.md#configuration).

---

## One-time setup

The Makefile wraps all of this — from the repo root, just run:

```bash
make dev        # or, for hooks only: make hooks
```

That target verifies the `pre-commit` framework is installed, warns if
`gitleaks` is missing, and runs `pre-commit install` to register the
git hook. If you'd rather do it by hand:

```bash
# 1. Install pre-commit framework
brew install pre-commit            # macOS
# or: pipx install pre-commit

# 2. Install gitleaks (layer 2)
brew install gitleaks

# 3. Install the hooks into .git/hooks/
pre-commit install

# 4. (Optional) Run against all files once to verify nothing is flagged
make lint        # or: pre-commit run --all-files
```

After this, every `git commit` — by you, by Claude Code, by anything —
will be scanned by both layers. To bypass for a single commit:

```bash
SKIP_SECRETS_SCAN=true git commit -m "add fixture with fake key"
# or skip all pre-commit hooks:
git commit --no-verify -m "..."
```

