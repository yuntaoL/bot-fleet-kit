# bot-fleet-template

A git-backed pattern for **backing up and restoring a fleet of AI assistant bots**.

**Why:** if your assistant account or platform disappears, your bots' instructions, routines and memory go with it; and chat context gets compacted, so bots forget. Here the repo is the durable copy, each bot re-reads its rules and state from files on every run, and permissions follow the folder structure.

## Layout (details: [template/docs/LAYOUT.md](template/docs/LAYOUT.md))
```
template/      template-owned (upgrade only): rules/common.md, OWNERS.json, docs, scripts, schema, migrations, defaults
manager/       manager-owned: fleet.json, roles/, overrides.md, local/, shared/, CHANGELOG.md
bots/<slug>/   owned by that bot
README.md, LICENSE (manager) · .github/ (template)
examples/      template-owned: shareable bot packages (tracker, notes-keeper)
```

## Examples
Ready-made, generic bots in the `bots/<slug>/` layout: [examples/](examples/README.md). Add one with `BOT_ROLE=manager template/scripts/add-example.sh <example> <slug> [name] [platform-id]`, fill the remaining `<placeholders>`, validate and commit.

## Adoption (summary; full steps in [template/docs/ADOPTION.md](template/docs/ADOPTION.md))
1. *Use this template* → **Private** repo; clone to the shared bot machine; set git identity.
2. `template/scripts/bootstrap.sh <this-template-url>`; `git push`.
3. Add bots to `manager/fleet.json`, seed `bots/<slug>/`, then `template/scripts/worktree.sh --all`.
4. Put the bootstrap prompt (`template/defaults/bot/instructions.md`) at the top of every bot's instructions.

## Update procedure
```
cd ~/bot-fleet-worktrees/<manager>      # the manager's own worktree
git fetch origin && git rebase origin/main
BOT_ROLE=manager template/scripts/upgrade.sh <version>
git show --stat && git push origin HEAD:main
```
See [template/docs/VERSIONING.md](template/docs/VERSIONING.md); guidance changes go upstream first ([CONTRIBUTING](template/docs/CONTRIBUTING.md)).

Restore: tell a fresh bot **"Clone <repo> and follow template/docs/RESTORE.md."** · MIT licensed.
