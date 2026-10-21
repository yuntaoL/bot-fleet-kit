# Changelog (template)

## 0.4.0 – 2026-10-21
**Breaking layout change (migration included). Requires 0.3.2 first.**
- **Folder-owned permissions:** one owner class per tree: `template/` (upgrade only), `manager/` (manager), `bots/<slug>/` (that bot). Single source: `template/OWNERS.json`, enforced by `check-boundary.sh` and `validate.sh` (unowned or doubly-owned paths fail). New file types inside an owned folder need no permission change. See docs/LAYOUT.md.
- Template files moved under `template/` (rules, docs, scripts, schema, migrations, defaults, VERSION). Fleet files move to `manager/` (fleet.json, roles/, overrides.md, local/, shared/, CHANGELOG.md). Root keeps only README.md, LICENSE (manager) and .github/ (template).
- common.md shortened: permissions are just "write only under paths OWNERS.json grants your role"; the 10 lessons kept as one-liners.
- **Worktrees:** `template/scripts/worktree.sh <slug>|--all` gives every bot (manager too) its own worktree at `<parent>/bot-fleet-worktrees/<slug>` (branch `wt/<slug>` tracking origin/main, per-worktree `fleet.bot`/`fleet.role`). Fixes shared-tree problems: stray untracked files breaking rebases, commits landing mid-run.
- **Sync loop:** `template/scripts/sync.sh` = add own paths → commit if changed → fetch → rebase origin/main → push HEAD:main → retry.
- Branch upstream fixed (`branch.main.merge` set to a single refs/heads/main) by bootstrap/worktree.sh; `upstream` remote set to `--no-tags`.
- Hook is now a wrapper that runs the current worktree's check-boundary.sh (`install-hook.sh`).
- Schemas: routine `status` optional (`enabled` allowed); state `open` items are bot-defined objects.
- profile.json `role` removed (fleet.json is the authority).
- Migration `0.4.0.sh`: moves files idempotently, rewrites bootstrap prompts and old repo paths in bot files to each bot's worktree. Old migrations (≤0.3.0) dropped.
- Upgrade: from 0.3.2, `BOT_ROLE=manager scripts/upgrade.sh 0.4.0`; afterwards `template/scripts/worktree.sh --all`.

## 0.3.2 – 2026-10-21
- upgrade.sh: finds the target's upgrade script at `template/scripts/upgrade.sh` (0.4.0 layout) or `scripts/upgrade.sh`. **Stepping stone: fleets must be on 0.3.2 before upgrading to 0.4.0.**
- No migration. Upgrade: `BOT_ROLE=manager scripts/upgrade.sh 0.3.2`.

## 0.3.1 – 2026-10-21
- check-boundary.sh: the manager may replace a `bots/<x>/rules.md` that is still the untouched starter (seeding). Previously the 0.3.0 migration created starters and then nobody but the bot could seed them. Once a bot edits its file, only it can change it.
- No migration. Upgrade: `BOT_ROLE=manager scripts/upgrade.sh 0.3.1`.

## 0.3.0 – 2026-10-21
- **Rule layers** (rules/README.md): common (template, upgrade-only) > overrides (`rules/local/overrides.md`, human-approved entries with date/approver/exact text) > role (`rules/roles/`, now **fleet-owned**, manager-only) > bot (`bots/<me>/rules.md`, bot-owned). User's direct instruction beats all; lower layers only add/tighten.
- Role defaults moved to `templates/rules/roles/`; copied on adoption; upgrades print a diff, never overwrite. Manager boundaries now live in `rules/roles/manager.md`.
- `rules/common.md`: 10 genericized lessons (write-through bookkeeping, notification dedupe via `shared/state/notified.json`, ephemeral platform state, compaction, agent messaging, target machine, confidential categories, outbound approval, single owner for recurring checks, pause-when-idle).
- check-boundary.sh: template-owned files only via upgrade (`BOT_FLEET_UPGRADE=1`); `bots/<x>/rules.md` modifiable only by bot x (others may only create).
- validate.sh: rules/README.md, role files, overrides entry fields, rules.md for every non-retired bot.
- Bootstrap prompt now includes `bots/<me>/rules.md` and precedence.
- Migration `0.3.0.sh`: keeps existing rules/roles/, adds missing defaults, overrides.md, notified.json, starter rules.md, updates bootstrap prompts, fixes profile.json trailing newlines.
- Upgrade: `BOT_ROLE=manager scripts/upgrade.sh 0.3.0`. After upgrading, move any fleet-specific manager boundaries into `rules/roles/manager.md`.

## 0.2.0 – 2026-10-21
**Breaking (migration included).**
- Two-layer rules: `rules/common.md` + `rules/roles/{manager,builder,worker,retired}.md` (template-owned) and user-owned `rules/local/` overlay (manager-only).
- fleet.json schemaVersion 2: `role` is `manager|builder|worker|retired`; `manager` boolean removed; `role` also in each profile.json.
- check-boundary.sh: only `BOT_ROLE=manager` may stage `rules/`, `shared/`, `fleet.json`; `retired` read-only; `builder` + `BOT_RESTORE=1` may stage any `bots/` during a restore.
- Bootstrap prompt snippet at the top of `templates/bot/instructions.md`.
- Docs moved to template-owned `docs/` (ADOPTION, AGENT_GUIDE, RESTORE, VERSIONING, CONTRIBUTING, CHANGELOG) so they upgrade; root README/CHANGELOG are now fleet-owned (`templates/fleet/`).
- upgrade.sh deletes files removed from template-owned paths (and legacy root docs).
- validate.sh: checks rules files, exactly one manager, profile/fleet role match.
- Migration `0.2.0.sh`: roles (primary/manager:true → manager, status retired → retired, others → worker, builder kept), schemaVersion 2, fleet README/CHANGELOG, rules/local/.
- Upgrade: `BOT_ROLE=manager scripts/upgrade.sh 0.2.0`.

## 0.1.2 – 2026-10-21
- upgrade.sh: re-executes the **target** version's upgrade.sh after fetching, so new template-owned paths (e.g. CONTRIBUTING.md in 0.1.1) are picked up. Forks that ran 0.1.1 with the 0.1.0 script were missing CONTRIBUTING.md; upgrading to 0.1.2 restores it.
- No migration. Upgrade: `BOT_ROLE=manager scripts/upgrade.sh 0.1.2`.

## 0.1.1 – 2026-10-21
Fixes from the first real adoption (friction log):
- README: full step-by-step **Adoption guide** and **Update procedure**.
- bootstrap.sh: checks git identity, adds `upstream` remote (arg), installs jsonschema, commits fleet.json as manager; idempotent.
- AGENT_GUIDE: Roles (primary/manager, builder, worker, retired) and "Adding a bot" procedure.
- CONTRIBUTING.md: upstream-first rule. Added to template-owned paths.
- upgrade.sh: tolerates existing local tag; includes CONTRIBUTING.md; safer staging.
- Migration `0.1.1.sh`: ensures `owner`/`templateVersion` in fleet.json (idempotent).
- Upgrade: `BOT_ROLE=manager scripts/upgrade.sh 0.1.1`.

## 0.1.0 – 2026-10-21
- Initial template: AGENT_GUIDE, RESTORE, schemas (fleet, profile, state, routine), bot skeleton, boundary hook, validate, upgrade, bootstrap, CI.
