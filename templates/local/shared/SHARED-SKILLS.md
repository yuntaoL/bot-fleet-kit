---
type: shared-skills-index
updated: YYYY-MM-DD
status: stub
---
# Shared skills

The builder maintains this index. Every bot reads it at startup before its own kb/ACTIONS.md. Bots point to rows here; they never copy them. Precedence: the owner's direct instruction > bot rules and owner kb (that bot's ACTIONS.md and its kb) > this index > generic or platform-managed skills.

Location is where the skill lives: `fleet/skills/<name>`, `local/shared/skills/<name>`, or `library` when the skill is kept in the platform's global skill library outside git. Set `status: seeded` once this fleet's rows are filled in.

| Skill | When to use | Action types covered | Owner (bot slug or role that maintains the skill content) | Location |
|---|---|---|---|---|
| fleet-change | Use when a change touches the fleet repo and must be classified before anyone applies it. | repo and fleet changes | builder | `fleet/skills/fleet-change` |
| rename-bot | Use when renaming a bot display name, slug, worktree or branch, after the owner has approved the new name. | repo and fleet changes | builder | `fleet/skills/rename-bot` |
