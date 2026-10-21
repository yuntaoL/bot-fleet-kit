# Rule layers

| layer | file(s) | owner / who edits | changes how |
|---|---|---|---|
| 1. common | `rules/common.md` | template | only via `scripts/upgrade.sh` |
| 2. overrides | `rules/local/overrides.md` | manager | only with an explicit recorded human approval (date, approver, exact text) |
| 3. role | `rules/roles/<role>.md` | fleet; manager only | defaults from `templates/rules/roles/` copied on adoption; upgrades never overwrite, only print a diff vs new defaults |
| 4. bot | `bots/<me>/rules.md` | that bot only | the bot improves it; the manager may only request changes by message |
| (extra) | other `rules/local/*.md` | manager | fleet-specific additions; same precedence as overrides, may only add or tighten common |

**Precedence:** the user's direct instruction > common > overrides > role > bot rules.
Overrides beat common only where an entry explicitly says so. Lower layers may only **add or tighten**, never loosen, a higher layer. If two layers conflict, follow the higher one and tell the manager.

Read order on every run: `rules/common.md`, `rules/local/*.md`, `rules/roles/<role>.md`, `bots/<me>/rules.md`, then `bots/<me>/state.json`.
