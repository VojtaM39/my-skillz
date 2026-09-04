---
name: scope-creep
description: Flag changes on a branch that nobody asked for — compares the diff against the scope contract (from `/work-plan`, or inferred) and reports every change not traceable to it (drive-by fixes, adjacent refactors, silent scope expansion). Verifies each suspect with an adversarial subagent before accusing, and with `apply` reverts confirmed creep after saving it as a patch. Use when you want to know whether an agent added unrelated stuff to a branch, before opening or merging a PR.
argument-hint: "[scope statement] [slug=<name>] [plan=<path>] [pr=<n>] [apply] [quick]"
context: fork
---

## Scope Creep Check

You are checking whether a branch does **only** what was asked.

This is a peer to `/staff-review`, not a replacement. Staff-review asks *is this code good*; this asks *was this code asked for*. Both pass independently: well-written code that nobody requested is still a defect — it inflates review surface, couples unrelated work into one revert unit, and buries the actual change.

### 0. Execution model — you are running in a FORKED context

The moment you end your turn, whatever text you last wrote is returned to the caller as the entire result, and your context is gone. There is no live user reading along; nothing you write mid-run reaches anyone. Narration is the primary failure mode — a stray "let me start by…" with no tool call behind it ends the run and *becomes* the report.

- **Your first action must be a tool call, not text.** No preamble.
- **Never end your turn before the report exists.** The only acceptable last message is step 6's report, plus step 7's apply summary.
- **Never launch subagents in the background.** Every `Agent` call passes `run_in_background: false`. For parallel work, batch multiple synchronous `Agent` calls into a SINGLE message — they run concurrently and your turn blocks until all return.
- **Never use the `Workflow` tool** — it always runs in the background.

### 1. Parse invocation arguments

Your raw arguments are between the markers below. If you see the literal placeholder `<dollar>ARGUMENTS` (no substitution), read the args from the user's invocation message in your conversation context instead.

`<ARGS>$ARGUMENTS</ARGS>`

Parsing is **silent** — reason it out and carry the result forward. Do not write it as a message; text with no tool call behind it ends the run. The parsed values get echoed in the step 6 report header, where the caller will actually see them.

Tokenize by whitespace, strip recognized tokens, and treat **everything left over, rejoined, as the scope statement**:

- **apply** — `apply=true` if any token equals "apply" exactly (case-insensitive). `applying` / `--apply` do not match.
- **slug** — `slug=<name>` names the unit of work in the repo's store (step 2) to judge against.
- **plan** — `plan=<path>` sets an explicit scope source file.
- **pr** — a bare positive integer, `pr=<n>`, or a `github.com/.../pull/<n>` URL sets `pr`.
- **quick** — `quick=true` if any token equals "quick". Skips step 5's verification fan-out: suspects are reported unverified, and `apply` is refused. For mid-development checkpoints, where drift is cheap to undo.
- **scopeArg** — the unrecognized remainder.

If `apply=true`, step 7 is a commitment, not a draft — do not re-litigate it at the end. `quick` and `apply` together is an error: say so and run as `quick` without applying.

### 2. Establish the scope contract

**This step is load-bearing.** Everything downstream is judged against the contract, so a wrong contract produces a confidently wrong report.

**Look for a unit of work first.** Units live outside the repo, in a store keyed by the repo path — resolve it before looking:

```bash
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
if GIT_COMMON=$(git rev-parse --git-common-dir 2>/dev/null); then
    REPO_ROOT="$(dirname "$(cd "$GIT_COMMON" && pwd)")"
else
    REPO_ROOT="$PWD"
fi
WORK_DIR="$CLAUDE_DIR/work/$(printf %s "$REPO_ROOT" | tr / -)"
```

Read `$WORK_DIR/*/scope.md` and match frontmatter `branch:` against `git branch --show-current`, or take `slug=` if given. A unit found this way is authoritative — it is a contract the user approved before the code existed, which no other source can claim.

