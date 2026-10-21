# Agent guide

Rules: `template/rules/README.md` (layers, precedence). Permissions: `template/OWNERS.json` (`docs/LAYOUT.md`).

## Roles (manager/fleet.json `role`)
manager (primary bot), builder (creates bots; restores the fleet), worker, retired.

## Your worktree
Every bot, the manager included, works only in its own git worktree, never in the shared clone:
```
cd /home/box/bot-fleet && template/scripts/worktree.sh <slug>     # once; idempotent
cd /home/box/bot-fleet-worktrees/<slug>
```
The worktree is on branch `wt/<slug>` tracking `origin/main`, with `fleet.bot`/`fleet.role` set, so other bots' untracked files and half-done commits can't touch you.

## Sync loop
```
template/scripts/sync.sh "<what changed>"          # default paths: bots/<me>/ (manager: manager/ README.md)
```
It does: `git add <your paths>` (never -A) → commit only if something changed → `git fetch origin` → `git rebase origin/main` → `git push origin HEAD:main` → on a rejected push, fetch/rebase/push again (5 tries, backoff). A rebase conflict means someone wrote your paths or you wrote theirs: abort and tell the manager. Start every run with `git fetch origin && git rebase origin/main` (sync.sh with no change does this).

## Bootstrap prompt
Top of each bot's platform instructions; text in `template/defaults/bot/instructions.md`.

## Adding a bot (manager)
1. Add it to `manager/fleet.json` (slug `^[a-z0-9-]+$`, role); `cp -r template/defaults/bot bots/<slug>` and fill in `profile.json`, `instructions.md` (prompt on top), `rules.md`; remove `routines/example.json`.
2. Commit from the manager worktree (manager may add files under bots/<slug>/); `template/scripts/worktree.sh <slug>`.
3. After that, only the bot edits its folder.

From an example: `BOT_ROLE=manager template/scripts/add-example.sh <example> <slug> [name] [platform-id]` does step 1, fetching the example from the public template at your template/VERSION (see examples/README.md in the template repo).

## Seen-events log
`manager/shared/state/notified.json`: list of `{"key": "<source>:<id>:<status>", "at": "<ISO>", "by": "<slug>"}`. Check before notifying the human; message the manager to record.
