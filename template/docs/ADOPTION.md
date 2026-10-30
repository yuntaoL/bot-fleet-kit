# Adoption guide (first-time setup)

Prereqs on the shared bot machine: `git` ≥ 2.20, `gh` (`gh auth login`), `python3`.

> **Prefer chatting to typing?** Since 0.8.0 a bot can do this for you: ask your Grok Bot to follow `template/docs/install-manager.md` (two-phase bootstrap: it creates a builder bot that runs these steps). The manual path below still works.

1. **Create a PRIVATE repo from the template:** *Use this template* → Private (CLI: `gh repo create <you>/bot-fleet --private --template <owner>/bot-fleet-template`).
2. **Clone (shared setup clone):** `git clone https://github.com/<you>/bot-fleet.git ~/bot-fleet && cd ~/bot-fleet`
3. **Git identity:** `git config user.name "..." && git config user.email "..."`
4. **Bootstrap:** `template/scripts/bootstrap.sh https://github.com/<owner>/bot-fleet-template.git`, then `git push`. It installs the hook, fixes the branch upstream, adds `upstream`, and creates the fleet files under `manager/` from `template/defaults/`.
5. **Add your bots** to `manager/fleet.json` and seed `bots/<slug>/` (docs/AGENT_GUIDE.md "Adding a bot"); commit as manager and push.
6. **Worktrees:** `template/scripts/worktree.sh --all` → `~/bot-fleet-worktrees/<slug>` for every active bot, the manager included.
7. **Give each bot its bootstrap prompt** (`template/defaults/bot/instructions.md`, filled in with its worktree, slug and role).
8. **Check:** `template/scripts/validate.sh` passes; CI is green.
- **Owner name (0.8.0+):** set `owner_name` in `manager/fleet.json` and render each bot's prompt with `template/scripts/render-prompt.sh <slug>` (from `template/defaults/THIN-PROMPT.tmpl`); paste `bots/<slug>/THIN-PROMPT.md` instead of step 7's hand-filled prompt.
