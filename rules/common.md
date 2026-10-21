# Common rules (every bot, every run)

Template-owned. Changes only through a template upgrade, or via a human-approved entry in `rules/local/overrides.md`. Layers and precedence: `rules/README.md`.

## Fundamentals
1. **Read rules first.** Every run starts with `rules/common.md`, `rules/local/*.md`, `rules/roles/<role>.md`, `bots/<me>/rules.md`, then `bots/<me>/state.json`. Precedence: user's direct instruction > common > overrides > role > bot rules; lower layers only add or tighten.
2. **Permission boundary.** Write only inside `bots/<me>/`. Stage only your own files and push immediately:
   ```
   export BOT_NAME=<me> BOT_ROLE=<role>
   git add bots/$BOT_NAME/            # never git add -A / git add .
   git diff --cached --quiet || {
     git commit -m "$BOT_NAME: <what changed>"
     for i in 1 2 3; do git pull --rebase && git push && break; sleep 5; done
   }
   ```
   If a rebase conflicts outside your folder, `git rebase --abort` and tell the manager.
3. **Files are the source of truth; chat is scratch.** Write durable facts to `memory.md` and open work to `state.json` at the moment you learn them.
4. **Reconcile on a cadence.** At least daily, compare platform memory, routines and settings with your folder and fix drift in both directions.
5. **No secrets.** Never commit tokens, passwords, keys or license codes. `secrets.md` lists only names and how to re-create them.
6. **Keep memory lean.** Rewrite `memory.md` (target < 200 lines); history goes to `journal/YYYY-MM.md`.
7. **Never edit** `rules/`, `shared/`, `fleet.json`, root files or other bots' folders. Rule changes go through the manager. Your own `rules.md` is yours to improve (add/tighten only).

## Lessons from running a fleet
8. **Write-through bookkeeping.** If a store has a changelog or index, update it in the same step as the write, never "later".
9. **Dedupe notifications.** Before surfacing an event to the human, check `shared/state/notified.json`. If it's there, stay silent. If not, surface it and record it (manager appends; others message the manager with the event key).
10. **Platform state is ephemeral.** Machines get reset and message history gets wiped. Never rely on chat history or local indexes for durable facts; the repo (and the user's own systems) are durable.
11. **Context compaction.** Before long work, persist decisions and open asks to `state.json`. On wake, reconcile `state.json` open items before anything else.
12. **Agent messaging.** If another bot must act or is waiting, send with priority/wake; FYIs are non-urgent. Always report results back to the requester.
13. **Be explicit about the target machine.** Keep the bot machine's paths and the user's computers separate; check a machine is online before relying on it.
14. **Confidential categories never leave the bot that holds them**: not to other bots, not to the repo.
15. **Outbound messages to humans need human approval.** Reading is fine; sending, posting or replying is not without approval.
16. **One owner per recurring check.** Recurring checks belong to one dedicated owner (e.g. a tracker bot with a queue), not duplicated polling in several bots.
17. **Pause when idle; commit only on change.** Loops stop when their queue is empty and resume on new work; no commits for no-op runs.
