# Changelog (template)

## 0.9.1 – 2026-10-29
Rename support and a thin-prompt read fix. Additive; no migration.
- **Skill:** `template/defaults/fleet/skills/rename-bot/SKILL.md` (builder-owned): display name, slug/folder, worktree + branch as expand-then-contract steps (snapshot, clean-worktree check, reference grep without history, fleet.json/registry, copy then remove folder, worktree move + `branch -m` + prune, re-render, outside-git checklist for the bot itself: profile, routine prompts, skills, notes; validate, fleet-wide pull, verify, rollback). `builder.md` points to it.
- **Script:** `template/scripts/rename-bot.sh <old> <new> <refs|expand|worktree|contract> [--dry-run]` does the git parts.
- **validate.sh:** WARN (FAIL with `--pre-fleet`) when a worktree dir differs from its `fleet.bot`, WARN on branch != `wt/<fleet.bot>` or a `fleet.bot` not in fleet.json. Previously a dir named differently from its slug was skipped silently.
- **Rename drift:** `template/scripts/check-names.sh [profiles-dir]` (read-only, exit 3 on drift) compares live display names with fleet.json and the registry; `audit.sh` runs it; AUDIT.md item 8 and the skill: change nothing, builder tells the manager old and new names, manager asks the owner (full rename or display name only).
- **Schema:** optional `previousSlugs` per bot in fleet.json.
- **Thin prompt:** step 2 also reads `bots/{{SLUG}}/instructions.md` if it exists. Re-render to pick it up.
- **selftest.sh:** rename end to end (dry-run no-op, expand, worktree move, validate clean, contract) and a negative check for a mismatched worktree dir.
- Upgrade: `BOT_ROLE=manager template/scripts/upgrade.sh 0.9.1` (builder.md updates automatically if unedited).

## 0.9.0 – 2026-10-29
Role-files realign. Keeps fleets in sync with template role files so upgrades need no hand merges.
- **Role defaults:** bare `docs/...` paths fixed to `template/docs/...` (AUDIT, RESTORE, install-manager, bootstrap-fleet, convert-to-fleet-bot); roles are read from the fleet root. The manager's boundaries placeholder becomes a generic reach bullet plus a pointer to `manager/local/roles/manager.md`.
- **Common rules:** new rule 14 "Journal every run" (one place for all roles); rule 4 read order adds `manager/local/roles/<role>.md` and limits `manager/local/` to top-level files.
- **Thin prompt:** `THIN-PROMPT.tmpl` step 2 reads `manager/local/*.md` (top-level only), then `manager/roles/{{ROLE}}.md`, then `manager/local/roles/{{ROLE}}.md` if it exists. Already rendered prompts keep working; re-render to pick up the new read order.
- **upgrade.sh:** role files equal to the current or target default are copied automatically; an edited one stops the upgrade with a diff before anything changes (`BOT_FLEET_KEEP_ROLES=1` keeps it and continues).
- **validate.sh:** WARN `role drift` when `manager/roles/<role>.md` differs from the template default (FAIL under `BOT_FLEET_STRICT_ROLES=1`).
- **selftest.sh:** fails on bare `docs/` paths in role defaults; negative check for role drift.
- **Review fixes:** role defaults drop the bootstrap-phase lines (bootstrap docs are read by the owner/manager before the repo exists, not from role files); builder keeps "only builders create bots", manager keeps the one-manager/one-builder invariant. Thin prompt fail-safe reports through one channel: the manager, or the owner only if the bot is the manager or the manager is unreachable.
- **Template changes are maintainer-owned:** managers no longer propose or make template changes; a manager that wants one opens a PR or issue on the template repo (manager role, CONTRIBUTING, AUDIT, fleet-change skill, README).
- **CONTRIBUTING.md:** "Role files are template-owned copies". New section "Template branches start from current main" (fresh clone of origin/main, ancestry check before a PR). Log scripts stay instance; fleets name theirs in `manager/local/`.
- No migration. Upgrade: move local role edits to `manager/local/roles/<role>.md` and reset `manager/roles/` first (or `BOT_FLEET_KEEP_ROLES=1`), then `BOT_ROLE=manager template/scripts/upgrade.sh 0.9.0`; optionally re-render prompts.

