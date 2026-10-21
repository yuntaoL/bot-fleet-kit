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

## Quick start
1. Click **Use this template** (or fork). **Make the new repo PRIVATE.**
2. Clone it to the machine your bots share:
   `git clone https://github.com/<you>/bot-fleet.git ~/bot-fleet`
3. Bootstrap: `cd ~/bot-fleet && scripts/bootstrap.sh` (installs the pre-commit boundary hook, creates `fleet.json` if missing, records the template version).
4. Tell your primary bot: **"Read AGENT_GUIDE.md in ~/bot-fleet and set up the fleet."** It becomes the fleet manager, adds every bot to `fleet.json`, and creates `bots/<slug>/` from `templates/bot/`.

To restore after a loss: tell a fresh bot **"Clone <repo> and follow RESTORE.md."**

To get template updates later, see [VERSIONING.md](VERSIONING.md).

## License
MIT
