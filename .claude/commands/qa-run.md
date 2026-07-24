---
description: QA orchestrator — takes tracker/wiki links and returns context + commit/assignee + 2 lists (manual MVP and API/contract). On consensus, freezes api-tests-spec.md. Usage: /qa-run <links>.
---

# /qa-run — QA orchestrator (links → 2 lists → spec)

You are the orchestrator. The user pastes tracker or wiki links after `/qa-run`.
Automate NOTHING here — only prepare and reach consensus. Automation starts only when the
user says "start the automated ones" (the `api-test-author` agent).

## Steps

### 1. Context
- Call `qa-context` (curated local memory) for the story behind the links.
- If it returns `NEEDS_LIVE_CONTEXT`, call `gi-context` (tracker/wiki via MCP).
- Summarize the ticket in a few lines: objective, scope, what the MVP is.

### 2. Repo recon (in parallel with context)
Repos: `$REPO_BACKEND` and `$REPO_FRONTEND`.
- Find who owns the ticket (assignee field in the tracker).
- Via the GitHub MCP: `search_commits` / `list_commits` by author + issue key
  (e.g. `PROJ-123`) to locate the change commit.
- List the touched files → identify which APIs/endpoints were affected.
- If the commit isn't found: say "commit not located" explicitly and continue with the API
  list based on context alone. Do not invent a commit.

### 3. Produce the 2 lists
Call `create-tests` with the consolidated context.
- **List 1 — Manual MVP**: NO case limit. Covers the whole MVP of each ticket, detailed,
  unified, with NO redundancy.
- **List 2 — API/contract**: limit of **up to 3 PER TICKET** (not 3 total), anchored in the
  APIs the recon showed had changed. A purely visual/UI ticket produces 0 API tests. Titles
  and what each one validates only — no test code here.

Present everything in a single response: summary + recon (commit/assignee/files) + both lists.

### 4. Consensus
Discuss with the user and adjust both lists until they approve.

### 5. Freeze the contract (only after explicit approval)
Write `$AUTOMATION_REPO_PATH/api-tests-spec.md` containing:
- Ticket context (summary).
- Commit / assignee / touched files / affected APIs.
- Relevant repo conventions (what is already known; the scout fills in the rest).
- **The approved API list** (one block per test: title + what to validate + environment).

This file is the shared memory of the automation subagents — they cannot see this
conversation.

Then tell the user:
- For the manual CSV: `/tuskr-import` (manual cases only).
- To automate the API tests: say "start the automated ones" → `api-test-author`.

## Rules
- This command does not automate, does not write test code, does not commit.
- Production is read-only (inherited by `api-test-author`).
- Never invent a commit or an endpoint: if the recon doesn't find it, say so.
