# Tasks

Unit-of-work specs for handing work to an agent (Claude Code, a CI
job, a teammate). The format lives in `TEMPLATE.md`; copy it, fill it
in, drop the new file in this directory with a kebab-case name.

## Layout

```
tasks/
├── README.md      # this file
└── TEMPLATE.md    # copy this for every new task
```

## When to use one

- The work is bigger than a one-liner and you want a contract the
  agent can verify against.
- You're handing the task to someone (human or LLM) who wasn't in the
  original conversation.
- The acceptance criteria need to survive a code review.

A typo fix, a one-line config change, a docs paragraph: don't bother
with a task file. Open the PR.

## Lifecycle

1. Copy `TEMPLATE.md` to `tasks/<kebab-case-slug>.md`.
2. Set **Status** to `draft` and fill in **Context**, **Goal**,
   **Acceptance criteria**, **Verify**.
3. When work starts, set **Status** to `in-progress` and **Owner** to
   the person / agent.
4. When the **Verify** commands pass and every acceptance criterion is
   checked, set **Status** to `done` and either delete the file or move
   it to `tasks/done/` (create that directory if you want history).

## Status values

| Status | Meaning |
|---|---|
| `draft` | Not yet ready to be picked up. |
| `in-progress` | Someone is working on it. |
| `blocked` | Work is paused on something external. Note the blocker in **Notes**. |
| `done` | All acceptance criteria met and **Verify** has been run. |

The status is for humans skimming the directory. The contract is the
**Acceptance criteria** + **Verify** pair — an agent working on a
`draft` task should be expected to push back, not silently absorb
vague requirements.
