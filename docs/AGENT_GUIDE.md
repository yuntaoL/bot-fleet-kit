# Agent guide

The binding rules live in `rules/`; layers, owners and precedence are in `rules/README.md`:
1. `rules/common.md` (template-owned, upgrade-only)
2. `rules/local/overrides.md` (manager, human-approved entries only) and other `rules/local/*.md`
3. `rules/roles/<role>.md` (fleet-owned, manager-only; defaults in `templates/rules/roles/`)
4. `bots/<me>/rules.md` (each bot owns and improves its own)

Precedence: user's direct instruction > common > overrides > role > bot rules. Lower layers only add or tighten.

## Roles (fleet.json `role`)
| role | who | may write |
|---|---|---|
| manager | the primary bot | everything; owns rules/local, shared, fleet.json |
| builder | the bot that creates bots | own folder; any bots/<slug>/ during a restore |
| worker | everyone else | own folder only |
| retired | kept for history | nothing |

## Bootstrap prompt
Every bot puts the snippet from `templates/bot/instructions.md` at the top of its platform instructions so it reads the rules on every run.

## Adding a bot (manager)
1. Slug `^[a-z0-9-]+$`; `cp -r templates/bot bots/<slug>`; delete `routines/example.json`; seed `rules.md` (the manager may replace it while it is still the untouched starter; afterwards only the bot edits it).
2. Fill `profile.json` (incl. `role`) and `instructions.md` (keep the bootstrap prompt on top).
3. Add the entry to `fleet.json`; `scripts/validate.sh`.
4. `git add fleet.json bots/<slug>/ && BOT_ROLE=manager git commit -m "manager: add <slug>"`; pull --rebase; push.

## Folder contents
profile.json, instructions.md, rules.md (bot-owned rules), routines/*.json, skills/, memory.md, state.json, journal/YYYY-MM.md, secrets.md (names only).

## Seen-events log
`shared/state/notified.json` is a list of `{"key": "<source>:<id>:<status>", "at": "<ISO time>", "by": "<slug>"}`. Check it before notifying the human; the manager appends (others message it).
