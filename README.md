# my-skills

Monorepo of skills for Claude Code.

## Skills

### Scope

These four compose into one flow — see [Scope flow](#scope-flow).

| Name | Description |
|------|-------------|
| [work-plan](skills/work-plan/SKILL.md) | Start a unit of work — writes an append-only `scope.md` contract plus a mutable `plan.md`. |
| [work-do](skills/work-do/SKILL.md) | Implement the plan's steps against the contract, ticking them off as they land; refuses work that traces to no scope item. |
| [scope-amend](skills/scope-amend/SKILL.md) | Widen, narrow, or correct the scope on the record, by appending a dated amendment. |
| [scope-creep](skills/scope-creep/SKILL.md) | Flag changes not traceable to the contract; verifies each suspect adversarially and can revert confirmed creep. |

### Hygiene

| Name | Description |
|------|-------------|
| [comment-audit](skills/comment-audit/SKILL.md) | Flag comments that restate the code, contradict it, or say one fact three times; verifies before accusing and can remove and trim them. |

```bash
/comment-audit                  # every tracked source file, report only
/comment-audit src/ Dockerfile  # just these paths
/comment-audit diff             # only comments on lines this branch changed
/comment-audit quick            # skip verification, cheap checkpoint
/comment-audit diff apply       # remove and trim, then build/lint/test
```

Comments only — the apply pass asserts every changed line is a comment or blank and reverts the file if any executable line moved. Vendored files are audited but never auto-changed: cleaning them costs a clean diff against upstream.

## Scope flow

```
/work-plan "fix token expiry in auth middleware"
    -> ~/.claude/work/-Users-me-repo/fix-token-expiry/{scope.md, plan.md}

/work-do                    # implement unticked steps, tick them off
/work-do next               # or one step at a time
/scope-creep quick          # cheap checkpoint, no subagents
/scope-amend "the retry belongs in the pool, not the client"
/work-do                    # resume — picks up where the ticks left off
/scope-creep                # pre-PR gate, verified findings
/scope-creep apply          # revert confirmed creep, saved as a patch first
```

Units are stored **outside the repo** — `~/.claude/work/<repo-path-dashed>/<slug>/` — so nothing this flow writes can land in the working tree, a PR diff, or `.gitignore`. The key comes from `git rev-parse --git-common-dir`, so all worktrees of a repo share one store and same-named clones stay separate.

Only `/work-plan` needs arguments. Everything after it resolves the unit from the current branch (falling back to the single active unit), so the flow survives a new session — `slug=` is just an override for when that lookup is ambiguous.

Longer asks do not belong on the `/work-plan` command line: describe the work in normal messages, paste screenshots (`Ctrl+V`), or get a plan approved in plan mode, then run `/work-plan` bare — it reads the ask from the conversation.

`scope.md` is **append-only**; `plan.md` is freely rewritten. The asymmetry is deliberate: an editable contract gets silently rewritten to match whatever was built, which makes the creep check validate code against itself. `/scope-amend` is the only way scope changes, so widening is always dated and attributed.

## Structure

Each skill lives in its own directory under `skills/`:

```
skills/
  <skill-name>/
    SKILL.md      # skill instructions + frontmatter (name, description)
    ...           # optional scripts, references, assets
```

## Install

```bash
./install.sh                    # all skills -> ~/.claude/skills
./install.sh scope-creep        # just one
./install.sh --project ~/repo   # -> ~/repo/.claude/skills
./install.sh --list             # what's available
./install.sh --dry-run          # print, change nothing
./install.sh --uninstall        # remove this repo's symlinks
```

Skills are symlinked, so edits under `skills/` take effect with no re-install. Restart Claude Code or open a new session to pick up newly added skills, then invoke with `/<skill-name>`.
