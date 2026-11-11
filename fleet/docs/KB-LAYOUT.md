# Knowledge layout (0.7.0, additive; action index 0.11.0)
Optional structure for keeping each bot's long-term knowledge in git. Startup reads the shared skills index and each bot's action index every run (see CONTRIBUTING "Deploy safely").

```
local/registry/INDEX.md     one row per bot: name · use when · owns
local/registry/<slug>.md    bot card (templates/local/registry/CARD.md)
local/shared/INDEX.md       catalog of everything shared
local/shared/SHARED-SKILLS.md   fleet shared skills index, builder-owned (templates/local/shared/SHARED-SKILLS.md)
local/shared/skills/<name>/SKILL.md   fleet skills (fleet-change default in fleet/skills/)
bots/<slug>/kb/INDEX.md       the bot's knowledge index (templates/bot/kb/INDEX.md)
bots/<slug>/kb/ACTIONS.md     action index: kb files and skills to read before each outside action
```
Rules: read INDEX first, open only what you need; one topic per file with front matter; update the parent INDEX in the same commit; platform memory holds pointers only, never the only copy. Before an outside action, read `local/shared/SHARED-SKILLS.md`, then `bots/<slug>/kb/ACTIONS.md`. Bots point at shared rows; they do not copy them. Confidential material never goes in git (see `fleet/scripts/confidential-scan.sh`).

`init-fleet.sh` creates `local/registry/INDEX.md`, `local/shared/INDEX.md` and `local/shared/SHARED-SKILLS.md` only if missing. `validate.sh` warns (never fails) on INDEX rows pointing at missing files and kb files without front matter. `check-actions.sh` fails when ACTIONS.md or the shared index is missing or a row points at a missing file, and warns on an unindexed pref, service or skill and on a stub index.
