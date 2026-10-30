# Restore the fleet (one instruction)

Tell a bot in the new account:
> **Clone `<repo-url>` and follow fleet/docs/RESTORE.md.**

1. Clone to the shared machine, set git identity, run `fleet/scripts/bootstrap.sh <template-url>`, then `fleet/scripts/worktree.sh --all`.
2. In your (manager) worktree read `fleet/rules/README.md`, the rule layers, `local/fleet.json`, `local/shared/`.
3. **Restore yourself** from the manager bot's folder: profile, instructions (bootstrap prompt on top), memory, routines (paused stay paused), skills, state.
4. Ask the user to re-create every secret named in `bots/*/secrets.md`. Never guess.
5. **Create the builder** from its folder; ask it to rebuild every non-retired bot in `local/fleet.json` (`fleet/roles/builder.md`).
6. Each rebuilt bot's first run follows its bootstrap prompt in its own worktree.
7. Update ids in `local/fleet.json` (old ones to `previousIds`), commit as manager.
8. `fleet/scripts/validate.sh`; report restored items and gaps to the user.
