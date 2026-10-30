# Contributing

**Rule: shared guidance changes go upstream first, then flow to forks through the upgrade path.**

1. Anything under `template/` or `.github/` changes only in this template repo, via PR.
2. Each change bumps `template/VERSION`, adds a `template/docs/CHANGELOG.md` entry (with migration notes), and is tagged `vX.Y.Z`.
3. User-data changes need an idempotent `template/migrations/X.Y.Z.sh`.
4. Fleets receive changes only via `template/scripts/upgrade.sh X.Y.Z`. Local customization goes in `manager/` (roles, overrides, local rules).
5. Adoption friction → issue or PR here, not a local patch.

## Fleet changes: classify first, then deploy safely (added 0.7.0)
These apply inside a fleet (the rules above apply to this template repo). They add to rules 1–5; nothing above changes.

**Classify every change.**
- **Template:** generic, useful to any fleet forked from this template, no owner data (prompt shape, common rules, scripts, OWNERS, schemas, layout, shared-skill mechanisms, audit checks).
- **Instance:** names the owner's bots, people, rules, schedules or data; lives in `manager/` or `bots/<slug>/`. Mixed changes are split.
- Template changes: the manager edits the template and its guidance upstream, bumps VERSION and CHANGELOG, releases via `upgrade.sh`; the builder (fleet syncer) rolls it out to every worktree.
- Instance changes: the manager proposes; after owner approval the builder applies them, asking each bot to edit only files it owns. Bot profile or prompt changes always need owner approval.

**Deploy safely.**
- Expand, then contract: add the new path first, keep the old one with dual-read until N verified runs (default 5), remove it in a separate step.
- Prompt support lands before content moves; never both in one step; copy, don't move.
- Bootstrap invariant: each bot's built-in prompt must always reach its worktree, its INDEX, the shared INDEX and the fleet-change skill, and state the gist of its hard rules so it fails safe.
- Canary on a low-impact worker; the manager and builder migrate last and act as each other's rollback operator.
- Snapshot each bot (profile, prompt, routines, memory) outside git before every change (`template/scripts/snapshot-fleet.sh`); keep a restore runbook (`template/docs/RESTORE-BOT.md`).
- One bot, one step at a time. Template releases are additive only.
