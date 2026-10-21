# Agent Guide (rules for every bot)

You are one bot in a fleet. Your folder is `bots/<your-slug>/`. Set `BOT_NAME=<your-slug>` in every git command you run here. The fleet manager also sets `BOT_ROLE=manager`.

## 1. Files are the source of truth; chat is scratch
Anything worth remembering beyond this session goes into `memory.md` (durable facts) or `state.json` (open work) **in the same step you learn it**. Don't rely on platform memory or chat context alone.

## 2. Read on wake, reconcile daily
- On every wake, read your own `state.json` (and `memory.md` if the task needs it) before acting.
- Once a day, compare platform memory, routines and settings against your folder and fix drift **in both directions**: repo → platform if the platform lost something, platform → repo if you learned something not yet written.

## 3. Commit only on real change, immediately, only your files
```
cd ~/bot-fleet
git add bots/$BOT_NAME/          # never `git add -A` or `git add .`
git diff --cached --quiet || {
  git commit -m "$BOT_NAME: <what changed>"
  for i in 1 2 3; do git pull --rebase && git push && break; sleep 5; done
}
```
If the rebase conflicts in your folder, resolve it (yours is the only writer, so it is usually a stale local copy); if it conflicts elsewhere, `git rebase --abort` and tell the fleet manager.

## 4. One writer per folder
Each bot writes only `bots/<its-slug>/`. Only the fleet manager edits `shared/`, `fleet.json`, root files and other bots' folders, and it does so with care to avoid conflicts. The pre-commit hook (`scripts/check-boundary.sh`) enforces this.

## 5. No secrets
Never commit tokens, passwords, API keys, license keys or private data that would hurt if leaked. `secrets.md` lists only the **name** of each secret and **how to re-create it** (e.g. "SMTP_APP_PASSWORD – app password from mail provider, stored as env var").
Treat the repo as readable by every bot in the fleet: keep anything the user wants restricted to one bot out of it.

## 6. Keep memory lean
Rewrite `memory.md` instead of appending forever; target < 200 lines. History goes to `journal/YYYY-MM.md`, one file per month.

## 7. Monthly restore dry run
Once a month the fleet manager checks that `RESTORE.md` plus the repo is enough to rebuild each bot (profile, instructions, routines, skills present and valid; `scripts/validate.sh` passes) and logs the result in its journal.

## Folder contents
| file | purpose |
|---|---|
| profile.json | name, id, role, description, avatar, settings |
| instructions.md | persona and standing rules |
| routines/*.json | each routine: prompt, schedule, status |
| skills/ | skills the bot wrote |
| memory.md | durable facts (lean) |
| state.json | open work: pending asks, queues, deadlines |
| journal/ | monthly history |
| secrets.md | secret names + how to re-create |
