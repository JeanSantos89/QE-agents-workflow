---
name: jira-comment
description: Closes tracker tickets after a QA run — links the commit, posts ONE comment per ticket (description + commit/PR links + evidence link), attaches the evidence PDF to the ticket, and moves the tickets to the review status. Trigger with /jira-comment or when the user asks to comment, attach evidence, and/or move tickets to review.
---

# Closing a ticket (commit link + comment + evidence + review status)

Two valid modes:

- **Standalone:** `/jira-comment PROJ-123 PROJ-124 PROJ-125 <path-to-pdf>`.
- **Inside the agent flow:** the final step of `/qa-run` or of `api-test-author` — after the
  commit/merge and after feeding the QA memory base, call this skill to close the tickets.
  It depends on no prior context: if a ticket, the PDF, or the links are missing, it asks.

Expected input: a list of ticket keys, optionally the path to the evidence PDF and the
commit/PR links.

Mandatory order: **1) link the commit in the dev panel → 2) evidence → 3) comment →
4) transition.** The review transition is always the last step — never transition before
the comment exists, and never in the same batch where the commit was just linked.

## Configuration

Read from the environment: `JIRA_SITE`, `JIRA_EMAIL`, `JIRA_PROJECT`, `JIRA_TOKEN`,
`REVIEW_STATUS_NAME`, `EVIDENCE_DIR`. Nothing about the site, project, or workflow is
hard-coded in this skill.

## 0. Link the commit — native dev panel, NOT a comment

The real link lives in the tracker's own development panel (its native VCS integration),
and it's created by the **ticket key appearing in the commit message** — there's no API
call that attaches a commit after the fact.

1. **Before committing**, put the ticket key in the message, ideally in the title
   (`PROJ-123: <summary>`). A commit serving two tickets cites both keys.
2. **Push.** Without a push there's no link — the integration reads the remote, not the
   local repo.
3. **Verify** the panel picked it up (fetch the ticket's development-panel field) before
   moving on.
4. If it didn't, it may be integration latency (wait and recheck once) or a missing/wrong
   key. **Don't compensate with a comment** — report that the native link didn't happen.
5. A commit that doesn't belong to the ticket (or a ticket with no commit) → don't link
   anything, don't invent a link. State that there's no commit for that ticket.

## 1. Evidence (PDF) — native attachment on the ticket

The validated, preferred path: attach the PDF **to the ticket itself** via the tracker's
REST API. The upload runs locally (PowerShell reads the file from disk), so the PDF content
never has to be carried by the model.

- Endpoint: `POST https://$JIRA_SITE/rest/api/3/issue/{key}/attachments`
- Auth: Basic `base64($JIRA_EMAIL:$JIRA_TOKEN)` + header `X-Atlassian-Token: no-check`
- Multipart, field `file`. Use `System.Net.Http` (PowerShell 5.1 has no `-Form`).
- Reference script: `jira-attach.ps1`, next to this file. It takes the ticket keys and the
  PDF filename pattern as arguments.
- Link for the comment:
  `https://$JIRA_SITE/secure/attachment/{id}/{filename-url-encoded}`

Prerequisites and pitfalls:

- `JIRA_TOKEN` must exist in the session (API token from
  `id.atlassian.com/manage-profile/security/api-tokens`). An OAuth-based MCP connection
  does **not** work here: it doesn't expose the credential and has no attachment tool. Ask
  the user to run `! $env:JIRA_TOKEN = '...'` — never ask for the token as a chat message.
- **Never write an accented path literal inside the `.ps1`**: PowerShell 5.1 reads the
  script as ANSI and the path breaks. Locate the file with
  `Get-ChildItem -LiteralPath $env:EVIDENCE_DIR -Recurse -Filter '<pattern>.pdf'`.
- Attach the same PDF to every ticket in the list (one attachment per ticket, a different id
  per ticket).

## 1b. Fallback: a shared drive link (when there is no token)

1. Check whether the PDF is already in the shared evidence folder (search by filename).
2. If it is, use the shareable link it returns. This step is done.
3. If it is not, **do not try to work around the upload.** MCP file upload requires the
   content inline as base64, and evidence PDFs are typically hundreds of KB — that is not
   transmittable. Ask the user to put the file in the folder, wait for confirmation, then go
   back to step 1 for the link.
4. Do not proceed to the comment without a link.

The link in the comment must be the shareable URL, never a local path.

## 2. The comment (one per ticket)

Use the tracker MCP's add-comment tool. ONE comment per ticket, never two. Each ticket gets
only its own commit.

### Format: plain markdown, and only markdown

Always submit the body as plain markdown — never mix in the tracker's own legacy wiki
markup. Since the add-comment call usually returns the saved body, **read it back** and
confirm no leftover legacy markup before moving on; that's the failure mode that only
shows up after posting.

Structure:

1. **Descriptive body** — what was automated/tested and validated in staging, in short
   bullets (one per test/scenario).
   - Read-only production tests (`$TAG_PROD_READONLY`): include that they are also scheduled
     to run automatically against production after deploy (post-deploy, read-only).
   - Staging-only tests (`$TAG_STAGING_ONLY`): do NOT mention production.
2. **Links, at the END of the same comment:**
   - Evidence: the attachment link on the ticket (or the shared drive link, path 1b).
   - The commit specific to that ticket (when there is one).
   - The PR (when there is one).

Do not create a separate commit-only comment — the tracker's development panel already
associates commits natively, and that is enough.

## 3. Move to the review status

For each ticket:

1. Call `getTransitionsForJiraIssue` to **discover at runtime** the `id` of the transition
   whose destination is `$REVIEW_STATUS_NAME`. Match on the destination status, not the
   transition name — they often differ. Never hard-code a transition or status id.
2. Call `transitionJiraIssue` with that `id`.
3. If the transition is not available from the current status, do NOT force an alternative
   path and do not change the status by other means: report the ticket, its current status,
   and the available transitions, then continue with the remaining tickets.

## At the end

Report per ticket: commit linked (yes/no), comment posted (yes/no), the evidence link used,
final status. List explicitly what was left pending and why.
