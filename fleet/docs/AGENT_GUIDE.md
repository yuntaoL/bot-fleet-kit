# Agent guide

Rules: `fleet/rules/README.md` (layers, precedence). Permissions: `fleet/OWNERS.json` (`docs/LAYOUT.md`).

## Roles (local/fleet.json `role`)
manager (primary bot), builder (creates bots; restores the fleet), worker, retired.

## Your worktree
Every bot, the manager included, works only in its own git worktree, never in the shared clone:
```
cd /home/box/bot-fleet && fleet/scripts/worktree.sh <slug>     # once; idempotent
cd /home/box/bot-fleet-worktrees/<slug>
```
The worktree is on branch `wt/<slug>` tracking `origin/main`, with `fleet.bot`/`fleet.role` set, so other bots' untracked files and half-done commits can't touch you.

## Sync loop
```
fleet/scripts/sync.sh "<what changed>"          # default paths: bots/<slug>/ (manager: local/ README.md)
```
It does: `git add <your paths>` (never -A) → commit only if something changed → `git fetch origin` → `git rebase origin/main` → `git push origin HEAD:main` → on a rejected push, fetch/rebase/push again (5 tries, backoff). A rebase conflict means someone wrote your paths or you wrote theirs: abort and tell the manager. Start every run with `git fetch origin && git rebase origin/main` (sync.sh with no change does this).

## Bootstrap prompt
Top of each bot's platform instructions; text in `templates/bot/instructions.md`.

## Adding a bot (manager)
1. Add it to `local/fleet.json` (slug `^[a-z0-9-]+$`, role); `cp -r templates/bot bots/<slug>` and fill in `profile.json`, `instructions.md` (prompt on top), `rules.md`; remove `routines/example.json`.
2. Commit from the manager worktree (manager may add files under bots/<slug>/); `fleet/scripts/worktree.sh <slug>`.
3. Render its prompt: `fleet/scripts/render-prompt.sh <slug>` (needs `owner_name` in `local/fleet.json`, 0.8.0+); give the bot `bots/<slug>/THIN-PROMPT.md` as its platform prompt.
4. Routines (0.9.2+): put each routine's real instructions in `bots/<slug>/routines/<name>.json` `steps` (or a `stepsFile`), run `fleet/scripts/render-routine-prompt.sh <slug>`, and use `routines/<name>.prompt.md` as the live routine prompt. A routine's saved prompt never holds task knowledge. The rendered prompt only points at `fleet/rules/routines.md`, which holds everything a run does: read order, following `steps`, journaling with the `read: …|routine:<file>` marker, `sync.sh`, staying quiet, the schedule and fail-safe. Keep routine `steps` to the task itself.
5. After that, only the bot edits its folder. In a live fleet (0.8.0+) the builder adds bots; the manager decides.

From an example: `BOT_ROLE=manager fleet/scripts/add-example.sh <example> <slug> [name] [platform-id]` does step 1, fetching the example from the public template at your fleet/VERSION (see examples/README.md in the template repo).

## Seen-events log
`local/shared/state/notified.json`: list of `{"key": "<source>:<id>:<status>", "at": "<ISO>", "by": "<slug>"}`. Check before notifying the human; message the manager to record.
