# Versioning and upgrades

The template uses **semver** (`VERSION` file, git tags `vX.Y.Z`).
- PATCH: doc/script fixes. MINOR: new optional features or fields. MAJOR: schema changes that need a migration.

## Ownership split
| owner | paths | upgrades |
|---|---|---|
| template | `scripts/`, `schema/`, `migrations/`, `templates/`, `AGENT_GUIDE.md`, `RESTORE.md`, `VERSIONING.md`, `CONTRIBUTING.md`, `.github/` | replaced by upgrade |
| user | `bots/`, `shared/`, `fleet.json`, `README.md`, `CHANGELOG.md`, `VERSION` (written by upgrade) | **never touched** by checkout; only migrations may edit them |

Don't edit template-owned files in your fleet repo; put customizations in `shared/` (e.g. `shared/RULES.local.md`).

## Upgrading your fleet
```
git remote add upstream https://github.com/<template-owner>/bot-fleet-template.git   # once
BOT_ROLE=manager scripts/upgrade.sh 0.2.0
```
`upgrade.sh`:
1. fetches tag `v0.2.0` from `upstream`;
2. `git checkout v0.2.0 -- <template-owned paths>` (user paths untouched);
3. runs every `migrations/<version>.sh` with version > your current `VERSION` and ≤ target, in order. Migrations must be **idempotent** (safe to re-run) and handle schema bumps on user data;
4. writes the new `VERSION`, runs `validate.sh`, and commits `chore: upgrade template to 0.2.0`.
Review with `git show` and push. To undo, `git revert` the commit.

Upstream release notes and migration notes live in `CHANGELOG.md` of the template repo.
