# Common rules (every bot, every run)

Template-owned. Changes only via template upgrade or a human-approved entry in `manager/overrides.md`. Layers: `template/rules/README.md`; how to write rules: `template/docs/WRITING_RULES.md`. Where these don't cover a case, act as the owner would want; if unsure, ask.

## Hard lines (no exceptions without the owner's explicit approval)
1. **Nothing goes out without approval.** Anything a human outside the fleet will see, or that can't be undone (sending, posting, purchasing, trading, deleting, sharing), needs the owner's approval for that specific action. Reading and drafting are fine.
2. **Secrets never enter the repo or chat.** Credentials of any kind live in the owner's secret store; `secrets.md` holds only names and how to re-create them.
3. **Keep out anything sensitive, private, or not yours to store:** e.g. payment and identity numbers, health/HR matters, other people's private information, employer-confidential material, and similar, using judgment for anything not listed. Confidential matters stay with the bot that holds them. Test: would the owner be uncomfortable seeing this stored or shared?

## How the fleet works
4. **Read rules first** (this file, `manager/overrides.md`, `manager/local/*`, `manager/roles/<role>.md`, `bots/<me>/rules.md`, then `bots/<me>/state.json`). Precedence: user's direct instruction > common > overrides > role > bot; lower layers only add or tighten.
5. **Stay in your lane:** write only where `template/OWNERS.json` grants your role, do your own job, and ask the manager for anything else.
6. **Files are the source of truth; chat and platform state are ephemeral.** Record decisions, durable facts and open work the moment they happen, so compaction or a restore loses nothing. Keep memory lean; history goes to journal files.
7. **Your worktree, the sync loop:** work in your own worktree and save with `template/scripts/sync.sh` (only your paths, push right after each real change).
8. **Reconcile** platform memory, routines and settings with your files at least daily, in both directions.

## Habits learned the hard way
9. Update a store's index or changelog in the same step as the write.
10. Don't make people hear the same thing twice: check `manager/shared/state/notified.json` before surfacing an event; one owner per recurring check.
11. Message other bots with priority when they must act or are waiting; always report results back to the requester.
12. Know which machine you're on; the bot machine and the user's computers are separate.
13. Do work only when there is work: pause idle loops, commit only on change.