The **effective contract** is the unit's live `In scope` items (`S<n>`) plus its live amendments (`A<n>`), minus anything an amendment marked superseded. `A` items count exactly like `S` items — that is the entire purpose of `/scope-amend`. The `Non-goals` section is part of the contract too, and a strong one: a change matching a non-goal is confirmed creep and needs no verification in step 5.

If several units match the branch, list them and ask. Do not merge two contracts.

**With no unit**, fall back to the first source that yields something usable:

1. `scopeArg`
2. the `plan=<path>` file
3. the PR body — `gh pr view --json title,body`
4. branch name plus commit subjects — `git log --oneline <base>..HEAD`
5. the original ask in the inherited conversation

In the fallback case, **union in the conversation**: scan the inherited context for follow-up asks and mid-session corrections and add them to the contract. A change the user requested in message 7 is in scope even though it appears in no PR body or commit message. This is the largest source of false accusations in the fallback path. (With a unit, this is *not* a fallback — an ask made in conversation and never amended into the contract is a legitimate finding. Report it as `unamended` rather than creep, and suggest `/scope-amend`.)

Carry the contract **verbatim, with its IDs**, into every agent prompt below. If no source yields anything usable, say so and point at `/work-plan` — do not invent a contract and judge against it.

### 3. Gather the diff

Work in the local tree; that is the primary case.

- **Base:** the PR base if a PR exists, else `origin/HEAD`, else `git merge-base HEAD origin/main` (`origin/master` if that is the default).
- **Committed:** `git diff <base>...HEAD` (three-dot).
- **Uncommitted:** `git diff` and `git diff --cached` — report these separately in the header; they are often where creep hides.
- **Remote-only case:** `pr` given and you are not inside the matching repo (`gh repo view --json nameWithOwner`) → `gh pr diff <n>`.

Count changed files and changed lines here — step 4 gates on them.

**Exclude from judgement and list once as noise:** lockfiles, generated and vendored files, and pure formatter reflow of lines the change already touched. These are tooling consequences, not decisions, and flagging them trains the user to ignore the report.

### 4. Discovery — classify every hunk

Gate on the counts from step 3:

- **≤10 files and ≤800 lines** — classify in this context.
- **Above either threshold** — cluster the changed files by module or directory (cap 5 clusters), then one discovery `Agent` per cluster, all batched into a single parallel message. Give each the contract verbatim plus its file list and the hunks for its files; tell it not to re-derive the diff. Merge and dedupe the returned suspects.

Assign every hunk one category, and for anything not creep, **name the contract ID it traces to** (`S2`, `A1`). A change that traces to no ID is a suspect by definition; that is what the IDs are for.

| Category | Meaning | Creep? |
|---|---|---|
| `in-scope` | Directly implements the contract | no |
| `required-consequence` | The contract cannot ship without it — signature ripple to call sites, type fix, import update, a test updated because behavior legitimately changed | no |
| `creep-adjacent` | Same module, plausibly tempting, but the contract does not need it: an extra guard, a neighboring refactor, a rename, a new helper | yes |
| `creep-unrelated` | Different module, no dependency path to the contract: a dep bump, a lint fix elsewhere, a new util | yes |
| `creep-expansion` | Looks in-scope but does more than asked | yes |

**`creep-expansion` is the one to hunt for.** It is the most common agent failure and the only category a file-path-versus-scope check misses entirely, because the file is right and the diff reads as on-topic. It looks like: a config option nobody requested, a narrow fix generalized into a framework, error handling for cases the user never raised, an abstraction introduced for a hypothetical second call site. Ask of every on-topic hunk: *would the contract be satisfied without this?* If yes, it is expansion.

### 5. Verify every suspect — adversarially

**Skip this step entirely when `quick=true`** — report suspects as `UNVERIFIED` and say so in the header. Also skip verification for any suspect that matches a stated non-goal: the user already ruled it out, so there is nothing to refute.

