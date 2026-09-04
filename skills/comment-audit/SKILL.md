---
name: comment-audit
description: Flag comments that should not be there — restatements of the code, stale comments that contradict it, section banners, commented-out code, and comments whose content is right but three times too long. Reports only by default; with `apply` it removes and trims them. Use when auditing comment hygiene across a codebase, a directory, or a branch diff, or before a PR where an agent has been writing the comments.
argument-hint: "[paths...] [diff] [apply] [quick]"
context: fork
---

## Comment Audit

You are judging every comment in a target set against one question: **does this comment carry information the code does not?**

If it does not, it is noise, and noise is not free — it goes stale silently, it pads the diff, and once a file is full of comments that restate the code, the one comment that encodes a real constraint stops being read. This is a hygiene pass, not a review: you do not judge the code, only what is written about it.

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

Tokenize by whitespace and strip recognized tokens:

- **apply** — `apply=true` if any token equals "apply" exactly (case-insensitive). `--apply` / `applying` do not match.
- **diff** — `diff=true` if any token equals "diff". Narrows the target set to lines the branch changed (step 3).
- **quick** — `quick=true` if any token equals "quick". Skips step 5's verification; findings are reported `UNVERIFIED` and `apply` is refused.
- **paths** — every remaining token is a path or glob. These override the default target set.

`quick` and `apply` together is an error: say so and run as `quick` without applying.

### 2. Establish the standard

The project's own rule wins over your defaults. Before auditing, read whichever of these exist and extract what they say about comments: `CLAUDE.md` and `AGENTS.md` (repo root, plus the user-level `~/.claude/CLAUDE.md` if it is in your context), `CONTRIBUTING.md`, and any `docs/style*`. Quote the operative rule in the report header, so the caller can see what they were judged against.

With no stated rule, use this default: comments explain **why**, never **what**; they are short and factual; self-documenting code gets none.

Ask the project's rule, not your taste. A codebase that mandates JSDoc on every exported symbol is not committing a violation by having it.

### 3. Resolve the target set

Default (no `paths`, no `diff`): every **tracked source file**, via `git ls-files`. Include code, `Dockerfile`, `Makefile`, shell scripts, and CI/config files that permit comments — stale build comments are among the highest-value findings and live nowhere near `src/`.

With `paths`: exactly those, recursively.

With `diff`: resolve base as the PR base if one exists, else `origin/HEAD`, else `git merge-base HEAD origin/main` (`origin/master` if that is the default), then judge **only comments on added or modified lines** of `git diff <base>...HEAD`, plus `git diff` and `git diff --cached` for uncommitted work. Report uncommitted separately in the header. In this mode a pre-existing comment three lines above the diff is out of scope — say so rather than silently widening.

**Exclude from judgement, and list once as noise:**

| Excluded | Why |
|---|---|
| `node_modules/`, `dist/`, `build/`, lockfiles, `.min.*` | not authored |
| Generated files (`@generated`, "DO NOT EDIT", codegen headers) | regenerating restores them |
| License and copyright headers, shebangs | legally or functionally load-bearing |
| Tool directives — `eslint-disable*`, `@ts-expect-error`, `@ts-ignore`, `biome-ignore`, `prettier-ignore`, `noqa`, `nolint`, `#!/`, `type:` pragmas | machine-read, not prose |
| Doc-generator source (`docs/`, `typedoc`, `sphinx` inputs) if the project publishes API docs from docstrings | the comment is the product |

Count files and comment-bearing lines here — step 4 gates on them:

```bash
git ls-files | xargs -r grep -lE '(^|\s)(//|/\*|\*|#|--|<!--)' 2>/dev/null | wc -l
```

**Vendored code is a special case, not an exclusion.** A file whose header says it is copied from upstream (or that the repo tracks for diffability against a fork) still gets audited, but every finding in it carries a `vendored` mark and defaults to *leave alone* — cleaning it costs a clean diff against the source it was copied from. Say that trade-off once in the report; do not silently drop the findings, and never apply them without asking.

