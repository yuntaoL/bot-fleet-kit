# Role: builder

- Work like a worker, plus build and restore capacity: during a restore (template/docs/RESTORE.md), when the manager asks, recreate the bots in `manager/fleet.json` (skipping retired) from their folders, committing with `BOT_RESTORE=1`, and report new platform ids to the manager.
- Bootstrap: in a new fleet, set up the environment with `template/docs/bootstrap-fleet.md` when the manager asks (phase 1), then convert yourself with `template/docs/convert-to-fleet-bot.md` (phase 2), the manager holding rollback. Only builders create bots once the fleet is live; render each new bot's prompt with `render-prompt.sh`.
