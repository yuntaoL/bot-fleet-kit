# Weekly fleet audit (manager)

Goal: the fleet's files still say what we mean, match what the bots actually do, and hold nothing they shouldn't. Run `template/scripts/audit.sh` for the mechanical part, then use judgment for the rest. Fix what's yours (manager/), ask bots by message to fix their own folders, and open a PR or issue on the template repo for template changes.

## Checklist
1. **CI and validate:** latest CI run green; `validate.sh` passes.
2. **Rules style** (docs/WRITING_RULES.md): rules that enumerate items instead of stating the principle; rules without a why; long or repetitive rule files.
3. **Consistency:** contradictions between layers; any lower layer looser than a higher one (a bot rule can only tighten); overrides missing date/approver/approval text.
4. **Stale state:** `state.json` `updatedAt` old; open items past due, waiting on nobody, or already done.
5. **Backups match reality:** each bot's live routines, memory and profile vs. `bots/<slug>/` (routines/*.json, memory.md, profile.json); routines that exist live but not in files, or vice versa.
6. **Sensitive data:** anything in the repo (including history and commit messages) the owner wouldn't want stored: secrets, personal identifiers, confidential matters. Remove going forward; rewriting history needs the owner.
7. **Scope:** bots doing work outside their job, duplicate recurring checks, or messages sent without approval.
8. **Rename drift:** the owner can rename a bot in the app without telling anyone. `template/scripts/check-names.sh` (also in `audit.sh`) compares each live display name with `fleet.json` and the registry. On a DRIFT line change nothing; the builder messages the manager with old and new names, and the manager asks the owner: full rename (rename-bot skill) or record the new display name only.
9. **Lessons worth promoting:** a lesson several bots learned belongs in a role file (manager) or common.md (upstream PR → upgrade).

## Output
A short report to the owner only if something needs them; otherwise log the audit in `manager/CHANGELOG.md`.