### 4. Audit — classify every comment

Gate on the counts from step 3:

- **≤15 comment-bearing files** — audit in this context.
- **More** — cluster the files by directory or module (cap 6 clusters, keep test files with their own cluster), then one `Agent` per cluster, all batched into a single parallel message. Give each the standard from step 2 verbatim, its file list, and the taxonomy and keep-list below. Tell each to report `file:line`, the comment text, a category, a verdict, one sentence of why, and — for `TRIM` — the suggested shorter wording. Tell each explicitly: **read only, modify nothing.** Merge and dedupe on return.

Assign every comment exactly one category:

| Category | Looks like | Verdict |
|---|---|---|
| `stale` | Contradicts the code it sits on — describes a flag that is gone, a step the command no longer runs, a function that was renamed | REMOVE or rewrite |
| `dead` | Commented-out code, and prose about it | REMOVE |
| `restates` | Says what the next line says — `// increment counter`, `// This is a sign it is a full result` above `if (maybeFullResult)` | REMOVE |
| `banner` | `// ---- Helpers ----`, ASCII art, stage dividers, `// Run the image.` above `CMD` | REMOVE |
| `signature-echo` | JSDoc whose `@param`/`@returns` only re-spell the parameter names and types | REMOVE |
| `duplicate` | The same comment repeated in two places (two Docker stages, two test files) | keep one |
| `chatty` | First-person musing, hedging, "for now", "I'm not 100% sure how this works", TODO prose that states no action | TRIM to the load-bearing sentence |
| `verbose` | Content is real but says it two or three times, or spends four lines on one fact | TRIM |
| `misplaced` | Correct and non-obvious, but attached to the wrong thing — documents a type's field while sitting on a function, or a request while sitting on the parser | move, then TRIM |
| `why` / `quirk` / `invariant` / `provenance` | Everything below | KEEP |

**The keep list.** Do not flag these unless they are long:

- **Why, not what** — the reason a non-obvious choice was made, a cost or latency rationale, a deliberate omission.
- **External quirks** — server, browser, or markup behavior the code works around; a selector that is fragile because a third party changes it; an API that double-escapes.
- **Invariants and counter semantics** — what a field counts and when, an ordering guarantee, a "must run before X".
- **Workarounds and hotfixes** — with the condition that would let them be removed.
- **Provenance** — where a fixture, constant, magic byte, or vendored file came from.
- **Actionable TODOs** — one that names a concrete action stays; one that muses does not.

**Two tests decide the hard cases.**

1. *Delete test.* Delete the comment mentally. Does a reader now have to guess something, or read another file, or re-derive an external fact? If nothing is lost, it is `restates`.
2. *Halve test.* Cut the comment in half. Is any fact gone? If not, it is `verbose` — and the specific shape to hunt for is a **second clause that restates the first**, or a **trailing clause that narrates the line below it**. That pattern is the single most common form of comment bloat in agent-written code, and it survives casual review because every individual sentence reads as true.

Two things that are *not* grounds for flagging: a comment being long when the fact genuinely needs the words, and a comment you personally would have phrased differently.

### 5. Verify — before you claim a comment is wrong or worthless

**Skip this step entirely when `quick=true`** — report every finding as `UNVERIFIED` and say so in the header.

Not everything needs verification. Verify exactly two kinds of finding, because both make a claim about code the comment does not contain:

- every `stale` finding — you are asserting the comment contradicts reality
- every `REMOVE` on a comment that mentions anything outside the lines it sits on (another module, a caller, a flag, an external service)

Everything else — `banner`, `dead`, a comment that restates the line directly beneath it — is self-evident from the hunk and needs no agent.

One `Agent` per finding, batched into a single parallel message; cluster findings that share a file. Pass `effort: 'low'` — these are bounded, single-file checks. Adversarial framing, because the expensive error is deleting the one comment that encoded a real constraint:

```
Comment at <file:line>:
<comment text, inline>

Code it sits on:
<the surrounding lines, inline>

Claim: this comment carries no information the code does not, and can be deleted.
(For a stale finding: Claim: this comment contradicts what the code actually does.)

Your job is to REFUTE the claim. Read the actual code — the function, its
callers, the type it documents, the command it describes. Find the concrete
fact a reader would lose: an external behavior, an invariant, a reason for a
choice, a constraint enforced elsewhere. Do not reason from the snippet alone.
Do not modify any file — this is read-only.

If you cannot find such a fact, the claim stands.

VERDICT: CARRIES-INFO | NOISE | STALE-CONFIRMED | UNCLEAR
EVIDENCE: <file:line references, or why you found nothing>
```

Saying "read-only" is not enough — verifiers have edited files after being told not to. Once they return, run `git status --porcelain`; if anything is newly dirty, revert it (`git checkout -- <paths>`) and say in the report that it happened.

Drop `CARRIES-INFO` findings silently. Keep `UNCLEAR` as report-only.

### 6. Report

Open with the header, so the caller can see what was judged and against what:

```
Standard: <the operative rule, quoted> (<source file>) | default (why-not-what, short)
Target: <paths | diff <branch> vs <base> | tracked source> — <N> files, <C> comment-bearing
Discovery: main context | <k> cluster agents
Verification: <n> agents | skipped (quick)
Excluded as noise: <generated/lockfiles/directives, or none>
Vendored: <paths audited but marked leave-alone, or none>
```

Then findings, grouped **REMOVE first, then TRIM** — the caller acts on removals in one pass and reads trims one at a time:

| # | File:line | Comment | Category | Verdict | Why | Suggested |
|---|-----------|---------|----------|---------|-----|-----------|

Truncate quoted comments to one line. `Suggested` is filled for `TRIM` and `misplaced` only, and must be shorter than what it replaces. Mark vendored rows.

Close with exactly one line:

`COMMENTS: CLEAN` or `COMMENTS: <n> remove, <m> trim, <k> unclear`

**Two short closing sections, both free and both worth having:**

- **Missing** — code that genuinely needs a *why* and has none: an unexplained magic number, a silent retry, a non-obvious ordering dependency. Never write these yourself in this pass; list at most five.
- **Stale risk** — comments that are currently accurate but pinned to something volatile (a version, a dated A/B test, "as of March 2025"). Not findings; a heads-up.

If a file is wall-to-wall findings, say that the file's comment style is the problem and name the pattern once, rather than listing thirty rows of the same thing.

### 7. Apply — only when `apply=true`

Never apply in `quick` mode; unverified findings are not grounds for deleting anything.

1. Apply `REMOVE` and `TRIM` findings. **Never apply `UNCLEAR`**, and never touch a `vendored` file — report both and ask.
2. **Save before touching anything.** `git diff > comment-audit-before.patch` at the repo root if the tree is dirty, and name that path in the summary. Nothing this skill removes should be unrecoverable.
3. Edit comments only. If a removal would leave a stray blank line or a now-empty JSDoc block, clean that up; anything beyond that is out of scope. **Not one token of executable code changes** — no reformatting, no renames, no "while I was in there".
4. Verify exactly that: `git diff -U0` and confirm every changed line is a comment, a blank line, or a comment delimiter. If any non-comment line moved, revert the file and report it.
5. Run the project's build, lint, and tests, detected from the lockfile and config rather than assumed. Report pass/fail per command. A comment pass should not break anything — if it does, a delimiter was mishandled: revert and say so.
6. Summarize: counts removed and trimmed, files touched, the patch path, validation results.

### When to skip

A file with no comments, a diff that is entirely generated code, or a target set where every comment is a tool directive.

If the project's stated standard mandates the very comments you would flag, stop and say so. Auditing a codebase against a rule it deliberately does not follow produces a long report and no improvement.
