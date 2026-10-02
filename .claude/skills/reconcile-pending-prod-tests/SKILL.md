---
name: reconcile-pending-prod-tests
description: >
  Scans the queue of tests disabled in production for lack of deploy (an
  "awaiting-deploy" tag plus a tracking table), checks the tracker for what has actually
  shipped, revalidates in production only what's safely read-only, and returns coverage
  to the regression suite by removing the tag and the tracking row. Invoke after a
  deploy, or when asked what's stuck waiting on a deploy.
---

# Reconcile pending production tests

An "awaiting-deploy" tag disables production coverage for a test. It's meant to be a
**pause with a deadline**, and nobody comes back to remove it on their own: in one real
sweep, dozens of tests were disabled, most of their tracked tickets were already done,
and a pass against production came back fully green — tests had been sitting outside the
regression suite for no reason, some for weeks.

The regression suite's own alerting never complains about this: a test excluded by a tag
isn't considered, so it can't fail. Silence looks like health.

This skill closes that loop. Run it after a deploy, or whenever the doubt comes up.

## 1. Build the queue (two sources, they drift apart)

- The tracking table (a markdown file listing pending tests and their blocking ticket).
- The code itself: search for the awaiting-deploy tag across the test suite.

**Compare the two.** A mismatch is the finding, not a detail:

- Tag in code with no row in the table → coverage silently disabled, against the repo's
  own convention. Report it.
- Row in the table with no tag in code → the test is already running; the row is stale,
  clean it up.

Don't confuse this with a generic "work in progress" tag, which is unrelated: that one
marks debt in an area under active change, not something waiting on a deploy. This skill
doesn't touch that tag.

## 2. Check the tracker, ticket by ticket

For each ticket referenced in the queue, look up its current status.

- **Done / shipped** → candidate for revalidation (step 3).
- Still in an earlier status → legitimately still pending. Record the date to make the
  wait's age visible.

Tracker status is the trigger, but it isn't proof the code actually shipped. Proof is the
test passing in production — that's step 3.

## 3. Revalidate in production — only what's safe

**Production is read-only for this skill.** Before running any case, check what it
actually does. Anything mutating (create/update/delete) **does not run in production**,
even if the ticket is done, even if the tag was only ever about deploy timing.

Some queued cases are exactly this shape: a handful of tests send an intentionally
invalid payload to a mutating endpoint expecting a validation error — if production
accepted one of those, it would create real, unwanted data. Cases like that **stay in the
queue**, with the reason changed from "awaiting deploy" to "unsafe in production, needs
explicit authorization". Don't request that authorization by default; just record it.

For the read-only ones:

1. Authenticate against production (through whatever gate — VPN, service auth — the
   environment requires).
2. Run only that specific test against the production target.
3. **A red result only counts on the second run.** Failed once → rerun just that one.
   Passes → intermittency, record it and move on. Fails twice → a real failure: don't
   remove the tag, and classify it as app bug vs. stale test before doing anything else.

## 4. Return the coverage

For every test **green on both runs**:

- Remove the awaiting-deploy tag from that specific test (not from the whole file — just
  the one that was pending). If the surrounding group also carries an undocumented
  work-in-progress tag, flag it to the user and **don't** remove that one unilaterally.
- Move the row from the pending table to a history section ("validated in production on
  `<date>` — tag removed"), with the result.
- Never swap the tag for an unconditional skip — the repo's convention is a visible tag
  in the test config, not a silent skip.

## 5. Report

```
reconcile-pending-prod-tests — <date>
initial queue: <n> tests / <m> tickets
tickets already done: <list>
revalidated in production: <n> → green <n> | real failures <n> | intermittent <n>
tags removed: <list of tests>
staying in queue: <test — reason (ticket still open | unsafe in production | real failure)>
mismatches found: <tag with no table row | row with no tag in code>
```

End by asking the user for the commit (removing a tag and updating the table is a code
change): prepare the message with the ticket key, wait for a go-ahead. Don't commit or
push without authorization.

## When not to run

- Without access to whatever production requires (VPN, auth): nothing can be validated.
  Stop and say so.
- Empty queue and no tag in the code: report it in one line and stop.
