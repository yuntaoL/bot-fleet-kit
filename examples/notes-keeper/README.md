# Example: Notes Keeper

A worker bot that manages an Obsidian vault on the shared bot machine.

- **Rules file:** the vault's `AGENTS.md` defines layout, templates, properties and writing style; the bot reads it every run.
- **Bookkeeping:** index pages kept current; a changelog row for every write (`Meta/Changelog.md`, weekly `Meta/Changelog/<YYYY-Www>.md`).
- **Inbox:** `00 Inbox/` folders for quick capture, filed by the daily routine (ambiguous items stay).
- **Routines:** `daily-inbox-filing` (filing, tidy recent changes, bot-folder compliance, fleet reconcile) and `weekly-vault-cleanup` (backup first, lint, proposals for anything big).
- **Fleet reconcile:** daily, the bot diffs its live routines/memory/profile against `bots/<me>/` and syncs drift.
- **Safety:** never deletes without asking, raw sources immutable, no secrets or confidential content in the vault.

Placeholders to fill: `<wt>`, `<me>`, `<manager-name>`, `<manager-id>`, `<vault-path>`, `<sync-method>`, `<sync-log>`, `<sync-restart-script>`, `<bot-folder>`, `<timezone>`, `<platform-id>`, and the schedules. You also need an `AGENTS.md` in the vault describing your layout.
