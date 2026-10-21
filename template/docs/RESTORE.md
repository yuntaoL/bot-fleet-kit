# Restore the fleet (one instruction)

Tell a bot in the new account:
> **Clone `<repo-url>` and follow template/docs/RESTORE.md.**

1. Clone to the shared machine, set git identity, run `template/scripts/bootstrap.sh <template-url>`, then `template/scripts/worktree.sh --all`.
2. In your (manager) worktree read `template/rules/README.md`, the rule layers, `manager/fleet.json`, `manager/shared/`.
3. **Restore yourself** from the manager bot's folder: profile, instructions (bootstrap prompt on top), memory, routines (paused stay paused), skills, state.
4. Ask the user to re-create every secret named in `bots/*/secrets.md`. Never guess.
5. **Create the builder** from its folder; ask it to rebuild every non-retired bot in `manager/fleet.json` (`manager/roles/builder.md`).
6. Each rebuilt bot's first run follows its bootstrap prompt in its own worktree.
7. Update ids in `manager/fleet.json` (old ones to `previousIds`), commit as manager.
8. `template/scripts/validate.sh`; report restored items and gaps to the user.
