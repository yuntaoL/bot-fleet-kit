# Contributing

**Rule: shared guidance changes go upstream first, then flow to forks through the upgrade path.**

1. Anything template-owned (`scripts/`, `schema/`, `migrations/`, `templates/`, `AGENT_GUIDE.md`, `RESTORE.md`, `VERSIONING.md`, `CONTRIBUTING.md`, `.github/`) is changed only in this template repo, via PR.
2. Each change bumps `VERSION` (semver), adds a `CHANGELOG.md` entry with migration notes, and is tagged `vX.Y.Z`.
3. If user data must change (schema bump), add an idempotent `migrations/X.Y.Z.sh`.
4. Fleet repos receive it only via `scripts/upgrade.sh X.Y.Z`. Never hand-edit template-owned files in a fleet repo; local customizations go in `shared/`.
5. Found friction while adopting? Open an issue or PR here, not a local patch.
