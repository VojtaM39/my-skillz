---
name: scope-creep
description: Flag changes on a branch that nobody asked for — compares the diff against the stated scope and reports every change not traceable to it (drive-by fixes, adjacent refactors, silent scope expansion). Verifies each suspect with an adversarial subagent before accusing, and with `apply` reverts confirmed creep after saving it as a patch. Use when you want to know whether an agent added unrelated stuff to a branch, before opening or merging a PR.
argument-hint: "[scope statement] [plan=<path>] [pr=<n>] [apply]"
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
- **plan** — `plan=<path>` sets the scope source file.
- **pr** — a bare positive integer, `pr=<n>`, or a `github.com/.../pull/<n>` URL sets `pr`.
- **scopeArg** — the unrecognized remainder.

If `apply=true`, step 7 is a commitment, not a draft — do not re-litigate it at the end.

### 2. Establish the scope contract

**This step is load-bearing.** Everything downstream is judged against the contract, so a wrong contract produces a confidently wrong report. Take the first source that yields something usable:

1. `scopeArg`
2. the `plan=<path>` file
3. the PR body — `gh pr view --json title,body`
4. branch name plus commit subjects — `git log --oneline <base>..HEAD`
5. the original ask in the inherited conversation

Then, **whichever source won, union in the conversation**: scan the inherited context for follow-up asks and mid-session corrections and add them to the contract. A change the user requested in message 7 is in scope even though it appears in no plan file, PR body, or commit message. This is the single largest source of false accusations — do not skip it.

Write the contract out as an explicit bulleted list of what was asked, and carry that list **verbatim** into every agent prompt below. If no source yields anything usable, say so and ask — do not invent a contract and judge against it.

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

Assign every hunk one category:

| Category | Meaning | Creep? |
|---|---|---|
| `in-scope` | Directly implements the contract | no |
| `required-consequence` | The contract cannot ship without it — signature ripple to call sites, type fix, import update, a test updated because behavior legitimately changed | no |
| `creep-adjacent` | Same module, plausibly tempting, but the contract does not need it: an extra guard, a neighboring refactor, a rename, a new helper | yes |
| `creep-unrelated` | Different module, no dependency path to the contract: a dep bump, a lint fix elsewhere, a new util | yes |
| `creep-expansion` | Looks in-scope but does more than asked | yes |

**`creep-expansion` is the one to hunt for.** It is the most common agent failure and the only category a file-path-versus-scope check misses entirely, because the file is right and the diff reads as on-topic. It looks like: a config option nobody requested, a narrow fix generalized into a framework, error handling for cases the user never raised, an abstraction introduced for a hypothetical second call site. Ask of every on-topic hunk: *would the contract be satisfied without this?* If yes, it is expansion.

### 5. Verify every suspect — adversarially

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
Scope contract (source: arg | plan file | PR body | commits | conversation):
  - <item>
  - <item>
Reviewed: <branch> vs <base> (<N> files, <M> lines, <U> uncommitted)
Discovery: main context | <k> cluster agents
Excluded as noise: <lockfiles/generated, or none>
```

Then the findings table — only `UNRELATED` and `UNCLEAR` survivors appear; anything a verifier rated `REQUIRED` is dropped silently.

| # | File:line | Change | Category | Verdict | Disposition |
|---|-----------|--------|----------|---------|-------------|

Disposition is one of `revert`, `split to own PR`, `keep — trivial`, `ask the user`. Close with exactly one line:

`SCOPE: CLEAN` or `SCOPE: CREEP — <n> confirmed, <m> unclear`

**Scope shortfall.** The same comparison surfaces contract items with no corresponding change. That is not creep, but list it in a short closing section — it is free and it matters. Never auto-fix it; implementing missing work is not descoping.

### 7. Apply — only when `apply=true`

1. Revert `UNRELATED` verdicts only. **Never revert `UNCLEAR`** — report those and ask.
2. **Save before touching anything.** Write the hunks to be reverted to `scope-creep-reverted.patch` at the repo root and name that path in the summary. Nothing this skill removes should be unrecoverable.
3. Revert with `git apply --reverse` against that patch. Working tree only — never rewrite branch history, never force-push.
4. Run the project's build, lint, and tests, detected from the lockfile and config rather than assumed. Report pass/fail per command. A hunk that was actually load-bearing shows up here: if the build breaks, re-apply the patch, downgrade that finding to `UNCLEAR`, and say so.
5. Summarize: what was reverted, the patch path, validation results.

### When to skip

A single trivial commit, a diff that is entirely generated files, or no usable scope source at all (no arg, no plan, no PR, nothing in the conversation) — in the last case, ask for the scope rather than guessing at one.
