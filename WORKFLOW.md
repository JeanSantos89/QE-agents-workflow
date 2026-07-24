# The flow, end to end

From ticket links to a card in product review with evidence attached. Three points marked
⏸ are human decisions — the agent stops and waits.

```
/qa-run <ticket links>
   ├─ 1. Context (qa-context → live-context if memory doesn't cover it)
   ├─ 2. Repo recon in parallel (commit / assignee / files / endpoints)
   ├─ 3. Two lists: manual MVP + API/contract
   └─ 4. ⏸ CONSENSUS — you approve the lists
          └─ 5. Freeze api-tests-spec.md
                 ├─ /tuskr-import ──────────► CSV for manual import
                 └─ "start the automated ones"
                        ├─ 6. automation-scout → api-test-author
                        ├─ 7. Run staging, then production (read-only)
                        ├─    test-healer if something breaks
                        └─ 8. ⏸ COMMIT — you commit
                              └─ 9. Manual execution (you) → evidence PDF
                                    └─ 10. /jira-comment
                                          ├─ attach the PDF to each ticket
                                          ├─ one comment per ticket
                                          └─ transition to product review
                                                └─ 11. Feed the QA memory base
                                                      └─ ⏸ diff before committing
```

---

## Step 1 — You call it with the links

```
/qa-run https://$JIRA_SITE/browse/PROJ-123 <more links>
```

Accepts tracker and wiki links, and more than one ticket in the same call.

**What happens:**

1. **Context** — the curated local QA memory is consulted first (`qa-context`), which
   cross-references the request against what is already known: existing coverage,
   contradictions, inherited risk. If memory doesn't cover it, the agent returns
   `NEEDS_LIVE_CONTEXT` and the orchestrator goes to the tracker and wiki via MCP
   (`live-context`). Output: objective, scope, and what the MVP is.
2. **Repo recon** (in parallel) — across the configured repositories: find the assignee,
   search for the change commit by issue key, list the touched files, and identify which
   endpoints were affected. If the commit isn't found, the agent says **"commit not
   located"** — it does not invent one.

---

## Step 2 — The two lists

Delivered in a single response: summary + recon + both lists.

| List | Limit | Criterion |
|---|---|---|
| **Manual MVP** | no limit | Covers the whole MVP of each ticket, detailed, no redundancy |
| **API/contract** | up to 3 **per ticket** | Anchored in the APIs the recon showed had changed |

A purely visual/UI ticket produces **zero** API tests. A ticket about, say, chart labels
overlapping at narrow viewport widths has no contract surface to test — the manual list
covers it and the API list is empty. Saying "zero" is the correct answer there, not a gap.

---

## Step 3 — ⏸ Consensus

The lists get adjusted until you approve them. Nothing is automated before that.

With an **explicit OK**, the contract is frozen at `$AUTOMATION_REPO_PATH/api-tests-spec.md`:
context, commit/assignee/files/APIs, repo conventions, and the approved API list (title +
what to validate + environment). That file is the shared memory of the automation
subagents — they don't see the conversation, only the spec.

From here the flow forks into two independent paths:

- **Manual** → `/tuskr-import` generates the CSV (`Suite,Title,Steps,Expected Result`) for
  you to import. The test manager here is **CSV only** — no API token, so no automatic test
  run creation.
- **Automated** → you say **"start the automated ones"**.

---

## Step 4 — Automation (only when you ask)

1. `automation-scout` (read-only) maps how the automation repo does things: patterns, auth,
   fixtures, environment tag convention.
2. `api-test-author` writes the tests at minimum viable scope, validates in **staging** and
   then in **production** — in production, **read-only only**.
3. If something breaks, `test-healer` diagnoses and **classifies**: application bug
   (regression) or flaky test. If it's an app bug, it does not mask it — it reports.
4. Environment tags matter. The production CI workflow excludes by tag, so staging-only
   cases, performance cases, and anything depending on internal network access must carry
   the right tag or it will run where it can't pass.
5. **⏸ The agent does not commit.** It stops and asks you. End-to-end tests only with
   explicit authorization.

Note on ordering: if the code isn't deployed to production yet, running the production
cases produces false negatives. Those cases are **written with the tag but not executed**
in this run, and recorded in a pending file for a post-deploy sweep. Pending production is
not a failure and does not block the merge request.

---

## Step 5 — Manual execution and evidence

You run the manual cases in the test manager and export the result as a PDF. Suggested
convention:

```
$EVIDENCE_DIR/<MM DD>/Run <ids>.pdf
```

