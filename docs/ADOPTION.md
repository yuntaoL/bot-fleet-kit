# Adoption guide (first-time setup)

Prereqs on the shared bot machine: `git`, `gh` (`gh auth login`), `python3`.

1. **Create a PRIVATE repo from the template:** GitHub → *Use this template* → Private (CLI: `gh repo create <you>/bot-fleet --private --template <owner>/bot-fleet-template`). Never a public fork.
2. **Clone:** `git clone https://github.com/<you>/bot-fleet.git ~/bot-fleet && cd ~/bot-fleet`
3. **Git identity:** `git config user.name "..." && git config user.email "..."`
4. **Bootstrap:** `scripts/bootstrap.sh https://github.com/<owner>/bot-fleet-template.git` installs the boundary hook, adds `upstream`, installs jsonschema, replaces the template README/CHANGELOG with fleet ones, creates `fleet.json` and commits as manager. Then `git push`.
5. **Hand off to your primary bot:** *"Read ~/bot-fleet/rules/common.md and rules/roles/manager.md. You are the fleet manager: add every bot (docs/AGENT_GUIDE.md 'Adding a bot') and put fleet-specific rules in rules/local/."*
6. **Give every bot its bootstrap prompt** (templates/bot/instructions.md) with its slug and role filled in.
7. **Check:** `scripts/validate.sh` passes; CI is green.