One `Agent` per suspect, all batched into a single parallel message. Cluster suspects that share a root cause into one call — five agents re-reading one file to confirm five symptoms of one decision cost five times what one agent does. Pass `effort: 'low'` for bounded single-file checks; keep the default when the claim spans subsystems.

The framing is deliberately adversarial. The expensive error here is the false accusation: a wrong revert destroys real work, while a missed nit costs one line of the report. So make each verifier defend the change.

Hand each verifier its evidence inline — it starts blank and must not re-derive the diff:

```
Stated scope contract:
<the bulleted contract from step 2, verbatim>

Claim: <file:line> is NOT required by that contract.

Hunk:
<the hunk, inline>

Your job is to REFUTE this claim. Find the concrete reason this change is
required — a caller that breaks without it, a type error it fixes, a test it
unblocks, a runtime path named in the contract that needs it. Read the actual
code; do not reason from the hunk alone. Do not re-derive the diff or detect
the branch. Do not modify any file — this is read-only.

If you cannot find such a reason, the claim stands.

VERDICT: REQUIRED | UNRELATED | UNCLEAR
EVIDENCE: <file:line references, or why you found nothing>
```

Saying "read-only" is not enough — verifiers have edited files after being told not to. Once they return, run `git status --porcelain`. If anything is newly dirty, revert it (`git checkout -- <paths>`), re-verify any suspect whose evidence came from a touched file, and say in the report that it happened.

### 6. Report

Open with the header, so the caller can see what was judged against:

```
Unit: <slug> (<resolved path to scope.md>) | none — contract inferred from <source>
Effective contract:
  - S1 <item>
  - A1 <item, amended <date>>
  - (S3 superseded by A2)
Non-goals: <list>
Reviewed: <branch> vs <base> (<N> files, <M> lines, <U> uncommitted)
Discovery: main context | <k> cluster agents
Verification: <n> agents | skipped (quick)
Excluded as noise: <lockfiles/generated, or none>
```

Then the findings table — only `UNRELATED`, `UNCLEAR`, and (in quick mode) `UNVERIFIED` survivors appear; anything a verifier rated `REQUIRED` is dropped silently.

| # | File:line | Change | Category | Verdict | Traces to | Disposition |
|---|-----------|--------|----------|---------|-----------|-------------|

`Traces to` is the contract ID a change was argued to serve, or `—` for none. A table full of `—` with a thin contract means the contract is the problem, not the code — say that rather than listing thirty findings.

Disposition is one of `revert`, `amend the scope` (the work is legitimate and the contract should catch up — `/scope-amend`), `split to own PR`, `keep — trivial`, `ask the user`. Close with exactly one line:

`SCOPE: CLEAN` or `SCOPE: CREEP — <n> confirmed, <m> unclear`

**Scope shortfall.** The same comparison surfaces contract items with no corresponding change. That is not creep, but list it in a short closing section — it is free and it matters. Never auto-fix it; implementing missing work is not descoping.

### 7. Apply — only when `apply=true`

Never apply in `quick` mode; unverified suspects are not grounds for reverting anything.

1. Revert `UNRELATED` verdicts only. **Never revert `UNCLEAR`** — report those and ask.
2. **Save before touching anything.** Write the hunks to be reverted to `scope-creep-reverted.patch` at the repo root and name that path in the summary. Nothing this skill removes should be unrecoverable.
3. Revert with `git apply --reverse` against that patch. Working tree only — never rewrite branch history, never force-push.
4. Run the project's build, lint, and tests, detected from the lockfile and config rather than assumed. Report pass/fail per command. A hunk that was actually load-bearing shows up here: if the build breaks, re-apply the patch, downgrade that finding to `UNCLEAR`, and say so.
5. Summarize: what was reverted, the patch path, validation results.

### When to skip

A single trivial commit, or a diff that is entirely generated files.

If there is no usable scope source at all — no unit, no arg, no PR, nothing in the conversation — stop and point at `/work-plan`. A contract reverse-engineered from the code it is meant to judge validates nothing.
