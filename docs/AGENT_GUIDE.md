# Agent guide

The binding rules live in `rules/`: `rules/common.md` (everyone), `rules/roles/<role>.md`, and the fleet's `rules/local/` overlay. This page explains the layout.

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
1. Slug `^[a-z0-9-]+$`; `cp -r templates/bot bots/<slug>`; delete `routines/example.json`.
2. Fill `profile.json` (incl. `role`) and `instructions.md` (keep the bootstrap prompt on top).
3. Add the entry to `fleet.json`; `scripts/validate.sh`.
4. `git add fleet.json bots/<slug>/ && BOT_ROLE=manager git commit -m "manager: add <slug>"`; pull --rebase; push.

## Folder contents
profile.json, instructions.md, routines/*.json, skills/, memory.md, state.json, journal/YYYY-MM.md, secrets.md (names only).
