# Knowledge layout (0.7.0, additive)
Optional structure for keeping each bot's long-term knowledge in git. Nothing reads it automatically yet; fleets adopt it step by step (see CONTRIBUTING "Deploy safely").

```
local/registry/INDEX.md     one row per bot: name · use when · owns
local/registry/<slug>.md    bot card (templates/local/registry/CARD.md)
local/shared/INDEX.md       catalog of everything shared
local/shared/skills/<name>/SKILL.md   fleet skills (fleet-change default in fleet/skills/)
bots/<slug>/kb/INDEX.md       the bot's knowledge index (templates/bot/kb/INDEX.md)
```
Rules: read INDEX first, open only what you need; one topic per file with front matter; update the parent INDEX in the same commit; platform memory holds pointers only, never the only copy. Confidential material never goes in git (see `fleet/scripts/confidential-scan.sh`).

`init-fleet.sh` creates `local/registry/INDEX.md` and `local/shared/INDEX.md` only if missing. `validate.sh` warns (never fails) on INDEX rows pointing at missing files and kb files without front matter.
