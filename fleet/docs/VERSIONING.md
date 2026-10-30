# Versioning and upgrades

Semver in `fleet/VERSION`, git tags `vX.Y.Z`. PATCH: fixes. MINOR: features (may include idempotent migrations). Breaking layout changes are called out in docs/CHANGELOG.md.

## Ownership
Everything under `fleet/`, `templates/` and `.github/` is template-owned and replaced by upgrades; files removed upstream are deleted. `local/`, `bots/`, `README.md`, `LICENSE` are yours; only migrations touch them. Roles in `fleet/roles/` are used as-is; fleet additions go in `local/roles/`. See docs/LAYOUT.md.

## Upgrading your fleet (manager, in its own worktree)
```
cd ~/bot-fleet-worktrees/<manager-slug>
git remote get-url upstream || git remote add upstream https://github.com/<owner>/bot-fleet-template.git
git fetch origin && git rebase origin/main
BOT_ROLE=manager fleet/scripts/upgrade.sh <version>
git show --stat && git push origin HEAD:main
```
`upgrade.sh`: fetches tag `v<version>` → re-runs itself from that tag → checks out `fleet/` and `.github/` → deletes template files the target removed (and legacy pre-0.4.0 paths) → runs `fleet/migrations/<v>.sh` for current < v ≤ target → creates missing fleet files → lists role-default differences → writes `fleet/VERSION` → reinstalls the hook → validates → commits with `BOT_FLEET_UPGRADE=1`.

Fleets older than 0.3.2 must upgrade to 0.3.2 first (`scripts/upgrade.sh 0.3.2`), then to 0.4.0.
The hook rejects hand edits to template-owned files; the only sanctioned deviation from common rules is a human-approved entry in `local/overrides.md`.
