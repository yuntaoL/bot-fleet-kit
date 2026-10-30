# bot-fleet

Private backup of this bot fleet, created from bot-fleet-kit. Layout and owners: `fleet/docs/LAYOUT.md`.

- Roster and roles: `local/fleet.json`
- Rules: `fleet/rules/common.md` → `local/overrides.md` → `fleet/roles/` → `bots/<slug>/rules.md`
- Each bot works in its own worktree: `fleet/scripts/worktree.sh <slug>`
- Restore: tell a fresh bot "Clone this repo and follow fleet/docs/RESTORE.md."
- Update template: in the manager worktree, `BOT_ROLE=manager fleet/scripts/upgrade.sh <version>`
