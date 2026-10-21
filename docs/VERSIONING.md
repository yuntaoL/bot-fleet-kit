# Versioning and upgrades

The template uses **semver** (`VERSION` file, git tags `vX.Y.Z`).
- PATCH: doc/script fixes. MINOR: new optional features or fields. MAJOR: schema changes that need a migration.

## Ownership split
| owner | paths | on upgrade |
|---|---|---|
| template | `rules/common.md`, `rules/README.md`, `docs/`, `scripts/`, `schema/`, `migrations/`, `templates/`, `.github/` | replaced; files removed upstream are deleted |
| user | `bots/`, `shared/`, `fleet.json`, `rules/roles/` (defaults copied from `templates/rules/roles/` at adoption; upgrades only print a diff), `rules/local/`, `README.md`, `CHANGELOG.md`, `LICENSE` | never touched (only migrations may edit) |
| upgrade | `VERSION` | written by upgrade.sh |

Customize via `rules/local/` and `shared/`, never by editing template-owned files.

## Upgrading your fleet
```
git remote add upstream https://github.com/<template-owner>/bot-fleet-template.git   # once
BOT_ROLE=manager scripts/upgrade.sh <version>
```
`upgrade.sh`:
1. fetches tag `v0.2.0` from `upstream`;
2. `git checkout v0.2.0 -- <template-owned paths>` (user paths untouched);
3. deletes tracked files under template-owned paths that no longer exist in the target tag (and legacy root docs moved into `docs/`);
4. prints a diff of `templates/rules/roles/` (new defaults) vs your `rules/roles/` without changing them;
5. runs every `migrations/<version>.sh` with version > your current `VERSION` and ≤ target, in order. Migrations must be **idempotent** (safe to re-run) and handle schema bumps on user data;
6. writes the new `VERSION`, runs `validate.sh`, and commits `chore: upgrade template to 0.2.0`.
Review with `git show` and push. To undo, `git revert` the commit.

Template release and migration notes: `docs/CHANGELOG.md` (upgraded into your fleet). Your own fleet history: root `CHANGELOG.md`.

The pre-commit hook rejects hand edits to template-owned files; `upgrade.sh` commits with `BOT_FLEET_UPGRADE=1`. The only sanctioned deviation from `rules/common.md` is a human-approved entry in `rules/local/overrides.md`.
