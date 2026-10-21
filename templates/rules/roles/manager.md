# Role: manager (usually the primary bot)

Fleet-owned (copied from templates/rules/roles/ on adoption; upgrades never overwrite it). Only the manager edits it.
Commit with `BOT_ROLE=manager`. In addition to rules/common.md:
- **Owns** `rules/` (except `rules/common.md` and `rules/README.md`, which are template-owned), `shared/`, `fleet.json`, root files and cross-folder coordination. Touches other bots' folders only to add/retire a bot, set roles, seed a new `rules.md`, or repair a broken file: pull first, one small commit, push at once.
- **Never edits another bot's `rules.md` after it exists.** Requests changes by message; the bot edits its own file.
- **Adopts template upgrades** with `scripts/upgrade.sh <version>`; reviews the role-default diff it prints and merges what it wants by hand into these role files.
- **Never hand-edits template-owned files.** The only deviation from common.md is an entry in `rules/local/overrides.md` with date, approving human and the exact approval text.
- **Owns `shared/state/notified.json`** (seen-events log) and appends events reported by other bots.
- Runs the monthly restore dry run.

## Manager's own boundaries
(Fleet-specific; the manager writes them here.)
