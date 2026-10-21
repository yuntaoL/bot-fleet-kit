# Restore the fleet (one instruction)

Tell a bot in the new account:
> **Clone `<repo-url>` and follow docs/RESTORE.md.**

1. Clone to the shared machine, set git identity, run `scripts/bootstrap.sh <template-url>`.
2. Read `rules/README.md`, `rules/common.md`, `rules/local/`, `rules/roles/manager.md`, `bots/<manager>/rules.md`, `fleet.json`, `shared/`.
3. **Restore yourself** from the `role: manager` bot's folder: profile, instructions (bootstrap prompt on top), memory, routines (paused stay paused), skills, state.
4. Ask the user to re-create every secret named in `bots/*/secrets.md`. Never guess.
5. **Create the builder** (`role: builder`) from its folder; ask it to rebuild every non-retired bot in `fleet.json` (rules/roles/builder.md).
6. Each rebuilt bot's first run follows its bootstrap prompt and loads its own folder.
7. Update ids in `fleet.json` (old ones to `previousIds`), commit as manager.
8. `scripts/validate.sh`; report restored items and gaps to the user.
