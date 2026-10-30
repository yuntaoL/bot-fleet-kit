# Layout and ownership

Permissions follow the folder structure. Each top-level tree has exactly one owner class, declared in `fleet/OWNERS.json` and enforced by the pre-commit hook (`check-boundary.sh`) and `validate.sh`.

```
bot-fleet/
├── README.md                     manager   fleet landing page (GitHub only renders a root README)
├── LICENSE                       manager
├── .github/workflows/            template  CI: validate.sh (GitHub requires this path)
├── examples/                     template  template repo ONLY (not copied to fleets); add-example.sh fetches from here
├── fleet/                        template  shared, upstream-owned, used as-is; changed ONLY by fleet/scripts/upgrade.sh
│   ├── VERSION  OWNERS.json      version; path globs → owner class (the single permission source)
│   ├── rules/                    startup.md (read order every run), common.md, routines.md, README.md
│   ├── roles/                    manager.md builder.md worker.md (used directly, never copied)
│   ├── skills/                   fleet skills (fleet-change, …)
│   ├── docs/  schema/            documentation; JSON Schemas
│   ├── scripts/                  bootstrap, worktree, sync, upgrade, validate, audit, compat, owners.py, …
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
│   ├── registry/  shared/        bot cards; shared data (state/, skills/, scripts/, …)
│   └── CHANGELOG.md              fleet history
└── bots/<slug>/                  self      only bot <slug> (manager/builder may only ADD files)
    ├── bot.json                  identity + environment (0.10.5+): the one copy prompts and routines read
    ├── profile.json  instructions.md  rules.md  memory.md  state.json  secrets.md
    ├── routines/  skills/  journal/
    └── <anything new>            no permission change needed
```

During the 0.10.0 rollout a fleet also has `template/` and `manager/`: relative symlinks to the new paths so not-yet-re-rendered live prompts keep working (`fleet/scripts/compat.sh`). They are removed later (see CHANGELOG 0.10.0).

Working copies (not in git): `/…/bot-fleet` (shared clone, used for setup) and `/…/bot-fleet-worktrees/<slug>/` (one worktree per bot, branch `wt/<slug>` tracking origin/main).

## OWNERS.json semantics
- First matching glob wins; `**` any depth, `*` one segment. Every tracked file must match (validate.sh fails on unowned paths or paths that match two owner classes).
- `template`: only `upgrade.sh` (it commits with `BOT_FLEET_UPGRADE=1` as manager).
- `manager`: `BOT_ROLE=manager`.
- `self`: the bot whose slug is the second path segment. `create` lists roles that may add new files there (manager seeding a bot; builder with `BOT_RESTORE=1`).
- `retired` role: nothing.
Identity comes from `BOT_NAME`/`BOT_ROLE` or the worktree's git config (`fleet.bot`, `fleet.role`) that `worktree.sh` sets.
