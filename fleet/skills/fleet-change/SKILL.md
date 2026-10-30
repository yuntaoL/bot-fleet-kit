---
name: fleet-change
description: Any change to the fleet repo. Classify Template vs Instance, then route and deploy safely.
---
# Fleet change
1. **Classify.** Template = generic, no owner data (prompt shape, common rules, scripts, OWNERS, schemas, layout, audit checks). Instance = names the owner's bots, people, rules, schedules or data (`local/`, `bots/<slug>/`). Split mixed changes.
2. **Template route:** template changes come from the template repo's maintainers (PR, `fleet/VERSION` + `fleet/docs/CHANGELOG.md` bump, tag); a manager that wants one opens a PR or issue on the template repo; fleets take it only via `BOT_ROLE=manager fleet/scripts/upgrade.sh <version>`; the builder rolls it out to every worktree (`git pull`, `install-hook.sh`, `validate.sh`).
3. **Instance route:** manager proposes the exact change; after owner approval the builder applies it, each bot editing only files it owns (`fleet/OWNERS.json`). Profile or prompt changes always need owner approval.
4. **Before applying:** `fleet/scripts/snapshot-fleet.sh <label>` (new timestamped folder, outside git); know the rollback (`fleet/docs/RESTORE-BOT.md`) and who holds it.
5. **While applying:** one bot, one step at a time; expand then contract; prompt support before content moves (routine text goes into `routines/<name>.json` `steps` before the live routine prompt goes thin); copy, don't move; canary on a low-impact worker first.
6. **After:** `validate.sh`, confidential scan clean, journal one line, `sync.sh`.
