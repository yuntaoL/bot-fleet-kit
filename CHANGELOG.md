# Changelog

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
