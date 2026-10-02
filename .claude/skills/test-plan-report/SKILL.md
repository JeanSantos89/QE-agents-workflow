---
name: test-plan-report
description: >
  Analyzes the latest test plan/execution record (the cycle's evidence file, or its
  working diary) and returns, as chat text, the fields needed for a standard QA report
  (general identification, scope, test environment, strategy, acceptance criteria,
  observations and risks). Invoke when asked to fill out a test plan report from an
  existing test file.
---

# Test Plan Report

Produces, as chat text (never as a written file), the fields of a standard QA report
template, extracted from an existing test plan/execution record.

## 1. Locate the source file

- If the user already attached or referenced a test plan file in this conversation (an
  evidence file, a working diary, any markdown record), use the most recently mentioned
  one.
- Inside an active test cycle, the default source is that cycle's own working diary.
- If no file was shared or referenced, **ask** which file to use before proceeding. Don't
  invent content.

## 2. Analyze the file

Read the file in full (every page, if a PDF) and extract:

- Name of the suite/feature tested and the execution period (case dates).
- Ticket(s) referenced.
- Environment the tests ran in (staging/production, URL).
- Developer(s) responsible for the fix/feature, when mentioned in comments or linked
  merge/pull requests.
- Overall stats (total cases, passed/blocked/failed).
- Acceptance criteria / expected behavior — extracted from the expected result (the
  oracle) of the key cases (happy path, cases citing an explicit AC).
- Bugs, discrepancies, risks and observations — cases marked "bug", "finding",
  "discrepancy", "risk", "note", "limitation", "gap", a blocked case with a reason, etc.

## 3. Reply in chat with this exact template

Fill every field with what was extracted. If a field can't be filled confidently from the
file, leave it blank (don't invent) and flag it with `(not found in the file)`.

```
General identification
Author (QA/Analyst): {{name}}
Developer responsible: {{extracted from linked MRs/PRs/comments, or "(not found in the file)"}}
Creation date: {{report/execution date}}

Overview and scope
{{short summary: what the suite covers, how many cases, feature/ticket context}}

Test environment
URL/Endpoint: {{environment + URL}}
Browser: {{browser + version}}
Ticket: {{one or more ticket keys}}

Test strategy
{{how the suite was organized — case groups/sections, MVP vs. regression, manual vs. automated, etc.}}

Acceptance criteria / expected behavior
{{objective list of the ACs covered, extracted from the key cases' expected result}}

Observations and risks
{{list of bugs/discrepancies/risks found, one per line, citing the case id for traceability}}
```

## Rules

- Always as chat text — never write this to a file unless the user explicitly asks.
- Don't over-summarize "Observations and risks": every relevant bug/discrepancy from the
  file should appear as its own item, with its case id for traceability.
- If the file covers more than one ticket, list all of them under "Ticket" and reflect
  that in the scope.
- Don't confuse "Developer responsible" with who executed the test (the report's author)
  — those are different roles even when the same person fills both elsewhere.