## 0.8.0 – 2026-10-29
Bootstrap release. Additive: no files removed or renamed; existing fleets keep working without changes (new checks warn, never fail, unless opted in).
- **Two-phase bootstrap (bot-driven setup):** `template/docs/install-manager.md` (Part A phase 1 pre-fleet: names, prerequisites, create the builder with the owner's yes, delegate, exit check; Part B phase 2: manager converts itself, then supervises the builder), `template/docs/bootstrap-fleet.md` (builder environment setup; rerunnable repair guide), `template/docs/convert-to-fleet-bot.md` (snapshot → `converting` → copy memory → git-first prompt with fallback → N=5 verified runs → contract; named rollback holder). `ADOPTION.md` points to the bot-driven path; the manual path is unchanged.
- **Thin prompt template:** `template/defaults/THIN-PROMPT.tmpl` with `{{BOT_NAME}}`, `{{OWNER_NAME}}`, `{{SLUG}}`, `{{ROLE}}`, `{{WORKTREE}}`; `template/scripts/render-prompt.sh <slug>` writes `bots/<slug>/THIN-PROMPT.md` (instance) and refuses empty `owner_name` or leftover placeholders. The old `defaults/bot/instructions.md` prompt still works.
- **Schemas:** `fleet.json` gains optional `owner_name` and bot statuses `pre-fleet`, `converting`; `state.json` gains optional `bootstrap {phase, step, status, snapshot, rollbackHolder, verifiedRuns, updated}`. `init-fleet.sh` writes `"owner_name": ""` in new fleets only.
- **validate.sh:** `--pre-fleet` mode (one manager + a builder listed, every worktree present with `fleet.bot` = slug). Default mode adds: FAIL on duplicate slugs or a `bots/*/THIN-PROMPT.md` with `{{...}}`; WARN when there is no active manager or no active builder (`BOT_FLEET_STRICT_ROLES=1` makes it FAIL; planned default later), on worktree identity mismatch, and while bots are `pre-fleet`/`converting`.
- **Self-test:** `template/scripts/selftest.sh` runs both bootstrap phases end to end in throwaway repos (fake owner and bots, rerun no-op, forced rollback, negative checks); CI runs it.
- **Role defaults:** one bootstrap line added to `defaults/roles/manager.md` and `builder.md` (upgrade.sh lists them as differing; merge by hand). `AGENT_GUIDE.md` "Adding a bot" gains the render step.
- **README:** rewritten (why it exists, quick start by chat or by hand, built vs proposed).
- No migration. Upgrade: `BOT_ROLE=manager template/scripts/upgrade.sh 0.8.0`; then optionally set `owner_name` and render prompts.

## 0.7.0 – 2026-10-29
Additive release: new files and warn-only checks; nothing removed or renamed; no behavior change for existing bots.
- **Fleet changes:** `CONTRIBUTING.md` gains "Fleet changes: classify first, then deploy safely" (Template vs Instance; expand-then-contract; prompt support before content moves; canary; snapshot before every change; one step at a time; additive template releases). Default skill `template/defaults/fleet/skills/fleet-change/SKILL.md`.
- **Safety net:** `template/scripts/snapshot-fleet.sh [label]` (always a new `<YYYY-MM-DD-HHMM>[-label]` folder outside git, sha256 manifest, refuses to overwrite); `template/docs/RESTORE-BOT.md` runbook template.
- **Confidential scan:** `template/scripts/confidential-scan.sh` (patterns outside git, prints paths only). `install-hook.sh` now runs the scanner (instance copy in `manager/shared/scripts/` preferred) before `check-boundary.sh`, so rerunning it no longer drops a scanner hook. No pattern file = scanner skips.
- **Knowledge layout (opt-in, nothing reads it yet):** `template/docs/KB-LAYOUT.md`; defaults for `manager/registry/INDEX.md` + bot card `CARD.md`, `manager/shared/INDEX.md`, `bots/<slug>/kb/INDEX.md`. `init-fleet.sh` creates the two manager INDEX files only if missing. `validate.sh` adds warn-only INDEX link and kb front-matter checks.
- No migration. Upgrade: `BOT_ROLE=manager template/scripts/upgrade.sh 0.7.0`.

## 0.6.2 – 2026-10-21
- examples/tracker: optional **start time**. Requests may carry `startAt` (time) and/or `startWhen` (status trigger); full checks begin at whichever comes first, with light cached checks before that (not counted toward maxChecks). Deliveries and exceptions are always reported. Added to rules.md and the live-package-tracking skill, written as principles.
- sync.sh: with no paths, the manager now also commits its own `bots/<me>/` folder (previously only `manager/` and README.md).
- No migration. Upgrade: `BOT_ROLE=manager template/scripts/upgrade.sh 0.6.2`.

## 0.6.1 – 2026-10-21
- audit.sh rules-style check: ignores the standard precedence line ("may add or tighten, never loosen…"), lines with "e.g./such as/and similar/use judgment", and URLs; slashes no longer count by themselves. Flags only real enumerated lists: 3+ comma- or slash-separated items (a/b/c) after never/no/don't/not/without, within the same clause.
- No migration. Upgrade: `BOT_ROLE=manager template/scripts/upgrade.sh 0.6.1`.

## 0.6.0 – 2026-10-21
- **Principle-first rules.** New `template/docs/WRITING_RULES.md`: state intent and why, a few illustrative examples (never the boundary), the judgment test ("would the owner be uncomfortable seeing this stored or shared?"), concrete rules only for hard safety lines or learned failures, keep rules short.
- `template/rules/common.md` rewritten in that style: three hard lines (nothing goes out without approval; no secrets; keep out anything sensitive, private or not yours to store), fleet mechanics, and learned habits. Same obligations, fewer items.
- Role defaults (`template/defaults/roles/*.md`) and the starter `bots/<me>/rules.md` rephrased as principles. Existing fleets: upgrade.sh lists role-default differences; merge by hand.
- examples/tracker and examples/notes-keeper rules and anti-jobs rewritten as principles.
- **Audit:** `template/docs/AUDIT.md` (weekly manager checklist) and `template/scripts/audit.sh` (read-only: validate, folder/routine/state freshness, sensitive-pattern grep, heuristic for enumerating rules). CI also runs audit.sh (report only).
- No migration. Upgrade: `BOT_ROLE=manager template/scripts/upgrade.sh 0.6.0`.

## 0.5.3 – 2026-10-21
- examples/tracker: new skill `skills/live-package-tracking/SKILL.md` (source chain, public tracking-page URL patterns per carrier, known shell dead ends, reporting format); rules.md and the tracker-loop routine point to it. examples/README.md notes that `skills/` and `routines/` are the most reusable parts and can be copied alone.
- No migration. Upgrade: `BOT_ROLE=manager template/scripts/upgrade.sh 0.5.3`.

## 0.5.2 – 2026-10-21
- examples/tracker: email fallback replaced by a near-real-time **status-source chain**: carrier API (if keyed) → carrier tracking page in a real browser subagent → cached tracking site over HTTP (may lag) → carrier alerts to a bot inbox → user's email notifications (last resort). New rule: report source and scan time with every status; never wait on email when a live source works. Updated rules.md, memory.md, instructions.md, README and the tracker-loop routine.
- No migration (examples are fetched by add-example.sh, never copied into fleets). Upgrade: `BOT_ROLE=manager template/scripts/upgrade.sh 0.5.2`.

## 0.5.1 – 2026-10-21
- **examples/ never lands in a fleet.** It lives only in the template repo. upgrade.sh no longer copies `examples/` and never deletes it; if a fleet already has one (e.g. from 0.5.0 or "Use this template"), upgrade.sh and init-fleet.sh print a note so you can `git rm -r examples` by hand.
- add-example.sh fetches the example from the public template (shallow clone of tag `v<version>` into a temp dir; default version = `template/VERSION`, override with `EXAMPLE_VERSION`; repo = `TEMPLATE_URL`, else the `upstream` remote) instead of a local `examples/`.
- validate.sh checks `examples/` only in the template repo (no `manager/fleet.json`); fleets don't need it. OWNERS.json keeps `examples/**` as template-owned (read-only if present in a fleet).
- No migration. Upgrade: `BOT_ROLE=manager template/scripts/upgrade.sh 0.5.1`.

## 0.5.0 – 2026-10-21
- **Examples:** new template-owned `examples/` with two generic, shareable bot packages in the `bots/<slug>/` layout: `examples/tracker` (check-until-done queue in a private git repo, 15-min loop that pauses when idle, expiry/max checks/expected status, dedupe, results only to the requester, email fallback when a carrier blocks scripted tracking) and `examples/notes-keeper` (Obsidian vault manager: AGENTS.md rules file, index pages, changelog row per write, `00 Inbox/` filing daily, weekly cleanup, fleet reconcile). Routine prompts are templates with `<placeholders>`; routines ship `paused`.
- `template/scripts/add-example.sh <example> <slug> [name] [platform-id]` (manager): copies an example to `bots/<slug>`, fills `<me>`/`<wt>`/`<role>`/name/id, registers a worker in `manager/fleet.json`. Does not commit.
- OWNERS.json: `examples/**` owned by template. upgrade.sh: `examples` added to template paths. validate.sh: schema-checks example profiles, states and routines.
- No migration. Upgrade: `BOT_ROLE=manager template/scripts/upgrade.sh 0.5.0`.

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
