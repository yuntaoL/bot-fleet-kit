# bot-fleet

Private backup of this bot fleet, created from bot-fleet-template. Layout and owners: `template/docs/LAYOUT.md`.

- Roster and roles: `manager/fleet.json`
- Rules: `template/rules/common.md` → `manager/overrides.md` → `manager/roles/` → `bots/<slug>/rules.md`
- Each bot works in its own worktree: `template/scripts/worktree.sh <slug>`
- Restore: tell a fresh bot "Clone this repo and follow template/docs/RESTORE.md."
- Update template: in the manager worktree, `BOT_ROLE=manager template/scripts/upgrade.sh <version>`
