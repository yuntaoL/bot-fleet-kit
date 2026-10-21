# Contributing

**Rule: shared guidance changes go upstream first, then flow to forks through the upgrade path.**

1. Anything under `template/` or `.github/` changes only in this template repo, via PR.
2. Each change bumps `template/VERSION`, adds a `template/docs/CHANGELOG.md` entry (with migration notes), and is tagged `vX.Y.Z`.
3. User-data changes need an idempotent `template/migrations/X.Y.Z.sh`.
4. Fleets receive changes only via `template/scripts/upgrade.sh X.Y.Z`. Local customization goes in `manager/` (roles, overrides, local rules).
5. Adoption friction → issue or PR here, not a local patch.
