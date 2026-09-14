---
name: terse-docs
description: Style contract for writing prose deliverables — Markdown files, READMEs, Notion pages, PR and issue descriptions, design docs, runbooks, release notes, commit bodies. Enforces result first, unordered bullets over paragraphs, no walls of text, simple words, and hard length budgets. Use before or while writing or editing any document, and when asked to "write it up", "document this", or "draft a PR description".
argument-hint: "[paths...]"
---

## Terse Docs

**A doc is read by someone in a hurry.** Every sentence that does not change what they do is a sentence that hides the ones that do.

- Invoked bare — these rules govern every doc you write for the rest of the session.
- Invoked with paths — rewrite those docs to these rules now. Cut, do not add. Report the before/after line count.

### Shape

- **Result in the first line.** What it is, what it does, or what was decided. No "In this document we will…", no scene-setting.
- **Unordered bullets by default** (`-`). Numbered lists only for a real sequence — steps run in order, ranked priorities.
- **Never a wall of text.** Three lines of prose in a row is the cap; after that, break to bullets.
- **One idea per bullet, two lines max.** Nesting stops at one level. A three-deep tree means the structure is wrong.
- **Tables** when comparing 3+ things across the same axes. Not for decoration.
- **Code blocks and commands** instead of prose describing them. Show the command, not a paragraph about the command.
- **Headings are navigation.** A section with two bullets is not a section. No heading for a doc under one screen.
- **Cap a list at 7.** Longer becomes a table, or splits.
- **Link, do not restate.** If another doc owns the fact, link it in one line.
- No emoji, no ASCII art, no decorative bold, no closing summary that repeats the doc.

### Words

- Short sentences. Active voice. Present tense. Simple words.
- Numbers beat adjectives — "p95 2.4s", not "quite slow".
- State the constraint and the trade-off up front; do not bury them mid-paragraph.
- Say "Actor" not "actor" when it is the Apify concept.

**Cut on sight:** `it's worth noting`, `essentially`, `basically`, `in order to`, `please note`, `as you can see`, `we can see that`, `keep in mind`, `simply`, `just`, `leverage`, `utilize`, `robust`, `seamless`, `comprehensive`, `powerful`, `delve`, `ensure that` (→ `make sure`, or drop).

**Cut whole sections:** an Introduction that restates the title, a Conclusion, a Summary at the end, "Next steps" with no owner or action, a TOC for anything under two screens, background the reader already has.

### Budgets

| Doc | Budget |
|---|---|
| PR / issue description | ≤ 10 lines: what changed, why, how to verify |
| Commit body | ≤ 3 lines, or none — the subject is usually enough |
| README top section | one screen to first useful command |
| Design doc / RFC | one page: problem, options, decision, trade-offs. Detail goes in an appendix |
| Runbook | numbered commands only, one line of context each |
| Release notes | one bullet per user-visible change |
| Notion page | same rules; no nested-page sprawl, callouts only for a real warning |

Over budget means cut, not "split into more sections".

### Before / after

**Written**

> This document provides a comprehensive overview of the changes that were made to the authentication middleware. As you can see from the diff, we have essentially refactored the token validation logic in order to improve performance. It's worth noting that the previous implementation was performing a database lookup on every single request, which was quite slow. The new implementation leverages a cache, which should provide a significant improvement in latency.

**Ship**

> Token validation now reads from cache instead of the DB on every request.
>
> - p95 on `/api/*`: 240ms → 12ms
> - Cache TTL 60s — a revoked token stays valid up to 60s
> - Verify: `npm run bench:auth`

### Process

1. Draft.
2. Cut half. The cut is the work, not the draft.
3. Last pass — per sentence: does the reader act differently because of it? If not, delete it.
