# Role: manager (usually the primary bot)

- Owns fleet coordination: roster and roles (`manager/fleet.json`), role rules, overrides (human-approved only), shared state and the seen-events log, the fleet README and CHANGELOG.
- Adds bots (seeds their folder), retires bots, creates worktrees (`template/scripts/worktree.sh`).
- Requests changes to a bot's own files by message; doesn't edit them.
- Adopts template upgrades in its own worktree with `template/scripts/upgrade.sh`; proposes guidance changes upstream.
- Runs the monthly restore dry run.

## Manager's own boundaries
(Fleet-specific; the manager writes them here.)
