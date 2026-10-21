# bot-fleet-template

A git-backed pattern for **backing up and restoring a fleet of AI assistant bots**.

## Why
- **Platform or account loss.** If your assistant account disappears, so do your bots, their instructions, routines and memory. This repo is the durable copy.
- **Context compaction.** Chat context is small and gets summarized; details get lost. Bots that write durable facts to files and re-read them on every wake don't forget.

The platform and the bot machine hold only temporary data. The repo holds everything needed to rebuild.

## Layout
```
AGENT_GUIDE.md   rules every bot follows            (template-owned)
RESTORE.md       one-instruction restore            (template-owned)
VERSIONING.md    how upgrades work                  (template-owned)
schema/          JSON Schemas                       (template-owned)
templates/bot/   skeleton for a new bot folder      (template-owned)
scripts/         boundary hook, validate, upgrade   (template-owned)
migrations/      per-version upgrade scripts        (template-owned)
fleet.json       list of your bots                  (user-owned)
shared/          shared profile, preferences, skills(user-owned)
bots/<slug>/     one folder per bot                 (user-owned)
```

## Adoption guide (first-time setup)
Prereqs on the machine your bots share: `git`, `gh` (logged in: `gh auth login`), `python3`.

1. **Create your repo.** On GitHub click **Use this template → Create a new repository**, choose **Private**, name it e.g. `bot-fleet`. (CLI: `gh repo create <you>/bot-fleet --private --template <owner>/bot-fleet-template`.) Don't fork publicly: your fleet data must stay private.
2. **Clone it** to the shared bot machine: `git clone https://github.com/<you>/bot-fleet.git ~/bot-fleet && cd ~/bot-fleet`
3. **Bootstrap:** `scripts/bootstrap.sh <template-repo-url>`. It checks git identity (set `git config user.name/user.email` if it complains), installs the pre-commit boundary hook, adds the `upstream` remote, installs `jsonschema` if possible, creates `fleet.json`, and commits it as the manager.
4. **Hand off to your primary bot:** tell it *"Read AGENT_GUIDE.md in ~/bot-fleet. You are the fleet manager: add every bot to fleet.json and create its folder (see 'Adding a bot')."*
5. **Check:** `scripts/validate.sh` passes and `git log` shows the manager's commit pushed.
6. Tell each bot: *"Read AGENT_GUIDE.md; your folder is bots/<slug>/; commit with BOT_NAME=<slug>."*

Restoring after a loss: tell a fresh bot **"Clone <repo> and follow RESTORE.md."**

## Update procedure (getting template fixes)
```
cd ~/bot-fleet
git remote -v | grep upstream || git remote add upstream https://github.com/<owner>/bot-fleet-template.git
git pull --rebase                      # clean tree, up to date
BOT_ROLE=manager scripts/upgrade.sh 0.1.1
git show --stat                         # review
git push
```
Only template-owned paths change; your `bots/`, `shared/`, `fleet.json` are touched only by migrations. Details in [VERSIONING.md](VERSIONING.md). Never hand-edit template-owned files in your fleet repo; propose changes upstream ([CONTRIBUTING.md](CONTRIBUTING.md)).

## License
MIT
