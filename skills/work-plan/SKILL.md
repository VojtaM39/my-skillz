---
name: work-plan
description: Start a unit of work — writes `.claude/work/<slug>/scope.md` (an append-only contract of what was asked, with explicit non-goals) and `plan.md` (mutable steps and approach). Consumes an already-approved plan file when one exists instead of re-planning. Use at the start of a feature, fix, or refactor so the scope survives across sessions and `/scope-creep` has something to check against.
argument-hint: "[the ask] [slug=<name>] [from=<plan-file>]"
---

# Work Plan

Opens a **unit of work**: a feature, fix, or refactor, tracked in `.claude/work/<slug>/`. Two files with deliberately different rules:

| File | Rule | Holds |
|---|---|---|
| `scope.md` | **Append-only.** Never rewrite an item. Changes go through `/scope-amend`, which appends. | What was asked, explicit non-goals, amendment log |
| `plan.md` | Freely mutable, yours to rewrite | Approach, steps, decisions, open questions |

The asymmetry is the point. If the contract were editable, drift would silently rewrite it to match whatever got built, and `/scope-creep` would then validate code against a contract moved to fit that code. Append-only makes widening a visible, dated act.

## Invocation

The one-liner is the least convenient form. Longer asks work better as:

| Form | When |
|---|---|
| `/work-plan` (no args) | The ask is already in the conversation — messages, pasted logs, screenshots. Step 3 picks it up. |
| `/work-plan` after plan mode | `Shift+Tab` into plan mode, get a plan approved, then this. Step 3 consumes it instead of re-planning. |
| `/work-plan from=<path>` | The ask lives in a file. Inline `@file` references work too. |
| `/work-plan "<one line>"` | Small, obvious units. |

Multiline inside the prompt: `\` + `Enter` or `Ctrl+J` in any terminal, `Shift+Enter` in most. Images: drag and drop, `Ctrl+V` (not `Cmd+V`), or give a path. Images never arrive through `$ARGUMENTS` — they are message content, so read them from the conversation.

## 1. Parse arguments

`<ARGS>$ARGUMENTS</ARGS>`

If you see the literal placeholder `<dollar>ARGUMENTS`, read the args from the user's invocation message instead.

Tokenize, strip recognized tokens, and treat the remainder as **the ask**:

- `slug=<name>` — the unit's directory name. If absent, derive kebab-case from the ask (3-4 words, `fix-mongo-retry-timeout`), or from the current branch name with any `feat/`, `fix/`, `user/` prefix stripped.
- `from=<path>` — an existing plan file to consume (see step 3).

## 2. Resolve the unit

```bash
git branch --show-current
```

Check whether `.claude/work/<slug>/` already exists.

- **Exists** — do **not** overwrite. Read both files, show the user the current contract and plan status, and ask whether they want to continue this unit, amend it (`/scope-amend`), or start a new one under a different slug. Overwriting a scope contract destroys the record this whole flow exists to keep.
- **Does not exist** — proceed. Also check for other units in `.claude/work/` whose `scope.md` frontmatter names the current branch; if one exists under a different slug, say so before creating a second unit on the same branch.

## 3. Establish the ask

Take the first source that yields something usable:

1. the ask from `$ARGUMENTS`
2. `from=<path>`, if given
3. an approved plan file from this session — Claude Code's plan mode writes one under `~/.claude/plans/`; if a plan for this task was approved in the inherited conversation, **consume it rather than re-planning.** Do not make the user restate work they already approved.
4. the user's original ask in the conversation
5. nothing usable → ask. Do not invent a contract.

Whichever source won, union in follow-up asks and corrections from the conversation.

**Images are part of the ask.** A mockup, a screenshot of the failure, a diagram of the target architecture — read them and turn what they show into checkable `In scope` items, citing what you read out of them: `S2 — the empty state matches the mockup: centered icon, one-line copy, no CTA`. Write it so the contract stands alone once the image is out of context; an image is not self-documenting six sessions later, and `/scope-creep` will never see it.

## 4. Research — only if you are actually planning

If step 3 consumed an approved plan, skip this; the research is already in it.

Otherwise read enough of the codebase to write a plan that survives contact: the files involved, the existing patterns to follow, the utilities already available. Prefer `Explore` subagents for breadth. Keep this proportional — a one-file fix does not need a survey.

## 5. Write `scope.md`

Items get **stable IDs** (`S1`, `S2`, …). `/scope-creep` cites them, so a change either traces to an ID or traces to nothing — which is the whole signal.

```markdown
---
slug: <slug>
branch: <current branch>
created: <output of `date +%F`>
status: active
---

# Scope: <one-line title>

## Goal

<2-3 sentences: the problem and the intended outcome. Why, not how.>

## In scope

- **S1** — <a specific, checkable thing that must be true when done>
- **S2** — <...>

## Non-goals

- <something deliberately not being done>
- <...>

## Amendments

_None yet. Added by `/scope-amend` — never edit the sections above._
```

**Non-goals are not optional.** Name at least one, and push for the ones that are actually tempting — the neighboring refactor you can see needs doing, the adjacent bug you noticed, the generalization that would be "easy while we're here". A contract with no non-goals is unfalsifiable, and those specific temptations are exactly what `/scope-creep` will catch later. If nothing feels tempting, ask the user what they *don't* want touched.

Keep `In scope` items checkable. "Improve error handling" cannot be verified against a diff; "`fetchToken` returns a typed error instead of throwing on 401" can.

## 6. Write `plan.md`

```markdown
---
slug: <slug>
---

# Plan: <title>

## Approach

<how, and why this way over the obvious alternative>

## Steps

- [ ] <step> — `path/to/file.ts`
- [ ] <step>

## Decisions

<record as you go: what was chosen and what it ruled out>

## Noticed, not done

_Appended by `/work-do`: seen while implementing, deliberately not done._

## Open questions

<or "none">
```

Rewrite this file freely as the work evolves. Tick steps off as they land.

## 7. Ignore the directory

Ensure `.claude/work/` is ignored — append it to `.gitignore` if not already covered. These are working notes; they should not land in the PR diff, where a per-branch file accumulates in the default branch and conflicts.

## 8. Confirm the contract

Show the user the `In scope` and `Non-goals` sections and ask for a correction pass before starting work.

This is the one cheap moment to fix the contract. After this it is append-only, and every later check judges against it — so a wrong item here produces confidently wrong reports for the rest of the unit. Say plainly that amendments are how it changes from now on.

Then report the two file paths and stop. Writing the plan is not doing the work — hand off to `/work-do`, which implements the steps against the contract and resolves the unit from the branch, so it works in a later session too. Do not start implementing yourself unless the user asks.