One PDF can cover several runs.

---

## Step 6 — Closing the tickets (`/jira-comment`)

```
/jira-comment PROJ-123 PROJ-124 PROJ-125 "<path to the PDF>"
```

Works standalone or as the final step of `/qa-run`. **Mandatory order — evidence, comment,
transition.** A card is never moved before it has a comment.

### 6.1 Attaching the evidence

The PDF is attached **to the ticket itself**, via the tracker's REST API
(`POST /rest/api/3/issue/{key}/attachments`). The upload runs locally — PowerShell reads
the file from disk and sends it, so the PDF content never passes through the model. Script:
`.claude/skills/jira-comment/jira-attach.ps1`. One attachment per ticket.

**Prerequisite:** `JIRA_TOKEN` in the session. The MCP OAuth connection does not work for
this: it neither exposes the credential nor offers an attachment tool. Set it with:

```
! $env:JIRA_TOKEN = '<token from id.atlassian.com/manage-profile/security/api-tokens>'
```

That lasts for the session only. To avoid repeating it, set it persistently outside the
session (`setx JIRA_TOKEN ...` on Windows).

*Fallback without a token:* put the PDF in a shared drive folder yourself and have the agent
locate it and use the shareable link in the comment. The agent cannot upload it on its own —
MCP file upload requires the content inline as base64, which is unworkable for a PDF of
several hundred KB.

### 6.2 The comment — one per ticket, never two

Structure:

1. **Descriptive body** — what was tested/automated and validated, in short bullets,
   anchored in that ticket's acceptance criteria.
   - Read-only production tests: mention that they also run automatically against
     production after deploy.
   - Staging-only tests: do **not** mention production.
2. **Links, at the end of the same comment** — evidence (attachment), the commit specific
   to that ticket, and the PR when there is one. Each ticket gets only its own commit.

No separate commit-only comment: the tracker's development panel already associates commits
natively.

### 6.3 Transition

The transition whose destination is the product review status is **discovered at runtime**
(`getTransitionsForJiraIssue`) and applied to each ticket. Transition and status IDs are
never hard-coded — they change whenever someone edits the workflow.

If the transition doesn't exist from the current status, no alternative path is forced: the
agent reports the ticket, its current status, and the available transitions, then continues
with the rest.

At the end, a per-ticket report: comment posted, evidence link, final status — and what was
left pending, with the reason.

---

## Step 7 — Closing the loop in the QA memory base

A **fixed** step, not optional: the QA memory base at `$QA_MEMORY_PATH` gets fed what the
run validated. `qa-context` reads that base at the start of every run — without feeding it
at the end, it never learns.

Curation filter (business rules only):

- **Goes in:** the validated rule + a coverage marker (e.g. "coverage: contract test
  automated in `contracts-*.spec.ts`, validated in staging; production post-deploy").
- **Stays out:** commit SHAs, PRs, dates (that's what the tracker and git are for),
  cosmetic/visual details, and flaky-test heals — an incident entry is only for a real app
  bug or regression.
- Prefer **editing** the existing behavior file over creating a new one.
- Keep that repo neutral: no company name, URL, or ticket key outside `knowledge/`, and
  commits without AI attribution.
- **⏸ Stop before committing** and show the diff.

---

## Known limitations

| Limitation | Practical effect |
|---|---|
| The agent doesn't read the PDF | It doesn't know what the screenshots show or whether the run passed. The comment is derived from the acceptance criteria — if a case failed or you want specific numbers, say so when you ask. Installing a PDF text extractor (`poppler-utils`) removes this. |
| `JIRA_TOKEN` is per session | It will be asked for again in a new session unless set persistently. |
| A command typed with `!` lands in the transcript | The token is recorded in plain text in the session history. Rotate it periodically. |
| No accented path literal inside a `.ps1` | PowerShell 5.1 reads the script as ANSI and the path breaks. The script locates the PDF with `Get-ChildItem -Recurse -Filter`. |
| Test manager without an API | CSV import only; running the manual cases and exporting the PDF are yours. |
| No automatic push or destructive git | Commits and pushes are always yours, or require explicit authorization. |

---

## What you actually type

| Moment | Command |
|---|---|
| Start | `/qa-run <tracker/wiki links>` |
| After approving the lists | `/tuskr-import` (CSV of the manual cases) |
| To automate the API tests | "start the automated ones" |
| Before closing (first time in the session) | `! $env:JIRA_TOKEN = '...'` |
| Closing | `/jira-comment <tickets> "<path to the PDF>"` |
