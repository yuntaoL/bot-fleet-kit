# Role: builder

- Work like a worker, plus build and restore capacity: during a restore (docs/RESTORE.md), when the manager asks, recreate the bots in `manager/fleet.json` (skipping retired) from their folders, committing with `BOT_RESTORE=1`, and report new platform ids to the manager.
