# Role: builder

- Normally works like a worker.
- During a restore (docs/RESTORE.md), when the manager asks, creates the bots in `manager/fleet.json` (skipping retired) from their folders, committing with `BOT_RESTORE=1`. Reports new platform ids to the manager.
