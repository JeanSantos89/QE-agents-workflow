---
name: challenge-test-cases
description: >
  Quality gate between test-case generation and human approval. Two independent judges,
  each in a clean subagent context, review the list — one anchors every case against the
  acceptance criteria (gaps, redundancy), the other checks every cited name against the
  real source code (hallucination). They receive only the cycle's facts, never the
  generating agent's defense of its own output. Returns keep / rewrite / cut, always with
  a cited source. Invoke after test-case generation, before execution.
---

# Challenge test cases (anti-slop gate)

A grossness filter, **not** a certification. The gate answers two questions the agent
that wrote the cases can't answer about itself:

1. Does every case target a bug this change could plausibly cause — and is anything
   missing?
2. Do the names each case cites actually exist?

Everything else (oracle design, layer choice, step count) is a generation constraint and
lives upstream, in test-case generation. This gate doesn't redo that work.

## Facts go in, defense doesn't

The judgment runs in a subagent because the model that generated the cases is biased
toward defending what it just wrote. But the subagent still needs **facts** to judge —
without them it guesses, and a guess has already deleted good coverage before (a real
incident: four legitimate fields got flagged as hallucinated because the judge had no
source code to check against).

| Goes in (fact of the cycle) | Doesn't go in (author's defense) |
|---|---|
| Ticket verbatim, numbered acceptance criteria (AC1, AC2…) | Transcript of the generation |
| Diff reference: repo, commit, PR, files, endpoints touched | Why the author picked each case |
| Context agent output: behaviors cited by file, covered / contradicted / inherited-risk, environment traps | Discussion with the user |
| CI pipeline probe result: target pipeline and whether it's alive | Verdict from a previous gate round |
| Numbered list with stable IDs (`M-xx`, `A-xx`), every case with all its fields | Author's paraphrase of the ticket instead of the verbatim |

The line "Why this is manual:" is part of the case and goes in — it's a claim to be
judged, not a defense.

All of this should already be assembled by whatever produced the test case list. If the
ticket or the list is missing, **stop and ask**. If the diff is missing, run the
requirement judge only and skip the hallucination judge; log it as missing context.

## The two judges

Fire both **in the same message**, in parallel, each as its own subagent with a clean
context. Neither sees the other's output. Each receives only the part of the package it
needs — less context, less chance of judging against the wrong criterion.

### Requirement judge

Receives: ticket, context agent output, pipeline probe, the list. **Does not receive the
diff or the code** — its judgment is against what the ticket promises, not against how it
was implemented.

For each case:

- **Anchor** — which AC or behavior does it point to? Cite `AC2` or the behavior file.
  No identifiable anchor → cut.
- **Named bug** — what plausible bug from this change does it catch, in one sentence. Two
  cases catching the same bug → the less specific one goes. A case catching a bug in
  something this change didn't touch → cut.
- **Already covered** — context marks the behavior as covered and this case adds nothing
  new to that coverage? → cut, citing the behavior.

After the list:

- **GAPS** — an AC with no case, an inherited risk with no case, or an obvious bug from
  the change that nobody catches. One per line, with the anchor.

### Hallucination judge

Receives: ticket, diff reference, the list. Has grep/code-search tooling and the
repository's own CLI (never an MCP shortcut for this).

For every concrete name a case cites — field, endpoint, parameter, message, label,
enum — search in this order and stop at the first hit:

1. in the ticket;
2. in the diff (pull the actual commit/PR diff);
3. in the touched repo's code, and in the front-end repo for any on-screen text (code
   search by exact string, or a local grep).

One line of result per name:

- found → `ok — <where>`, the name is clean;
- not found anywhere → `HALLUCINATION — <command> → 0 results`;
- couldn't search → `not verified — <reason>`, goes to MISSING CONTEXT.
  **Never accuse without a search.**

An accusation without the command and the "0 results" is invalid.

## Consolidation (the main session, no subagent)

Merge both outputs per case. The main session doesn't re-judge — it only applies:

| Situation | Verdict |
|---|---|
| Name with a proven HALLUCINATION | CUT, or REWRITE if the rest of the case has an anchor and the name can be swapped for the real one |
| No anchor, or out of this change's scope | CUT |
| Redundant or already covered | CUT, citing the case or behavior that stays |
| Anchor is fine, but the named bug doesn't match what the steps do | REWRITE |
| Passed both judges | KEEP |

**Every verdict cites a source** — the AC, the behavior file, the case that stays, or the
exact search that proved it. A verdict with no source is discarded and the case defaults
to KEEP.

## Output

One line per case, no opening prose:

```
M-03 CUT — no anchor: no AC mentions export | requirement
M-04 CUT — redundant with M-02 (same bug: total ignores a day with no data) | requirement
M-05 REWRITE — AC1 ok; cites `averageLatencyMs`, real field is `p95LatencyMs` (Metrics.ts:41) | hallucination
A-01 KEEP — AC2; catches rounding in the aggregate; names check out in the diff
M-06 CUT — already covered: behaviors/unified-scale.md, nothing new | requirement
M-07 CUT — `Save draft` button | code search "Save draft" → 0 results | hallucination
```

Then:

- **GAPS** — from the requirement judge, each with its anchor.
- **MISSING CONTEXT** — whatever kept a judge from ruling (diff absent, search failed).
- **Scoreboard** — N entered, N left, broken down by criterion.

Verdicts are a recommendation. The human decides what survives.

## Note

When the same kind of cut repeats cycle after cycle (e.g. always a case with no anchor),
the fix is to turn it into a generation constraint upstream, not another round of this
gate.
