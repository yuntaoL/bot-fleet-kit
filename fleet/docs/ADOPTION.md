# Adoption guide (first-time setup)

Prereqs on the shared bot machine: `git` ≥ 2.20, `gh` (`gh auth login`), `python3`.

> **Prefer chatting to typing?** Since 0.8.0 a bot can do this for you: ask your Grok Bot to follow `fleet/docs/install-manager.md` (two-phase bootstrap: it creates a builder bot that runs these steps). The manual path below still works.

1. **Create a PRIVATE repo from the template:** *Use this template* → Private (CLI: `gh repo create <you>/bot-fleet --private --template <owner>/bot-fleet-template`).
2. **Clone (shared setup clone):** `git clone https://github.com/<you>/bot-fleet.git ~/bot-fleet && cd ~/bot-fleet`
3. **Git identity:** `git config user.name "..." && git config user.email "..."`
4. **Bootstrap:** `fleet/scripts/bootstrap.sh https://github.com/<owner>/bot-fleet-template.git`, then `git push`. It installs the hook, fixes the branch upstream, adds `upstream`, and creates the fleet files under `local/` from `templates/`.
5. **Add your bots** to `local/fleet.json` and seed `bots/<slug>/` (docs/AGENT_GUIDE.md "Adding a bot"); commit as manager and push.
6. **Worktrees:** `fleet/scripts/worktree.sh --all` → `~/bot-fleet-worktrees/<slug>` for every active bot, the manager included.
7. **Give each bot its bootstrap prompt** (`templates/bot/instructions.md`, filled in with its worktree, slug and role).
8. **Check:** `fleet/scripts/validate.sh` passes; CI is green.
- **Owner name (0.8.0+):** set `owner_name` in `local/fleet.json` and render each bot's prompt with `fleet/scripts/render-prompt.sh <slug>` (from `templates/THIN-PROMPT.tmpl`); paste `bots/<slug>/THIN-PROMPT.md` instead of step 7's hand-filled prompt.
