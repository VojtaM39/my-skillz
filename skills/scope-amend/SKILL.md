---
name: scope-amend
description: Widen, narrow, or correct the scope of the current unit of work by appending a dated amendment to its `scope.md` in the repo's unit store under `~/.claude/work/`. Never rewrites existing items — supersedes them on the record. Use when the work turns out to be bigger or smaller than planned, so the change is deliberate and logged instead of silent drift.
argument-hint: "[what changed] [slug=<name>] [drop=<S-id>]"
---

# Scope Amend

Scope growth is not automatically wrong — sometimes the work genuinely is bigger than it looked. The defect is **silent** growth. This skill is the ritual that turns "the agent did extra stuff" into "we decided, on record, to expand."

Amendments are **appended**. You never edit or delete an item in `In scope` or `Non-goals`; you supersede it with a new entry. The history is the artifact — a unit amended five times is telling you something about how it was estimated.

## Where units live

Units live **outside the repo**, in a store keyed by the repo path. Nothing this flow writes ever lands in the working tree, the diff, or `.gitignore` — the repo under review is not the place to keep notes about the repo under review. Resolve the store first, on every run:

```bash
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
if GIT_COMMON=$(git rev-parse --git-common-dir 2>/dev/null); then
    REPO_ROOT="$(dirname "$(cd "$GIT_COMMON" && pwd)")"
else
    REPO_ROOT="$PWD"
fi
WORK_DIR="$CLAUDE_DIR/work/$(printf %s "$REPO_ROOT" | tr / -)"
```

One unit per `$WORK_DIR/<slug>/`. The key comes from `--git-common-dir`, so every worktree of a repo resolves to the same store, and two clones sharing a basename do not collide. Report resolved absolute paths, never `$WORK_DIR` itself.

## 1. Parse arguments

`<ARGS>$ARGUMENTS</ARGS>`

If you see the literal placeholder `<dollar>ARGUMENTS`, read the args from the user's invocation message instead.

- `slug=<name>` — target unit. If absent, resolve from the current branch (step 2).
- `drop=<S-id>` — descope an existing item (`drop=S3`). Repeatable.
- the remainder — the amendment text.

## 2. Resolve the unit

```bash
git branch --show-current
ls "$WORK_DIR"
```

Match on `scope.md` frontmatter `branch:`. If several match, or none do, list what exists and ask — do not guess which contract to modify.

If no unit exists at all, say so and point at `/work-plan`. Do not create one here; a contract invented at amendment time has no baseline to amend.

## 3. Classify the amendment

Read the existing `scope.md` first, then decide which this is:

| Type | Meaning | Effect |
|---|---|---|
| `widen` | New work added to the contract | New `A<n>` item, in scope from now on |
| `narrow` | Work removed (`drop=`) | `A<n>` marks the named `S<id>` superseded; already-written code for it becomes creep |
| `correct` | An existing item was wrong or imprecise | `A<n>` restates it and supersedes the original `S<id>` |
| `non-goal` | Something explicitly ruled out mid-flight | `A<n>` adds it to non-goals |

If the amendment contradicts an existing item, it is `correct` or `narrow` — not `widen`. Name the superseded ID explicitly; an amendment that silently coexists with the item it contradicts leaves two live contracts and the next check picks one arbitrarily.

**Say when an amendment looks like rationalization.** If it arrives right after code was written that the contract did not cover, and the stated reason is "it was needed" rather than a discovery about the problem, flag that in a sentence before writing it. Legitimate: "the retry has to be in the pool, not the client — the client is constructed per-request." Rationalization: "also refactored the logger." Still write the amendment if the user confirms; just do not let it through silently.

## 4. Append it

Add to the `## Amendments` section, replacing the `_None yet._` placeholder on the first amendment. Never touch anything above that section.

```markdown
### A<n> — <date +%F> — <widen | narrow | correct | non-goal>

<what changed, in the same checkable style as the `S` items>

**Supersedes:** <S-id, or "nothing — new work">
**Why:** <what was discovered that the original contract did not know>
```

Number `A<n>` sequentially from existing amendments. `A` IDs are first-class contract items: `/scope-creep` treats an active `A` item exactly like an `S` item.

## 5. Sync the plan

Amendments change the work, so update `plan.md` — add steps for widened scope, strike steps for narrowed scope. `plan.md` is mutable; rewrite it freely.

## 6. Report

Print the resulting **effective contract**: live `S` and `A` items with superseded ones struck through, then the non-goals. That is what `/scope-creep` will judge against, so the user should see it now.

If this was a `narrow`, flag it explicitly: code already written for a dropped item is now out of scope, and the next `/scope-creep` run will report it. That is correct behavior, not a false positive — say so, so it is not a surprise.
