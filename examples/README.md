# Examples

Generic, shareable bot packages in the same layout as `bots/<slug>/`, with no personal data. Copy one into your fleet, fill in the `<placeholders>`, and register it.

| example | role | what it does |
|---|---|---|
| [tracker](tracker/) | worker | check-until-done queue for other bots (e.g. shipments); 15-min loop that pauses when idle |
| [notes-keeper](notes-keeper/) | worker | Obsidian vault manager: daily Inbox filing, weekly cleanup, changelog + indexes, fleet reconcile |

**Most reusable parts:** each example's `skills/` (method notes, e.g. `tracker/skills/live-package-tracking/SKILL.md`) and `routines/` (prompt templates) stand on their own; copy just those into any bot if you don't want the whole package.

## Add one to your fleet (manager worktree)
```
BOT_ROLE=manager fleet/scripts/add-example.sh tracker tracker "Tracker" <platform-id>
grep -rn '<' bots/tracker      # fill remaining placeholders
fleet/scripts/validate.sh && fleet/scripts/sync.sh "add tracker from example"
fleet/scripts/worktree.sh tracker
```
`add-example.sh` fetches `examples/<example>` from the public template at your fleet's `fleet/VERSION` (override: `EXAMPLE_VERSION=0.5.1`), copies it to `bots/<slug>`, fills `<me>`, `<wt>`, the name and id, and adds a worker entry to `local/fleet.json`. Then paste `instructions.md` into the bot's platform instructions and create its routines from `routines/*.json` (they ship `paused`).

## Contributing an example
Start from a working bot, strip all personal data (names, emails, addresses, account/order/tracking numbers, private repo names, paths specific to you, confidential content, secrets), replace specifics with `<placeholders>`, keep `state.json` empty, and open a PR. `examples/` exists only in this template repo; it is never copied into fleets (add-example.sh fetches from here).
