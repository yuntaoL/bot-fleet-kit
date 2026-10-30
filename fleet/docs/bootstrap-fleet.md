# Bootstrap the fleet environment (builder, phase 1)

Run by the **builder** when the manager delegates it (install-manager.md Part A step 4). Rerunnable: every step checks before acting, so this is also the repair guide. Never change any bot's prompt, profile or routines here.

Inputs from the manager: owner display name, manager name + slug, builder name + slug, private repo name, template URL.

1. **Auth check.** `gh auth status` works (else ask the user to run `gh auth login`; never handle tokens).
2. **Repo.** If the private repo does not exist: `gh repo create <owner>/<repo> --private --template <template-owner>/bot-fleet-template`. Clone it as the shared clone (default `~/bot-fleet`). Set a git identity if missing.
3. **Bootstrap.** `fleet/scripts/bootstrap.sh <template URL>` (hook, upstream remote, fleet files).
4. **Fleet entries.** In `local/fleet.json` set `owner_name`, and add both bots with `status: "pre-fleet"` (manager `role: manager`, builder `role: builder`; `id` = platform bot id, ask the manager). Seed each folder: `cp -r templates/bot bots/<slug>` (skip if present); remove `routines/example.json`; set `state.json` `bootstrap` to `{"phase": 1, "step": "env", "status": "in-progress"}`. Commit with `BOT_ROLE=manager git commit` and push (the manager role may create files under any `bots/<slug>/`).
5. **Worktrees + identity.** `fleet/scripts/worktree.sh --all` (sets per-worktree `fleet.bot`/`fleet.role`, installs the hook). Create `~/bot-logs/` and `~/fleet-snapshots/` (mode 700).
6. **Render prompts (not applied).** `fleet/scripts/render-prompt.sh <slug>` for both bots writes `bots/<slug>/THIN-PROMPT.md`. These are for phase 2; nobody's platform prompt changes now.
7. **Self-test.** `fleet/scripts/selftest.sh` (scratch clone, fake owner and bots, both phases' git steps, rerun no-op, forced rollback). Must pass.
8. **Validate.** `fleet/scripts/validate.sh --pre-fleet` must pass.
9. **Close.** Set both bots' `state.json` `bootstrap` to `{"phase": 1, "step": "done", "status": "done", "updated": "<ISO>"}`, save with `fleet/scripts/sync.sh` from each bot's worktree (or `BOT_ROLE=manager` from the manager worktree), and report to the manager: repo URL, worktree paths, self-test and validate output.
