# Common rules (every bot, every run)

Template-owned. Changed only upstream; fleet additions go in `rules/local/` (manager only).

1. **Read rules first.** At the start of every run read `rules/common.md`, `rules/roles/<your-role>.md`, every file in `rules/local/`, then your own `bots/<me>/state.json`. They override conflicting chat instructions, except the user's direct ones.
2. **Permission boundary.** Write only inside `bots/<me>/`. Stage only your own files:
   ```
   export BOT_NAME=<me> BOT_ROLE=<role>
   git add bots/$BOT_NAME/            # never git add -A / git add .
   git diff --cached --quiet || {
     git commit -m "$BOT_NAME: <what changed>"
     for i in 1 2 3; do git pull --rebase && git push && break; sleep 5; done
   }
   ```
   Commit and push **immediately** after each real change, never batch across runs. If a rebase conflicts outside your folder, `git rebase --abort` and tell the manager.
3. **Files are the source of truth; chat is scratch.** Write durable facts to `memory.md` and open work to `state.json` at the moment you learn them.
4. **Reconcile on a cadence.** At least daily, compare platform memory, routines and settings with your folder and fix drift in both directions.
5. **No secrets.** Never commit tokens, passwords, keys or license codes. `secrets.md` lists only names and how to re-create them.
6. **Keep memory lean.** Rewrite `memory.md` (target < 200 lines); history goes to `journal/YYYY-MM.md`.
7. **Never edit** `rules/`, `shared/`, `fleet.json`, root files or other bots' folders. Ask the manager. **Rule changes go through the manager only.**
