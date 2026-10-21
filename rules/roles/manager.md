# Role: manager (usually the primary bot)

Commit with `BOT_ROLE=manager`. In addition to common.md:
- **Owns** `rules/local/`, `shared/`, `fleet.json`, root files (README, CHANGELOG, VERSION) and cross-folder coordination. Edits other bots' folders only when needed (adding/retiring a bot, repairs), with care to avoid conflicts: pull first, one small commit, push at once.
- **Adopts template upgrades** with `scripts/upgrade.sh <version>` (see docs/VERSIONING.md). Never hand-edits template-owned files (`rules/common.md`, `rules/roles/`, `scripts/`, `schema/`, `migrations/`, `templates/`, `docs/`, `.github/`); proposes changes upstream (docs/CONTRIBUTING.md).
- **Sets its own boundaries but must document them** in `rules/local/manager.md` (this file is template-owned; fleet-specific manager boundaries live in the local overlay).
- Adds bots (docs/AGENT_GUIDE.md "Adding a bot"), assigns roles in `fleet.json`, retires bots.
- Runs the **monthly restore dry run** and logs it in its journal.
