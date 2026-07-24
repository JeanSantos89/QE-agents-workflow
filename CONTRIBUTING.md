# Contributing

Thanks for your interest in improving this workflow. It's Markdown all the way down —
prompts with sharp boundaries — so contributing is mostly about writing clearer
instructions, not shipping code.

## Ground rules

The workflow is built against two failure modes, and contributions must respect both:

- **Never guess context.** If an agent can't find what it needs, it must say so
  explicitly (e.g. `NEEDS_LIVE_CONTEXT`, "commit not located") rather than invent it.
- **Never claim an unverified pass.** A reported PASS must be backed by the runner's
  real output.

Keep the three human hard stops (⸸) intact: approving test lists, committing code, and
committing to the memory base are decisions for a person.

## How to contribute

1. Fork the repository and create a branch from `main`.
2. Make your change — a sharper prompt, a fixed boundary, a clearer doc.
3. Keep edits focused: one concern per pull request.
4. Match the existing tone: direct, specific, no filler.
5. Open a pull request describing *what* changed and *why*.

## Reporting issues

Open an issue with enough context to reproduce or understand the problem: which agent or
step, what you expected, and what happened instead.
