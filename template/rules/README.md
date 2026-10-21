# Rule layers

| layer | file | owner tree |
|---|---|---|
| 1. common | `template/rules/common.md` | template (upgrade only) |
| 2. overrides | `manager/overrides.md` (+ `manager/local/*.md` additions) | manager; overrides need date, approving human, exact approval text |
| 3. role | `manager/roles/<role>.md` (defaults in `template/defaults/roles/`, copied on adoption, never overwritten) | manager |
| 4. bot | `bots/<me>/rules.md` | that bot; the manager may only request changes |

**Precedence:** user's direct instruction > common > overrides > role > bot rules. Lower layers only add or tighten.
**Permissions** come only from `template/OWNERS.json` (see docs/LAYOUT.md); rules files never grant or describe per-file permissions.
