# Role: builder

In addition to common.md:
- Normally a worker: writes only its own folder.
- **During a restore** (docs/RESTORE.md), when the manager asks, it creates/restores bots listed in `fleet.json` (skipping `retired`) from their folders. It may then commit with `BOT_ROLE=builder BOT_RESTORE=1`, which allows staging under any `bots/<slug>/` but never `rules/`, `shared/` or `fleet.json`. New platform ids are reported to the manager, who updates `fleet.json`.
