# Layout and ownership

Permissions follow the folder structure. Each top-level tree has exactly one owner class, declared in `fleet/OWNERS.json` and enforced by the pre-commit hook (`check-boundary.sh`) and `validate.sh`. That hook also refuses a commit when staged `bots/<slug>/routines/*.json`, `bots/<slug>/bot.json` or `local/fleet.json` fails the index blob of its schema in `fleet/schema/` (`check-staged-config.sh`). A symlink, gitlink, or other non-regular mode is refused. The worktree copy of a schema is not the source.

```
bot-fleet/
├── README.md                     manager   fleet landing page (GitHub only renders a root README)
├── LICENSE                       manager
├── .gitignore                    manager   root ignore rules (Python bytecode)
├── .github/workflows/            template  CI: validate on pull requests and on pushes outside bots/; selftest only when a kit path changed; 2-hour validate and a 09:00 UTC selftest on main
├── examples/                     template  template repo ONLY (not copied to fleets); add-example.sh fetches from here
├── fleet/                        template  shared, upstream-owned, used as-is; changed ONLY by fleet/scripts/upgrade.sh
│   ├── VERSION  OWNERS.json      version; path globs → owner class (the single permission source)
│   ├── rules/                    startup.md (read order every run), common.md, routines.md, README.md
│   ├── roles/                    manager.md builder.md worker.md (used directly, never copied)
│   ├── skills/                   fleet skills (fleet-change, …)
│   ├── docs/  schema/            documentation; JSON Schemas
│   ├── scripts/                  bootstrap, worktree, sync, upgrade, validate, audit, check-actions, check-staged-config, build-prompt, compat, owners.py, schema_check.py, prompt_build.py, …
│   └── migrations/               <version>.sh, idempotent
├── .bot                          untracked, per worktree (0.10.5+): one line bots/<slug>/bot.json; how a bot finds itself
├── templates/                    template  placeholder/starter files only
│   ├── THIN-PROMPT.tmpl  ROUTINE-PROMPT.tmpl  bot.json.tmpl
│   ├── bot/                      new-bot skeleton
│   └── local/                    starter files copied into local/ once by init-fleet.sh
├── local/                        manager   this fleet's own files (was manager/ before 0.10.0)
│   ├── fleet.json                roster + roles
│   ├── overrides.md              human-approved deviations from common.md
│   ├── rules/*.md                fleet-specific rule additions (read every run)
│   ├── roles/<role>.md           optional additions to fleet/roles/<role>.md
│   ├── registry/                 bot cards
│   ├── shared/                   shared data (state/, skills/, scripts/, …)
│   │   ├── SHARED-SKILLS.md      builder   fleet shared skills index (not the rest of local/)
│   │   └── state/board.md        optional task board; off unless fleet.json sets board
│   ├── prompts/                  builder   compiled prompts and manifests (local/prompts/<slug>.md); not the rest of local/
│   └── CHANGELOG.md              fleet history
└── bots/<slug>/                  self      only bot <slug> (manager/builder may only ADD files)
    ├── bot.json                  identity + environment (0.10.5+): the one copy prompts and routines read
    ├── profile.json  instructions.md  rules.md  memory.md  state.json  secrets.md
    ├── routines/  skills/  journal/  kb/INDEX.md  kb/ACTIONS.md
    └── <anything new>            no permission change needed
```

During the 0.10.0 rollout a fleet also has `template/` and `manager/`: relative symlinks to the new paths so not-yet-re-rendered live prompts keep working (`fleet/scripts/compat.sh`). They are removed later (see CHANGELOG 0.10.0).

Working copies (not in git): `/…/bot-fleet` (shared clone, used for setup) and `/…/bot-fleet-worktrees/<slug>/` (one worktree per bot, branch `wt/<slug>` tracking origin/main).

## OWNERS.json semantics
- First matching glob wins; `**` any depth, `*` one segment. Every tracked file must match (validate.sh fails on unowned paths). A path that matches two owner classes also fails, except `local/shared/SHARED-SKILLS.md` and paths under `local/prompts/` (the builder rules, then `local/**`).
- `template`: only `upgrade.sh` (it commits with `BOT_FLEET_UPGRADE=1` as manager).
- `manager`: `BOT_ROLE=manager`.
- `builder`: `local/shared/SHARED-SKILLS.md` and `local/prompts/**`. The bot whose committed `local/fleet.json` role is builder, and whose status is not retired or paused, may change them. The check reads HEAD, not the working tree. `upgrade.sh` may write the shared index. The manager may only add the pristine template stub (bytes equal to the committed template). Bots' own files under `bots/<slug>/` stay owned by those bots. Audit allows the overlap with `local/**` for the shared index and for `local/prompts/`.
- `self`: the bot whose slug is the second path segment. `create` lists roles that may add new files there (manager seeding a bot; builder with `BOT_RESTORE=1`).
- `retired` role: nothing.
Identity comes from `BOT_NAME`/`BOT_ROLE` or the worktree's git config (`fleet.bot`, `fleet.role`) that `worktree.sh` sets.

## Shared task board (optional)
Omit `board` in `local/fleet.json` and there is no board. Set it to turn the feature on:

```json
"board": {"path": "local/shared/state/board.md", "coordinator": "<slug>"}
```

`coordinator` is a bot slug, not a role. The path must be a markdown file under `local/shared/state/`. An invalid path leaves the feature off and does not make any other file writable. The manager and that slug may create or delete the file. Every non-retired bot may update a regular file (mode 100644); a symlink or gitlink is refused. A board card is never an approval. A bot adds or updates only its own cards. The coordinator's scan reads each commit: the message starts with the committing slug, and every changed card's Owner is that slug or the card is a handoff. A mismatch is escalated to the manager. Ask the manager to write an approval-wait card. `sync.sh` with no paths stages the board when this bot may write it. A path sync does not, so a half-edited board is not swept into another commit. The same sync stages `bots/<slug>/journal` so a journal line does not block rebase. The rules are in `fleet/rules/common.md` and apply only while `board` is set. The rename-bot skill updates `board.coordinator` when the old slug is the coordinator.
