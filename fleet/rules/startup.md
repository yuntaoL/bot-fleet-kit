# Startup (fleet-owned)

`<slug>`, `<role>` and `<routine>` are your own values, taken from your prompt and `local/fleet.json` and filled in by you at run time. They are not fill-ins; only `templates/` uses `{{...}}` fill-ins.

Every run of every bot, interactive or scheduled, starts here. The live thin prompt only names the bot, its worktree and this file; the read order, precedence and end-of-run steps live here so they change in one place. Your slug and role come from the prompt; `local/fleet.json` is authoritative for the role.

1. **Worktree.** Work only in your own worktree and run `fleet/scripts/pull.sh` there first (never a bare `git pull`: it can fail when runs overlap) (create it with `fleet/scripts/worktree.sh <slug>` from the shared clone if missing).
2. **Read, in order, and follow:**
   1. `fleet/rules/common.md`: rules for every bot in every fleet.
   2. `local/overrides.md`: this fleet's approved deviations from common.
   3. `local/rules/*.md` (top-level files only): this fleet's standing rules.
   4. `fleet/roles/<role>.md`: your role.
   5. `local/roles/<role>.md` if it exists: this fleet's additions to your role.
   6. `bots/<slug>/rules.md`, `bots/<slug>/instructions.md` if it exists, `bots/<slug>/state.json`, and `bots/<slug>/kb/INDEX.md` if it exists.
3. **Precedence:** the owner's direct instruction now > common > overrides and local rules > role (fleet, then local additions) > your rules. Lower layers only add or tighten.
4. **Classify before any fleet change.** Before changing rules, scripts, prompts or another bot, classify the change as upstream (`fleet/`, `templates/`) or instance (`local/`, `bots/`) per `fleet/docs/CONTRIBUTING.md`, and follow the fleet-change skill (`fleet/skills/fleet-change/SKILL.md`).
5. **Before ending:** write what you learned (facts, decisions, corrections) into `bots/<slug>/` and save with `fleet/scripts/sync.sh "<message>"`. Conclusions the owner should find later also go to the fleet's notes channel if one is set up (named in `local/rules/`).
6. **Fail safe.** If the worktree or a file in step 2 can't be read: do nothing irreversible, never send, buy or delete, and report it through one channel: message the manager; only if you are the manager or it cannot be reached, tell the owner.
