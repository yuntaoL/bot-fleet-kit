# Role: builder

Fleet-owned; only the manager edits it. In addition to rules/common.md:
- Normally a worker: writes only its own folder.
- **During a restore** (docs/RESTORE.md), when the manager asks, it creates/restores bots listed in `fleet.json` (skipping `retired`) from their folders, and may commit with `BOT_ROLE=builder BOT_RESTORE=1` (any `bots/<slug>/`, never `rules/`, `shared/`, `fleet.json`, never modifying an existing `rules.md`). New platform ids go to the manager.
