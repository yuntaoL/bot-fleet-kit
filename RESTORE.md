# Restore the fleet (one instruction)

Tell a bot in the new account:
> **Clone `<repo-url>` and follow RESTORE.md.**

## Steps for the new primary bot
1. Clone the repo to the shared machine (e.g. `~/bot-fleet`) and run `scripts/bootstrap.sh`.
2. Read `AGENT_GUIDE.md`, `fleet.json` and `shared/`.
3. **Restore yourself** from `bots/<primary-slug>/` (the bot with `"role": "primary"` in fleet.json): apply `profile.json` and `instructions.md`, load `memory.md` into memory, recreate each `routines/*.json` (keep paused ones paused), install `skills/`, and resume open items in `state.json`.
4. Read `secrets.md` files and ask the user to re-create each listed secret. Never guess them.
5. **Create the bot-builder** bot (the one with `"role": "builder"` in fleet.json) from its folder, then ask it to rebuild every other bot in `fleet.json` whose `status` is `active` (skip `retired`).
6. Each rebuilt bot's first task: "Read AGENT_GUIDE.md and load `bots/<your-slug>/`." It restores its own routines, skills, memory and state.
7. New platform ids: the manager updates `fleet.json` (keep the old id under `previousIds`) and commits.
8. Run `scripts/validate.sh` and report what was restored and any gaps to the user.
