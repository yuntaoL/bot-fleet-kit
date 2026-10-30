# Startup (fleet-owned)

`<slug>`, `<role>` and `<routine>` are your own values, taken from `bots/<slug>/bot.json` (the slug is also in your worktree path) and `local/fleet.json`, and filled in by you at run time. They are not fill-ins; only `templates/` uses `{{...}}` fill-ins.

Every run of every bot, interactive or scheduled, starts here. **A run is every chat turn, every routine run, and every message from another bot that you handle.** A long chat session is many runs, not one. The live thin prompt only names the worktree, `bots/<slug>/bot.json` and this file; identity lives in bot.json and the read order, precedence and end-of-run steps live here, so each changes in one place. `local/fleet.json` is authoritative for the role; if it disagrees with bot.json, follow fleet.json and tell the manager.

0. **After a context summary** (compaction, "summary of earlier conversation", or any sign earlier turns were condensed): before acting, re-read `bots/<slug>/bot.json`, this file, `bots/<slug>/kb/INDEX.md` if it exists, and today's `bots/<slug>/journal/<YYYY-MM-DD>.md`. A summary does not carry your duties or your open work; the files do.
1. **Worktree and identity.** Work only in your own worktree and run `fleet/scripts/pull.sh` there first (never a bare `git pull`: it can fail when runs overlap) (create it with `fleet/scripts/worktree.sh <slug>` from the shared clone if missing). Then read `bots/<slug>/bot.json`: it is your identity (display name, slug, role, title, agent id, worktree, owner name, fleet repo, kit version, timezone). Use these values; never copy them into prompts, routines or rules. If it is missing or unreadable, go to step 7.
2. **Read, in order, and follow:**
   1. `fleet/rules/common.md`: rules for every bot in every fleet.
   2. `local/overrides.md`: this fleet's approved deviations from common.
   3. `local/rules/*.md` (top-level files only): this fleet's standing rules.
   4. `fleet/roles/<role>.md`: your role.
   5. `local/roles/<role>.md` if it exists: this fleet's additions to your role.
   6. `bots/<slug>/rules.md`, `bots/<slug>/instructions.md` if it exists, `bots/<slug>/state.json`, and `bots/<slug>/kb/INDEX.md` if it exists.
3. **Precedence:** the owner's direct instruction now > common > overrides and local rules > role (fleet, then local additions) > your rules. Lower layers only add or tighten.
4. **Classify before any fleet change.** Before changing rules, scripts, prompts or another bot, classify the change as upstream (`fleet/`, `templates/`) or instance (`local/`, `bots/`) per `fleet/docs/CONTRIBUTING.md`, and follow the fleet-change skill (`fleet/skills/fleet-change/SKILL.md`).
5. **Before ending every turn where you did work or made a decision:** append a journal line with the fleet's log script (named in `local/rules/`), write what you learned (facts, decisions, corrections) into `bots/<slug>/` and save with `fleet/scripts/sync.sh "<message>"`. Conclusions the owner should find later also go to the fleet's notes channel if one is set up (named in `local/rules/`).
6. **Delegation carries the duty.** Every brief you hand to a subagent, helper or another bot ends with: "Record the result in `bots/<slug>/` (journal line + any kb facts) and save with `fleet/scripts/sync.sh`." If the helper can't write to the repo, you record its result when it returns, before ending your turn. A returned result is not the end of the task until it is recorded.
7. **Fail safe.** If the worktree, `bot.json` or a file in step 2 can't be read: do nothing irreversible, never send, buy or delete, and report it through one channel: message the manager; only if you are the manager or it cannot be reached, tell the owner.
