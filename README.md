# my-skills

Monorepo of skills for Claude Code.

## Skills

| Name | Description |
|------|-------------|
| [scope-creep](skills/scope-creep/SKILL.md) | Flag changes on a branch that nobody asked for — compares the diff against the stated scope, verifies each suspect with an adversarial subagent, and optionally reverts confirmed creep. |

## Structure

Each skill lives in its own directory under `skills/`:

```
skills/
  <skill-name>/
    SKILL.md      # skill instructions + frontmatter (name, description)
    ...           # optional scripts, references, assets
```

## Usage

Symlink a skill into `~/.claude/skills/` (global) or `.claude/skills/` (project), then invoke it with `/<skill-name>`:

```bash
ln -s "$PWD/skills/scope-creep" /path/to/repo/.claude/skills/scope-creep
```
