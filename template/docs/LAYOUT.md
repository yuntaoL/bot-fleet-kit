# Layout and ownership

Permissions follow the folder structure. Each top-level tree has exactly one owner class, declared in `template/OWNERS.json` and enforced by the pre-commit hook (`check-boundary.sh`) and `validate.sh`.

```
bot-fleet/
├── README.md                     manager   fleet landing page (GitHub only renders a root README)
├── LICENSE                       manager
├── .github/workflows/            template  CI: validate.sh (GitHub requires this path)
├── template/                     template  changed ONLY by template/scripts/upgrade.sh
│   ├── VERSION
│   ├── OWNERS.json               path globs → owner class (the single permission source)
│   ├── rules/                    common.md, README.md (rule layers)
│   ├── docs/                     LAYOUT, ADOPTION, AGENT_GUIDE, RESTORE, VERSIONING, CONTRIBUTING, CHANGELOG
│   ├── scripts/                  bootstrap, worktree, sync, upgrade, validate, check-boundary, owners.py, …
│   ├── schema/                   JSON Schemas
│   ├── migrations/               <version>.sh, idempotent
│   └── defaults/                 bot/ skeleton, roles/ defaults, fleet/ starter files
├── manager/                      manager
│   ├── fleet.json                roster + roles
│   ├── roles/<role>.md           role rules (copied from defaults once; never overwritten)
│   ├── overrides.md              human-approved deviations from common.md
│   ├── local/*.md                fleet-specific rule additions
│   ├── shared/                   shared data: state/notified.json, skills/, …
│   └── CHANGELOG.md              fleet history
└── bots/<slug>/                  self      only bot <slug> (manager/builder may only ADD files)
    ├── profile.json  instructions.md  rules.md  memory.md  state.json  secrets.md
    ├── routines/  skills/  journal/
    └── <anything new>            no permission change needed
```

Working copies (not in git): `/…/bot-fleet` (shared clone, used for setup) and `/…/bot-fleet-worktrees/<slug>/` (one worktree per bot, branch `wt/<slug>` tracking origin/main).

## OWNERS.json semantics
- First matching glob wins; `**` any depth, `*` one segment. Every tracked file must match (validate.sh fails on unowned paths or paths that match two owner classes).
- `template`: only `upgrade.sh` (it commits with `BOT_FLEET_UPGRADE=1` as manager).
- `manager`: `BOT_ROLE=manager`.
- `self`: the bot whose slug is the second path segment. `create` lists roles that may add new files there (manager seeding a bot; builder with `BOT_RESTORE=1`).
- `retired` role: nothing.
Identity comes from `BOT_NAME`/`BOT_ROLE` or the worktree's git config (`fleet.bot`, `fleet.role`) that `worktree.sh` sets.
