---
name: terse-comments
description: Style contract for writing code comments, JSDoc, and docstrings — the default is zero comments, and a comment only earns its line if it carries a fact the code cannot. Use before or while writing or editing any comment, and when asked to "document this code" or "add comments". For judging comments that already exist across a codebase, use comment-audit instead.
argument-hint: "[paths...]"
---

## Terse Comments

**Default: no comment.** Most comments an agent writes did not need to be written — the code already says what it does. A comment is worth its line only when it says something the code *cannot*.

- Invoked bare — these rules govern every comment you write for the rest of the session.
- Invoked with paths — apply them to those files now: delete and trim comments, change no executable line.

### The gate

Write the comment only if it passes all three:

1. **Delete test** — delete it. Does a reader now have to guess, re-derive, or open another file? If nothing is lost, do not write it.
2. **Code test** — can the fact live in a name, a type, or a named constant instead? Put it there and write no comment.
3. **Halve test** — cut it in half. Any fact gone? If not, ship the half.

### What earns a comment

- **Why** — the reason for a non-obvious choice, or the alternative that was rejected.
- **External quirk** — third-party, browser, or API behavior the code works around.
- **Invariant or ordering** — "must run before X", what a counter actually counts, a guarantee callers rely on.
- **Workaround** — plus the condition that lets it be deleted.
- **Provenance** — where a magic number, fixture, or vendored block came from.
- **Actionable TODO** — names a concrete action. Musing is not a TODO.

Nothing else. Not *what*, not *how*, not a summary of the function below it.

### Shape

- One line. Two only if the fact needs two. Never a paragraph.
- Fragment beats sentence. Drop `This function`, `We`, `Note that`, `Here we`.
- Proper English, capital, full stop — but short and factual beats stylish.
- Sits on the thing it describes, not three lines above it.
- JSDoc documents only what the signature cannot. `@param userId The user ID` is noise; a type is not a description.
- Never write: section banners and dividers, commented-out code, changelog notes (`added in PR #123` — git knows), attribution, or an explanation of your own edit aimed at the reviewer. Edits are explained in the PR, not in the file.

### Before / after

| Written | Ship |
|---|---|
| `// Increment the counter` above `counter += 1` | nothing |
| `/** Fetches a user by ID. @param userId The user ID @returns The user */` | nothing — the signature says it |
| `// We use a Map here because it is faster than an array for lookups, which matters a lot because this code runs on every single request` | `// Array lookup here is O(n) per request.` or nothing |
| `// Set the timeout to 30 seconds` above `TIMEOUT_MILLIS = 30_000` | `// Upstream gateway drops the connection at 35s.` or nothing if not needed |
| `// ---------- Helpers ----------` | nothing |
| `// TODO: maybe refactor this someday` | nothing, or `// TODO: drop once the v2 endpoint ships.` |
| `// Retry once` above `retry(1)` | `// S3 returns 503 on the first write after bucket create.` or nothing |
| `// Changed from filter to find per review feedback` | nothing |

### Self-check before you finish

```bash
git diff -U0 | grep -E '^\+[[:space:]]*(//|#|\*|/\*|<!--)'
```

Read every added comment and apply the delete test to it. Expect to delete most of them. More than roughly one comment per 100 new lines means you are over — justify each one or cut it.
