---
name: rename-bot
description: Rename a bot (display name, slug/folder, worktree and branch) safely. Builder-owned; expand then contract.
---
# Rename a bot
Owner: **builder** (runs it), **manager** (fleet.json, registry), **the bot being renamed** (its own files and everything outside git). A rename is an instance change: follow fleet-change; the owner approves the new name and any prompt or profile change first.

**One place (0.10.5+).** A bot's display name, role, title and other identity live only in `bots/<slug>/bot.json`; prompts and routines reference it. A display-name rename therefore edits only `bots/<slug>/bot.json` (`display_name`, and `title` if it changes) plus the platform profile; the registry copy in `local/fleet.json` is mirrored by the manager with `fleet/scripts/bot-json.sh --mirror <slug>` (validate.sh warns until it is), and no prompt or routine needs re-rendering or re-pasting.

**Pick the scope.** (a) display name only: the bot edits `display_name` in its `bot.json` and syncs; with the owner's yes the platform profile name is changed; the manager runs `bot-json.sh --mirror <slug>` and updates the registry row; then steps 8–9. (b) slug/folder: all steps. (c) worktree + branch (folder already renamed, or a worktree dir that never matched its slug): steps 1–2, 5–11. Helper for the git parts: `fleet/scripts/rename-bot.sh <old> <new> <expand|worktree|refs|contract> [--dry-run]` (always run `--dry-run` first).

1. **Snapshot and check.** `fleet/scripts/snapshot-fleet.sh pre-rename-<old>-to-<new>`. Every affected worktree is clean (`git status --porcelain` empty, nothing unpushed); stash or commit first. List untracked files in the bot's worktree (`git status --porcelain --ignored`): they move with the dir, but note them. Pause the bot's routines or pick a gap between runs. New slug matches `^[a-z0-9-]+$` and is unused.
2. **Inventory references.** `rename-bot.sh <old> <new> refs` greps the repo for `bots/<old>`, the old worktree path and `wt/<old>` (`fleet/`, journals, CHANGELOGs and snapshots excluded: history stays as written). Save the list; it is the checklist for steps 4 and 10.
3. **Registry (manager).** In `local/fleet.json` set `slug` to new (and `name` if it changes); add the old slug to `previousSlugs`. Rename `local/registry/<old>.md` and its `INDEX.md` row. Commit with `sync.sh`.
4. **Expand: copy the folder (builder).** `BOT_RESTORE=1 rename-bot.sh <old> <new> expand` copies `bots/<old>/` to `bots/<new>/` (builders may only add files under a bot's tree) and commits. Both folders exist; nothing reads the new one yet. The copy's `bot.json` gets the new `slug` and `worktree` automatically. Fix repo references from step 2 that live outside `bots/<old>/` (manager-owned files by the manager, other bots' files by those bots).
5. **Move the worktree.** `rename-bot.sh <old> <new> worktree` (from the shared clone): `git worktree move`, `git branch -m wt/<old> wt/<new>`, upstream to `origin/main`, `fleet.bot=<new>`, `.bot` -> `bots/<new>/bot.json` (0.10.5+; the bot finds its identity through it), `git worktree prune`. Special cases in local scripts (e.g. a snapshot script mapping slug to dir) are removed, not updated.
6. **Re-render the prompts.** In the new worktree: `fleet/scripts/render-prompt.sh <new>` and `fleet/scripts/render-routine-prompt.sh <new>`; diff against the live prompt; nothing may be lost. Switch the live prompt only with the owner's yes, keeping the old one as a fallback line until step 11.
7. **Outside git (the bot itself; only it can edit these).** The builder sends it this list; the bot confirms each item:
   - profile/agent description and display name (the platform profile; its identity in git is only `bots/<new>/bot.json`);
   - every routine prompt (schedule text, paths to `bots/<old>/` or the old worktree);
   - its skills and any memory/notes entries holding the old path or name;
   - other bots' prompts or routines that mention it (each bot edits its own);
   - notes vault pages or channels that link the old path.
8. **Validate.** `fleet/scripts/validate.sh` in the new worktree: no FAIL, no `worktree dir` / `fleet.bot` WARN for this bot; confidential scan clean.
9. **Fleet-wide pull.** Builder pulls every worktree (`git pull --ff-only`); other worktrees keep the old text until they do.
10. **Verify.** Next real run of the bot (and of any routine that named it) works from the new path; `refs` returns only history. One journal line per step.
11. **Contract.** After verification: the bot, from its new worktree, runs `BOT_NAME=<old> rename-bot.sh <old> <new> contract` (removes `bots/<old>/`; only the old identity owns it) and drops the fallback prompt line. Remove `previousSlugs` later if no one needs it.

**Rename drift (owner renamed the bot in the app).** The builder's routine fleet check (fleet-sync or audit) runs `fleet/scripts/check-names.sh` (read-only; live `profile.json` `name` vs `fleet.json` and registry). On a DRIFT line: change nothing, message the manager with slug, old name and new name. The manager asks the owner: (1) full rename: slug/folder/worktree via this skill, or (2) display name only: the bot sets `display_name` in its `bot.json`, the manager runs `bot-json.sh --mirror <slug>` and updates the registry row; no prompt change (0.10.5+). Never pick for the owner.

**Rollback.** Before step 11: point the live prompt and routines back, `git worktree move` + `git branch -m` in reverse, `fleet.bot=<old>`, revert the fleet.json/registry commit and the copy commit. After step 11: also `git revert` the contract commit. Snapshot from step 1 holds the platform side. Name the rollback holder (normally the builder) before step 4.
