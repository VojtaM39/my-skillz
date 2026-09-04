---
name: work-do
description: Execute the current unit of work — reads `scope.md` and `plan.md` from the repo's unit store under `~/.claude/work/`, implements the unticked steps, and ticks them off as they land. Refuses work that traces to no contract item, pointing at `/scope-amend` instead of silently widening. Use to start or resume implementation after `/work-plan`, in this session or a later one.
argument-hint: "[slug=<name>] [next] [steps=<n,n>] [no-verify]"
---

# Work Do

Implements a unit of work opened by `/work-plan`, against its contract.

Two jobs, and the second is the one that matters: land the steps, and refuse what the contract does not cover. `/scope-creep` catches drift after the fact; this catches it before the edit exists. Both are needed, because the after-the-fact catch is the expensive one — it reverts work that was already written, reviewed, and maybe built on.

`scope.md` is not yours to touch. `plan.md` is.

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
- `next` — implement only the first unticked step, then stop and report. For driving one step at a time.
- `steps=<n,n>` — implement only these steps, by 1-based position in `## Steps`.
- `no-verify` — skip step 7's build/lint/test run. For a mid-development checkpoint.

No args means every unticked step, in order.

## 2. Resolve the unit

```bash
git branch --show-current
ls "$WORK_DIR"
```

Match `scope.md` frontmatter `branch:` against the current branch.

| Situation | Action |
|---|---|
| Exactly one branch match | That is the unit. |
| No branch match, exactly one unit with `status: active` | Use it, and say in the report which unit and that the branch did not match. `branch:` is written once at creation, so a rename or a branch cut afterwards breaks the match while the intent stays unambiguous. |
| Several branch matches, or several active units and no match | List them and ask. Never merge two contracts, never guess which one to implement. |
| No units at all | Point at `/work-plan` and stop. |

## 3. Load the contract and the plan

Read both files. Compute the **effective contract** exactly as `/scope-creep` does: live `In scope` items (`S<n>`) plus live amendments (`A<n>`), minus anything an amendment superseded. Non-goals are part of it.

Echo the effective contract and the selected steps in two or three lines, then start. The user is present and can interrupt — this is a checkpoint, not an approval gate.

If `plan.md` has an open question that blocks a selected step, ask it now. Before the code exists is the cheap moment; after is a rewrite.

## 4. Gate every step on the contract

Name the contract ID each step serves **before** implementing it. A step that traces to no live ID does not get implemented — that usually means the plan was written wider than the contract, or an amendment narrowed the contract and the plan never caught up.

Do not let one untraceable step block the run: implement the traceable steps, and report the rest as blocked with `/scope-amend` as the fix.

A step matching a **non-goal** is the harder case. Say so plainly and do not implement it, whatever the plan says. The contract outranks the plan — that asymmetry is why they are two files.

## 5. Implement

One step at a time, in plan order; the order usually encodes the dependencies.

- **Read before writing.** Follow the patterns, helpers, and naming already in the files you touch. A step written in a house style the repo does not use is a review finding even when the logic is correct.
- **The bar for every line: would the contract be satisfied without this?** If yes, it is scope expansion — `creep-expansion` in `/scope-creep`'s table, and the category it catches most often, because the file is right and the diff reads as on-topic.
- **Required consequences are in scope.** A changed signature ripples to its call sites, a type stops compiling, a test asserts behavior that legitimately changed. Do those; the contract cannot ship without them. This is not a door for adjacent cleanup.
- **Everything else you notice, you write down instead of doing.** The tempting neighboring refactor, the unrelated bug, the missing test elsewhere: one line each under `## Noticed, not done` in `plan.md`, with a `file:line`. Recorded, not fixed. If one of them genuinely blocks the step, that is a contract question — stop and offer `/scope-amend`.
- Use `Explore` subagents when a step needs reading breadth. Implementation stays in this context, where the user can see the edits.
- Do not commit or push unless asked.

If the plan's approach turns out to be wrong — an assumption about the code does not hold — rewrite `plan.md`, say what changed and why, and continue. `plan.md` is mutable; that is allowed and expected. If the **scope** has to change to proceed, stop instead.

## 6. Keep `plan.md` current as you go

After each step lands, not at the end of the run:

- tick it `- [x]`
- append to `## Decisions` when you chose between real alternatives — what you picked and what it ruled out
- append to `## Noticed, not done`

Incremental updates are what make the unit resumable: the next `/work-do`, in any session, reads the ticks and continues. Batching the write to the end of the run throws that away precisely when it is needed — an interrupted run leaves no trace of what landed.

## 7. Verify

Skip when `no-verify`.

Detect the commands from the repo rather than assuming them: package manager from the lockfile, scripts from `package.json`, lint and type config from the project's own files. Run typecheck/build, lint, and the tests covering what you touched — the full suite if it is cheap.

Report pass/fail per command with the real failure output. A step is not done because the edit was written; it is done when the checks pass. If a fix for a failure falls outside the contract, say so rather than widening to fix it.

## 8. Report

```
Unit: <slug> ($WORK_DIR/<slug>/, printed resolved) — resolved by <branch | only active unit>
Contract served: S1, A1
Steps: <n> landed, <m> remaining, <k> blocked
Verification: <command> pass | fail — <summary>
Noticed, not done: <n> logged in plan.md
```

Then, short: what changed and where (`file:line`), what is blocked and why, and any question the work raised.

Close by naming the next move — `/scope-creep quick` for a cheap checkpoint, `/scope-amend` if anything is blocked, `/staff-review` then `/scope-creep` before the PR. Do not run them yourself; each is a separate decision.

### When to stop and ask

- a selected step traces to no live contract item, or matches a non-goal
- proceeding requires the scope to change
- verification fails in a way that needs a decision rather than a fix
