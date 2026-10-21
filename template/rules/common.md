# Common rules (every bot, every run)

Template-owned. Changes only via template upgrade or a human-approved entry in `manager/overrides.md`. Layers: `template/rules/README.md`.

1. **Read rules first:** this file, `manager/overrides.md`, `manager/local/*`, `manager/roles/<role>.md`, `bots/<me>/rules.md`, then `bots/<me>/state.json`. Precedence: user's direct instruction > common > overrides > role > bot rules; lower layers only add or tighten.
2. **Write only under paths `template/OWNERS.json` grants your role.** Ask the manager for anything else.
3. **Work in your own worktree** and save with the sync loop (`template/scripts/sync.sh`, docs/AGENT_GUIDE.md): fetch, rebase onto origin/main, commit only your paths, push, retry. Never `git add -A`. Push immediately after each real change.
4. **Files are the source of truth; chat is scratch.** Write durable facts and open work at the moment you learn them.
5. **Reconcile** platform memory, routines and settings with your files at least daily, both directions.
6. **No secrets** in the repo; `secrets.md` lists names and how to re-create them.
7. **Keep memory lean;** history goes to monthly journal files.

## Lessons
8. **Write-through bookkeeping:** update a store's changelog or index in the same step as the write.
9. **Dedupe notifications:** check `manager/shared/state/notified.json` before surfacing an event; the manager records it.
10. **Platform state is ephemeral:** never rely on chat history or local indexes for durable facts.
11. **Context compaction:** persist decisions and open asks before long work; on wake, reconcile open items first.
12. **Agent messaging:** priority/wake when another bot must act or is waiting; FYIs are non-urgent; always report results to the requester.
13. **Target machine:** keep the bot machine and the user's computers separate; check a machine is online before relying on it.
14. **Confidential categories never leave the bot that holds them.**
15. **Outbound messages to humans need human approval;** reading is fine.
16. **One owner per recurring check;** no duplicated polling.
17. **Pause when idle; commit only on change.**
