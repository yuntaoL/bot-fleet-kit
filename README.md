# bot-fleet-template

A git-backed pattern for **backing up and restoring a fleet of AI assistant bots**.

**Why:** if your assistant account or platform disappears, your bots' instructions, routines and memory go with it; and chat context gets compacted, so bots forget. Here the repo is the durable copy and every bot re-reads its rules and state from files on every run.

## Layout
```
rules/common.md        rules every bot follows         (template)
rules/roles/<role>.md  manager | builder | worker | retired (template)
rules/local/           fleet-specific overlay          (yours, manager-only)
docs/                  ADOPTION, AGENT_GUIDE, RESTORE, VERSIONING, CONTRIBUTING, CHANGELOG (template)
schema/ scripts/ migrations/ templates/ .github/       (template)
fleet.json  bots/<slug>/  shared/  README.md  CHANGELOG.md   (yours)
```

## Adoption (summary — full steps in [docs/ADOPTION.md](docs/ADOPTION.md))
1. *Use this template* → **Private** repo.
2. Clone to the shared bot machine; set git identity.
3. `scripts/bootstrap.sh <this-template-url>`; `git push`.
4. Tell your primary bot to read `rules/common.md` + `rules/roles/manager.md` and set up the fleet.
5. Put the bootstrap prompt (`templates/bot/instructions.md`) at the top of every bot's instructions.

## Update procedure
```
git remote add upstream https://github.com/<owner>/bot-fleet-template.git   # once (bootstrap does it)
git pull --rebase
BOT_ROLE=manager scripts/upgrade.sh <version>
git show --stat && git push
```
Only template-owned paths change; removed template files are deleted; migrations handle schema bumps. See [docs/VERSIONING.md](docs/VERSIONING.md). Guidance changes go upstream first ([docs/CONTRIBUTING.md](docs/CONTRIBUTING.md)).

Restore: tell a fresh bot **"Clone <repo> and follow docs/RESTORE.md."**

MIT licensed.
