# Contributing

**Rule: shared guidance changes go upstream first, then flow to forks through the upgrade path.**

1. Anything under `fleet/` or `.github/` changes only in this template repo, via PR.
2. Each change bumps `fleet/VERSION`, adds a `fleet/docs/CHANGELOG.md` entry (with migration notes), and is tagged `vX.Y.Z`.
3. User-data changes need an idempotent `fleet/migrations/X.Y.Z.sh`.
4. Fleets receive changes only via `fleet/scripts/upgrade.sh X.Y.Z`. Local customization goes in `local/` (overrides, local rules); see "Role files" below.
5. Adoption friction → issue or PR here, not a local patch.

## Fleet changes: classify first, then deploy safely (added 0.7.0)
These apply inside a fleet (the rules above apply to this template repo). They add to rules 1–5; nothing above changes.

**Classify every change.**
- **Template:** generic, useful to any fleet forked from this template, no owner data (prompt shape, common rules, scripts, OWNERS, schemas, layout, shared-skill mechanisms, audit checks).
- **Instance:** names the owner's bots, people, rules, schedules or data; lives in `local/` or `bots/<slug>/`. Mixed changes are split.
- Template changes: come from the template repo's maintainers (PR, VERSION and CHANGELOG bump, tag). A fleet's manager that wants one opens a PR or issue on the [template repo](https://github.com/yuntaoL/bot-fleet-template); once released, the manager adopts it via `upgrade.sh` and the builder (fleet syncer) rolls it out to every worktree.
- Instance changes: the manager proposes; after owner approval the builder applies them, asking each bot to edit only files it owns. Bot profile or prompt changes always need owner approval.

**Deploy safely.**
- Expand, then contract: add the new path first, keep the old one with dual-read until N verified runs (default 5), remove it in a separate step.
- Prompt support lands before content moves; never both in one step; copy, don't move.
- Bootstrap invariant: each bot's built-in prompt must always reach its worktree, its INDEX, the shared INDEX and the fleet-change skill, and state the gist of its hard rules so it fails safe.
- Canary on a low-impact worker; the manager and builder migrate last and act as each other's rollback operator.
- Snapshot each bot (profile, prompt, routines, memory) outside git before every change (`fleet/scripts/snapshot-fleet.sh`); keep a restore runbook (`fleet/docs/RESTORE-BOT.md`).
- One bot, one step at a time. Template releases are additive only.

## Role files are template-owned copies (added 0.9.0)
- `fleet/roles/<role>.md` are upstream-owned and used as-is (no per-fleet copies since 0.10.0). Put fleet-specific role additions in `local/roles/<role>.md`, read right after the fleet role; `validate.sh` warns when a `local/roles/` file is just a copy of the fleet role.
- Fleet-specific role additions go in `local/roles/<role>.md` (optional; read right after the role file). Fleet-wide local rules stay in top-level `local/rules/*.md`; human-approved deviations from common rules stay in `local/overrides.md`.
- A role addition that would help any fleet is a template change: open a PR or issue on this template repo instead.
- Fleet-specific tooling (for example a journal/log script and where detailed logs live) stays instance: name it in `local/rules/*.md` so common rule 14 can point to it.

## Template branches start from current main (added 0.9.0)
- Cut every template change branch from a fresh clone of the template repo at current `origin/main` (`git clone ... && git checkout -b <branch> origin/main`), never from an older local checkout or a previous release branch. A stale base makes the PR conflict with releases merged since.
- Before opening or updating the PR, `git fetch` and confirm `git merge-base --is-ancestor origin/main HEAD`; if not, merge `origin/main` (no force-push) and rerun `selftest.sh`.
