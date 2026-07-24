# QA workflow for Claude Code

A QA workflow built as Claude Code configuration: one slash command, one skill, and seven
subagents that take a QA analyst from "here are the ticket links" to "the card is in
product review, with evidence attached".

It is opinionated about one thing: **the agent never decides what a human should decide.**
There are three hard stops in the flow — approving the test lists, committing code, and
committing to the QA memory base. Everything between them is automated.

Tools referenced are real and interchangeable: Jira (tracker + wiki), Tuskr (manual test
case management), Playwright (automation), GitHub Actions (CI). Nothing here is specific to
a particular company, product, or repository — all of that is configuration.

## What's in here

| Path | What it is |
|---|---|
| `WORKFLOW.md` | The end-to-end flow, step by step, with the stop points |
| `.claude/commands/qa-run.md` | `/qa-run <ticket links>` — the orchestrator entry point |
| `.claude/skills/jira-comment/` | Closing a ticket: evidence → comment → transition |
| `.claude/agents/*.md` | The seven subagents (context, test design, automation, healing, export) |
| `.env.example` | Every value you need to configure |

## The subagents

| Agent | Role | Access |
|---|---|---|
| `qa-context` | Reads the local curated QA memory first; signals a gap instead of guessing | read-only |
| `gi-context` | Fetches live context from the tracker and wiki when memory doesn't cover it | read-only |
| `create-tests` | Turns consolidated context into manual test cases grouped by suite | — |
| `automation-scout` | Maps how the automation repo already does things | read-only |
| `api-test-author` | Writes the minimum viable API/contract tests, validates them | writes tests, never commits |
| `test-healer` | Classifies a failure as app bug vs. flaky test — never masks a real bug | writes fixes only for flaky tests |
| `tuskr-import` | Exports manual cases to CSV for manual import | writes a CSV |

`gi-context` keeps its name for continuity with the agent that consumes it; rename freely.

## Setup

1. Copy `.claude/` into your project (or into `~/.claude/` for a personal setup).
2. Copy `.env.example` to `.env` and fill it in. The workflow reads these as environment
   variables — nothing is hard-coded to one tracker site or project key.
3. For the Jira attachment step, create an API token at
   `id.atlassian.com/manage-profile/security/api-tokens` and set `JIRA_TOKEN` in your
   shell. Do not put it in a file that gets committed.
4. Point `QA_MEMORY_PATH` at your curated QA knowledge base if you have one. If you don't,
   `qa-context` will always signal a gap and the flow falls through to live lookup — that
   works fine, it just doesn't accumulate.

## Adapting it

**Different tracker?** The context agents talk to the tracker through an MCP server. Swap
the tool names in `gi-context.md` and `jira-comment/SKILL.md`; the flow doesn't change.

**Different test manager?** `tuskr-import` writes a four-column CSV. Change the header to
match your importer's format.

**No automation repo yet?** `automation-scout` reports "greenfield" and proposes a minimal
structure instead of inventing patterns. That's the intended behavior.

**Environment tags.** The automation side assumes a tag convention that decides what runs
where — read-only cases against production, mutations staging-only, and a tag for tests
that need internal network access so CI can exclude them. Names are yours; the rule that
production is read-only is not negotiable in these prompts.

## Lessons worth keeping

Things that cost real debugging time and generalize to any similar setup:

- **An OAuth-based MCP connection to your tracker may not expose the credential, and may
  have no attachment tool at all.** File attachment then needs a separate API token in an
  environment variable — not a gap in the workflow, just a different path.
- **File upload through MCP generally requires the content inline as base64.** For a
  multi-hundred-KB PDF that's unworkable. The fix is a local script that reads the file
  from disk, so the file content never passes through the model.
- **PowerShell 5.1 reads `.ps1` files as ANSI.** A path with an accented character written
  literally inside the script breaks. Locate files with `Get-ChildItem -Recurse -Filter`
  instead of hard-coding the path.
- **A token typed into a command lands in the session transcript** in plain text. Rotate
  periodically, and prefer setting it outside the session.
- **Never let an agent report "done" without pasting the runner's real output.** A declared
  pass is not a pass. The `api-test-author` prompt enforces this explicitly.
- **Discover workflow transition IDs at runtime.** Hard-coded status and transition IDs
  break the first time someone edits the workflow.

## License

MIT.
