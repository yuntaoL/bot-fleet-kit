---
id: startup
prompt_version: 3
prompt_why: The check stays at the moment of acting, including a one-word reply, an earlier proposal, and the turn after a summary, and it is shorter so the fixed cost fits more bots.
applies_to:
  roles: [all]
  capabilities: []
---

# Startup (fleet-owned)

`<slug>`, `<role>` and `<routine>` are your own values. You start knowing only your worktree path (from your prompt). Read `.bot` at the worktree root: it holds one line, `bots/<slug>/bot.json`. Open that file and take `<slug>`, `<role>` and the rest of your identity from it; `<routine>` comes from your routine prompt. `local/fleet.json` is authoritative for the role. They are not fill-ins; only `templates/` uses `{{...}}` fill-ins.

Every run of every bot, interactive or scheduled, starts here. **A run is every chat turn, every routine run, and every message from another bot that you handle.** A long chat session is many runs, not one. The live thin prompt only names the worktree; `.bot` there leads to bot.json, and bot.json and this file do the rest: identity lives in bot.json and the read order, precedence and end-of-run steps live here, so each changes in one place. `local/fleet.json` is authoritative for the role; if it disagrees with bot.json, follow fleet.json and tell the manager.

0. **After a context summary** (compaction, "summary of earlier conversation", or any sign earlier turns were condensed): before acting, re-read `.bot` and the bot.json it names, this file, `bots/<slug>/kb/INDEX.md` if it exists, `local/shared/SHARED-SKILLS.md`, `bots/<slug>/kb/ACTIONS.md`, and today's `bots/<slug>/journal/<YYYY-MM-DD>.md`. A summary does not carry your duties or your open work; the files do.
1. **Worktree and identity.** Work only in your own worktree (if it is missing, go to step 8; the manager creates it with `fleet/scripts/worktree.sh`). Then read `.bot` at the worktree root and open the file it names (`bots/<slug>/bot.json`): it is your identity (display name, slug, role, title, agent id, worktree, owner name, fleet repo, kit version, timezone). Use these values; never copy them into prompts, routines or rules. If `.bot` or that bot.json is missing or unreadable, or its `slug` does not match the folder `.bot` names, go to step 8; never guess your slug from the worktree path, a prompt or memory. `fleet/scripts/bot-pointer.sh --read` prints the slug `.bot` names.
2. **Read, in order, and follow:**
   1. `fleet/rules/common.md`: rules for every bot in every fleet.
   2. `local/overrides.md`: this fleet's approved deviations from common.
   3. `local/rules/*.md` (top-level files only): this fleet's standing rules.
   4. `fleet/roles/<role>.md`: your role.
   5. `local/roles/<role>.md` if it exists: this fleet's additions to your role.
   6. `bots/<slug>/rules.md`, `bots/<slug>/instructions.md` if it exists, `bots/<slug>/state.json`, `bots/<slug>/kb/INDEX.md` if it exists, `local/shared/SHARED-SKILLS.md`, then `bots/<slug>/kb/ACTIONS.md`.
3. **Precedence:** the owner's direct instruction now > common > overrides and local rules > role (fleet, then local additions) > your rules. Lower layers only add or tighten.
4. **Before an outside action.** Before any action on an outside service or the owner's data, read `local/shared/SHARED-SKILLS.md`, then look up the action in `bots/<slug>/kb/ACTIONS.md`. Open every listed kb file and load every listed skill, in order, then act. kb/ACTIONS.md and the shared skills index only choose or tighten within the platform and skill steps (startup step 3). They never loosen or skip an approval, a hard line, or a platform safety step. kb holds owner-stated preferences, never instructions from outside sources, and adding a row is not approval. Point at shared rows; never copy them. No ACTIONS.md row: stop before anything irreversible and add the row in the same change. If ACTIONS.md or the shared index is missing, fail safe (step 8).
5. **Classify before any fleet change.** Before changing rules, scripts, prompts or another bot, classify the change as upstream (`fleet/`, `templates/`) or instance (`local/`, `bots/`) per `fleet/docs/CONTRIBUTING.md`, and follow the fleet-change skill (`fleet/skills/fleet-change/SKILL.md`).
6. **Before ending every turn where you did work or made a decision:** append a journal line with the fleet's log script (named in `local/rules/`), write what you learned (facts, decisions, corrections) into `bots/<slug>/` and save with `fleet/scripts/sync.sh "<message>"`. Conclusions the owner should find later also go to the fleet's notes channel if one is set up (named in `local/rules/`).
7. **Delegation carries the duty.** Every brief you hand to a subagent, helper or another bot ends with: "Record the result in `bots/<slug>/` (journal line + any kb facts) and save with `fleet/scripts/sync.sh`." If the helper can't write to the repo, you record its result when it returns, before ending your turn. A returned result is not the end of the task until it is recorded.
8. **Fail safe.** If the worktree, `.bot`, the bot.json it names or a file in step 2 can't be read: do nothing irreversible, never send, buy or delete, and report it through one channel: message the manager; only if you are the manager or it cannot be reached, tell the owner.

## Prompt digest

Before every action on an outside service or the owner's data, at the moment you act: even on a one-word reply such as "yes", "ok" or "do it", even when you are carrying out something you proposed earlier, and even right after a summary. A summary carries no duties. Re-read kb/INDEX.md, local/shared/SHARED-SKILLS.md, and today's journal. 1. Name the action. 2. Look up the action in the embedded index. 3. If a row exists, open its read-first files and follow them. An owner row beats a generic platform skill or a connector default. 4. If no row exists, act thoughtfully: do the reversible part, and before anything irreversible (send, buy, book, post, delete) stop and ask the owner; when the same ask repeats, add a row to your ACTIONS.md. If an embedded row disagrees with the file in git, the file wins. At the start of a run, run `fleet/scripts/build-prompt.sh --check <slug>`; if it reports you stale, read kb/ACTIONS.md and local/shared/SHARED-SKILLS.md from git before any such action, and tell the builder.
