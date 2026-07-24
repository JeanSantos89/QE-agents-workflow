# QE agents workflow

A quality engineering workflow built entirely as agent configuration: one slash command,
one skill, and seven subagents that carry a ticket from *"here are the links"* to *"the card
is in product review, with evidence attached"*.

No framework, no dependencies, no code to run. It's Markdown — prompts with sharp
boundaries.

## Why this exists

Most attempts to put an agent in a QA workflow fail the same two ways: the agent invents
context it doesn't have, and it declares success it never verified. This workflow is built
against both.

**It refuses to guess.** The context agent reads a curated memory base first and, when that
memory doesn't cover the request, emits an explicit `NEEDS_LIVE_CONTEXT` signal instead of
filling the gap with plausible text. If the recon can't find the commit for a ticket, it
says "commit not located" — the prompt forbids inventing one.

**It refuses to claim a pass.** No test is reported ready without the test runner's real
output pasted into the report. A declared PASS is not a PASS.

**It never decides what a human should decide.** Three hard stops, marked ⏸: approving the
test lists, committing code, and committing to the memory base. Everything between them is
automated; none of them is ever crossed alone.

And it closes the loop — the validated business rule goes back into the memory base at the
end of every run, so the next run starts better informed than the last. That's the part
most setups skip, and it's the reason the memory base is worth having at all.

## The flow

```
/qa-run <ticket links>
   ├─ context (memory first → live lookup only if needed)
   ├─ repo recon in parallel (commit / assignee / files / endpoints touched)
   ├─ two lists: manual MVP + API/contract
   └─ ⏸ you approve → the spec is frozen as shared subagent memory
          ├─ /tuskr-import → CSV for the test manager
          └─ "start the automated ones" → scout → author → healer
                 └─ ⏸ you commit
                        └─ /jira-comment → evidence, comment, transition
                               └─ ⏸ you approve the memory diff
```

Full detail, including the pitfalls at each step, is in **[WORKFLOW.md](WORKFLOW.md)**.

## The seven subagents

Each one has a narrow scope and a defined refusal.

| Agent | Role | Refuses to |
|---|---|---|
| `qa-context` | Reads the curated QA memory; cross-references coverage, contradictions, inherited risk | Invent a behavior — signals the gap instead |
| `live-context` | Fetches live context from the tracker and wiki when memory falls short | Report documentation it didn't find |
| `create-tests` | Turns context into manual cases grouped by suite | Look anything up on its own, or restate a criterion twice |
| `automation-scout` | Maps how the automation repo already does things — patterns, auth, fixtures, tags | Write anything; suggest a mutation against production |
| `api-test-author` | Writes the minimum viable API/contract tests and validates them | Commit; report ready without the pasted runner output |
| `test-healer` | Classifies a failure as app bug vs. flaky test | Loosen an assertion to hide a real bug |
| `tuskr-import` | Exports the manual cases to CSV | Need an API token for a CSV-only path |

## What's in here

```
README.md          WORKFLOW.md          .env.example
.claude/
  commands/qa-run.md                    the orchestrator entry point
  skills/jira-comment/                  evidence → comment → transition
  agents/*.md                           the seven subagents
```

Tools named are real and swappable: Jira as tracker and wiki, Tuskr for manual test cases,
Playwright for automation, GitHub Actions for CI. Nothing is tied to a specific company,
product, or repository — all of that is configuration.

## Setup

1. Copy `.claude/` into your project, or into `~/.claude/` for a personal setup.
2. Copy `.env.example` to `.env` and fill it in. Every site, project key, repo, path, and
   environment tag is a variable — nothing is hard-coded.
3. For the attachment step, create a Jira API token at
   `id.atlassian.com/manage-profile/security/api-tokens` and set `JIRA_TOKEN` **in your
   shell**, never in a committed file.
4. Point `QA_MEMORY_PATH` at your curated knowledge base. Don't have one? Leave it empty —
   `qa-context` will signal a gap every time and the flow falls through to live lookup. It
   works; it just doesn't accumulate.

## Adapting it

**Different tracker.** The context agents reach the tracker through an MCP server. Swap the
tool names in `live-context.md` and `jira-comment/SKILL.md`; the flow is unchanged.

**Different test manager.** `tuskr-import` writes a four-column CSV. Change the header to
whatever your importer expects.

**No automation repo yet.** `automation-scout` reports "greenfield" and proposes a minimal
structure rather than inventing patterns. That's intended behavior, not a failure.

**Your own tag convention.** The automation side assumes tags decide what runs where:
read-only cases against production, mutations staging-only, and a tag for tests needing
internal network access so CI can exclude them. The names are yours. The rule that
production is read-only is not negotiable in these prompts.

## Lessons worth keeping

Each of these cost real debugging time, and none is specific to this setup.

- **An OAuth-based MCP connection to your tracker may expose no credential and no
  attachment tool at all.** Attaching a file then needs a separate API token in an
  environment variable. Not a gap in the workflow — a different path.
- **File upload through MCP generally wants the content inline as base64.** For a
  several-hundred-KB PDF that is not transmittable. The fix is a local script that reads the
  file from disk, so its content never passes through the model.
- **PowerShell 5.1 reads `.ps1` files as ANSI.** An accented character in a path literal
  inside the script breaks it. Locate files with `Get-ChildItem -Recurse -Filter` instead of
  hard-coding paths.
- **A token typed into a command lands in the session transcript** in plain text. Set it
  outside the session, and rotate it periodically.
- **Discover workflow transition IDs at runtime.** Hard-coded status and transition IDs
  break the first time somebody edits the workflow — and they leak your instance's internals
  into the repo.
- **Give each subagent a self-contained briefing.** Subagents don't see the orchestrator's
  conversation. That's why the approved list is frozen into a spec file first: the spec is
  their context, and without it they improvise.
- **Pending is not failing.** If the code isn't deployed yet, production cases are written
  and tagged but not executed — recorded for a post-deploy sweep. Running them early
  produces false negatives and erodes trust in the suite.

## License

[MIT](LICENSE).
