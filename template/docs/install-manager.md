# Install the manager bot (two-phase bootstrap)

For a Grok Bot user who has **one bot** and wants a fleet. The user asks that bot: *"Follow template/docs/install-manager.md from <template repo URL>."* The bot becomes the fleet's **manager** (suggested name: Chief) and creates a **builder** (suggested name: dr eggbot). Any names work; guides and scripts refer to roles, never names.

**Why two phases.** In phase 1 there is no repo, no worktree and no local environment, so no bot can load anything from git. Converting a bot then would leave it with nothing to read. Both bots therefore keep running on their platform prompt and memory through phase 1, and are converted in phase 2 only after the environment exists and has been tested.

Hard lines for the whole guide: ask the user before creating a bot, changing any bot's prompt, profile or routines, or starting phase 2. Never see or type passwords, tokens or codes: the user signs in (`gh auth login`) themselves. Record progress in `state.json` `bootstrap` (`{phase, step, status, snapshot, rollbackHolder, verifiedRuns, updated}`) once the repo exists, so a rerun resumes instead of repeating.

## Part A: phase 1, pre-fleet (no prompt changes)
1. **Names.** Ask the user for the manager's display name + slug (default `Chief` / `chief`) and the builder's (default `dr eggbot` / `dr-eggbot`), and the owner's display name (goes into `owner_name`, used in every bot's prompt). Slugs match `^[a-z0-9-]+$` and are unique.
2. **Prerequisites** on the shared machine: `git` ≥ 2.20, `gh`, `python3`. If `gh auth status` fails, ask the user to run `gh auth login` themselves.
3. **Create the builder** (with the user's yes). This is the only bot ever created by a non-builder. Give it the *pre-fleet builder prompt* below, filled in. Do not change your own prompt.
4. **Delegate** environment setup: message the builder "Follow template/docs/bootstrap-fleet.md" with the names, owner name, repo name and template URL.
5. **Get control back.** The builder reports the repo URL, both worktree paths, the self-test result and `validate.sh --pre-fleet` output.
6. **Exit check** (run it yourself, from your new worktree): `template/scripts/validate.sh --pre-fleet` passes; `git config fleet.bot` = your slug in your worktree; `template/scripts/selftest.sh` passes; both bots' `state.json` show `bootstrap: {phase: 1, step: "done", status: "done"}`. Tell the user phase 1 is done and ask for a yes to start phase 2.

### Pre-fleet builder prompt (platform prompt for phase 1 only)
```
You are <BUILDER_NAME>, the builder bot in <OWNER_NAME>'s new bot fleet. There is no local fleet repo yet.
When <MANAGER_NAME> asks, follow <TEMPLATE_URL>/blob/main/template/docs/bootstrap-fleet.md exactly, then report back to <MANAGER_NAME>.
Ask <OWNER_NAME> before anything irreversible. Never handle passwords, tokens or codes; ask <OWNER_NAME> to sign in.
```
After phase 2 this prompt is replaced by the rendered thin prompt (`template/defaults/THIN-PROMPT.tmpl`).

## Part B: phase 2, fleet conversion (one bot at a time)
Entry gate: Part A exit check green and the user's yes.
1. **Convert yourself first**, following `convert-to-fleet-bot.md`. Rollback holder: the builder (and the user). Do not touch the builder while you convert.
2. After your N verified runs and contract step (`status: active`), **supervise the builder's self-conversion** with the same guide. Rollback holder: you (and the user). Verify each of its runs against evidence (files, commits), not its claim.
3. **Exit:** `template/scripts/validate.sh` (no flag) has no FAIL and no required-role WARN: exactly one active manager, at least one active builder. With the user's yes, switch on the builder's routines (daily worktree fast-forward, weekly audit). From now on only the builder creates bots ("Adding a bot" in AGENT_GUIDE.md, then `render-prompt.sh <slug>`).

## Recovery
- Rerun = resume: read `state.json` `bootstrap` and continue at the first step not `done`.
- Lost manager: the builder restores it from its snapshot (`RESTORE-BOT.md`), or the user creates a fresh bot and tells it "Clone <repo> and follow template/docs/RESTORE.md".
