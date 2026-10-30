# Rule layers

`<slug>`, `<role>` and `<routine>` are your own values, taken from your prompt and `local/fleet.json` and filled in by you at run time. They are not fill-ins; only `templates/` uses `{{...}}` fill-ins.

| layer | file | owner tree |
|---|---|---|
| 1. common | `fleet/rules/common.md` | template (upgrade only) |
| 2. overrides | `local/overrides.md` (+ `local/rules/*.md` additions) | manager; overrides need date, approving human, exact approval text |
| 3. role | `fleet/roles/<role>.md` (used as-is) + `local/roles/<role>.md` (this fleet's additions) | template / manager |
| 4. bot | `bots/<slug>/rules.md` | that bot; the manager may only request changes |

**Routine runs:** `fleet/rules/routines.md` (template-owned) is what every scheduled routine run follows; the live routine prompt only points at it. Both the thin prompt and routines.md defer to `fleet/rules/startup.md`, the single read order.

**Precedence:** user's direct instruction > common > overrides > role > bot rules. Lower layers only add or tighten.
**Permissions** come only from `fleet/OWNERS.json` (see fleet/docs/LAYOUT.md); rules files never grant or describe per-file permissions.
**Style:** principles with a why and illustrative examples, not enumerations (`fleet/docs/WRITING_RULES.md`).
