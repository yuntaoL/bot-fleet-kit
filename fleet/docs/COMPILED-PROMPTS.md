# Compiled prompts (0.12.0)

File mode is the default. A bot on file mode still gets the thin prompt: worktree, safe pull, `.bot`, `fleet/rules/startup.md`, a journal line and `sync.sh` every turn, and the fail-safe line. Compiled mode puts the pre-action check in the prompt itself, because the platform prompt is not compacted and the files are.

Nothing in this release edits a live platform profile. `startup.md` is not shortened here. That waits for 0.13.0, after compiled prompts have had verified runs.

## Opt out or in

`local/fleet.json`:

```json
"prompt_mode": "files"
```

`files` is the default when the key is missing. `compiled` builds a prompt per bot. A bot may set its own `prompt_mode`, and that wins over the fleet value.

`files` does not write `local/prompts/`. The thin prompt is rendered with `fleet/scripts/render-prompt.sh`, as before.

## What a compiled prompt contains

`fleet/scripts/build-prompt.sh` writes `local/prompts/<slug>.md` and `local/prompts/<slug>.manifest.json`.

The prompt has, in order:

1. The thin-prompt text for that bot's worktree, including `fleet/scripts/pull.sh` as the safe update. That is not a pull at the start of every turn.
2. The pre-action routine (below).
3. The prompt digests that apply to this bot. The startup digest is the routine, so it is not repeated.
4. This bot's action index, one line per row: action name, read-first pointers (paths and skill names, shortened), hard rule verbatim.
5. The shared-skill rows that apply to this bot: skill name, action types, location. The long "when to use" cell is not copied.
6. A reminder that holds, approvals, journals and state stay in their files.

Placeholder rows (`fill in`) are left out. A real hard rule is never dropped or cut to fit. If an embedded row disagrees with the file in git, the file wins. At the start of a run the bot runs `fleet/scripts/build-prompt.sh --check`, which only reports staleness.

## The pre-action routine

This is the `## Prompt digest` of `fleet/rules/startup.md`. Every compiled prompt includes it, for every role:

> Before every action on an outside service or the owner's data, at the moment you act: even on a one-word reply such as "yes", "ok" or "do it", even when you are carrying out something you proposed earlier, and even right after a summary. A summary carries no duties. 1. Name the action. 2. Look up the action in the embedded index and in Shared skills. 3. If a row exists, open its read-first files and follow them. An owner row beats a generic platform skill or a connector default. 4. If no row exists, act thoughtfully: do the reversible part, and before anything irreversible (send, buy, book, post, delete) stop and ask the owner; when the same ask repeats, add a row to your ACTIONS.md. If an embedded row disagrees with the file in git, the file wins. At the start of a run, and again after a summary, re-read kb/INDEX.md, local/shared/SHARED-SKILLS.md, and today's journal. At the start of a run, run `fleet/scripts/build-prompt.sh --check <slug>`; if it reports you stale, read kb/ACTIONS.md and local/shared/SHARED-SKILLS.md from git before any such action, and tell the builder.

File mode still follows startup step 4. Compiled mode does not remove that step.

## Which rows are included

Shared skills (`local/shared/SHARED-SKILLS.md`), for each bot:

- Include a skill row when that bot's `kb/ACTIONS.md` names the skill, `skills/<name>`, or a backticked path from the location cell, on a token boundary. Trailing `. , ; : ) ]` still counts. A location that is only a word, such as `library`, is not a path and does not count.
- Also include a skill row when the Applies to cell lists the bot's role, or `all`.
- An empty Applies to cell is reference-only. It is not given to every bot.
- The skill line carries the Read-first column's backticked paths and link targets. The long "when to use" cell is not copied.
- An owner-preference row is not copied to every bot. An Applies to cell lists slugs, roles, or `all`. An empty cell is included only when its action, or a skill it names, matches that bot's ACTIONS or a skill row already chosen. A `../` link in a skill or preference row is rewritten so it resolves from `local/prompts/<slug>.md`.

Rule digests (`fleet/rules/*.md`, `fleet/roles/*.md`, `local/rules/*.md`):

- Include the digest when `applies_to.roles` contains the bot's role or `all`, and either `applies_to.capabilities` is empty or the bot lists one of those capabilities (`capabilities` on the bot in `local/fleet.json`).
- The startup digest is the routine above and is included for every compiled bot.
- The role in `local/fleet.json` is the one that counts.

A bot only sees its own index and the rows that match it. Another bot's actions are not copied in.

## What causes a new build

The rebuild hash covers:

- each included `## Prompt digest` (id, prompt version, digest hash, who it applies to)
- the embedded action lines and skill lines
- the bot's role and capabilities
- the thin-prompt text (so the safe-pull sentence is part of the prompt)

It does not cover docs, scripts, journals, state, holds, approvals, or the manifest's `built_at`. Editing the body of a rule above its digest does not change the prompt. Editing the digest does.

`built_at` and the git commit are recorded on the manifest and are not part of the hash. A second build with the same inputs writes the same bytes, including the same `built_at`.

Kit files (`fleet/rules`, `fleet/roles`) have `prompt_version`. Fleet-local files (`local/rules`) do not: they are identified by id, the digest hash, and the fleet commit stored on the manifest.

`build-prompt.sh --check-versions` (also run by `validate.sh`):

- digest changed, `prompt_version` not bumped: fail
- `prompt_version` bumped, digest unchanged: warn
- a file gaining its first digest: ok

Compare is against `BOT_FLEET_PROMPT_BASE` when that commit exists, otherwise the merge-base with `origin/main`. An unreachable base (for example after a force-push) is a warning and falls back; if there is still no base, the check is skipped. Deleting a digest-bearing kit file fails unless its path is listed in `fleet/PROMPT-REMOVALS`.

## Size

The cap is 8000 characters. Set `prompt_max_chars` in `local/fleet.json`, or `BOT_FLEET_PROMPT_MAX` for one run. The environment variable wins.

Over the cap, the build fails and names three parts: fixed cost (thin prompt, routine, rule gists, footer), the bot's own action index, and skill plus preference rows. It says which part to cut and the exact overflow in characters. The strictly largest part is the one to cut. A tie does not tell the bot to trim ACTIONS.md unless that index is strictly the largest. Hard rules are not truncated. The cap stays 8000.

Measured on the fixture fleet in `fleet/scripts/test-build-prompt.sh` (fictional bots, kit 0.12.0):

| Bot | Characters | Fixed | Action index | Shared skills |
|---|---:|---:|---:|---:|
| harbor-clerk | 5030 | 3661 | 712 | 657 |
| pier-archivist | 4082 | 3716 | 122 | 244 |
| cargo-crier | 16130 | 3600 | 12055 | 475 |

cargo-crier's largest row, crate log, is 12036 characters. The action index is strictly the largest part, so the report says to cut 8130 characters from that index. The board fixture in `test-board.sh` writes `local/prompts/mina.md` at 3689 characters.

## One approval for a kit release

A kit release asks the owner once, for the whole fleet, not once per bot.

1. The builder runs `fleet/scripts/build-prompt.sh`.
2. The builder runs `fleet/scripts/build-prompt.sh --changelog` and sends that note. It says which bots, which rule, why, and the before/after text.
3. The owner says yes or no. One yes covers the release.
4. Whoever applies it pastes `local/prompts/<slug>.md` into that bot's platform profile, on the platform's own screen.
5. The builder runs `fleet/scripts/build-prompt.sh --mark-deployed <slug>` for each bot that was pasted.

An edit to one bot's action index between releases is a smaller ask for that bot. It is not a second kit approval. The same changelog command shows it.

Scripts never write the profile. `--mark-deployed` only updates the manifest, and only after a build that matches the files.

## Stale and drift

`fleet/scripts/build-prompt.sh --check` prints a short summary. `--json` prints the same facts as JSON on stdout and the summary on stderr. The exit code is non-zero when any compiled bot is stale or the live profile text does not match.

- **Stale** means the built snapshot differs from the deployed snapshot, or the hashed inputs differ from what was last built, or the prompt was never built or is over the cap.
- **Drift** means `description` in `<profiles-dir>/<id>/profile.json` is not the deployed prompt. `<id>` is the bot's id in `local/fleet.json`. The default directory is `/home/box/agent-data/agents`. Set `BOT_FLEET_PROFILES_DIR` to point somewhere else. A missing directory is reported and is not a failure. A description that differs is a failure.

File-mode bots are listed and are not stale. Retired bots are skipped.

## Manifest

`local/prompts/<slug>.manifest.json` has `built` and `deployed`.

`built` records each input's id, `prompt_version` (null for a fleet-local rule), and digest sha256; the hashes of `rules.md`, `ACTIONS.md`, and `SHARED-SKILLS.md` at the build that changed inputs; the role map; the kit version; the git commit; and `built_at`.

`deployed` is a copy of `built`, written only by `--mark-deployed`. Until that runs, the bot is stale.

## Upgrade

From 0.11.0:

```
BOT_ROLE=manager fleet/scripts/upgrade.sh 0.12.0 --dry-run
BOT_ROLE=manager fleet/scripts/upgrade.sh 0.12.0
```

The migration sets `prompt_mode` to `files` when the key is absent. It does not build prompts and it does not deploy any. Re-render each thin prompt and re-paste it with the owner's yes so the safe-pull sentence is what the bot sees. Turn on `compiled` later, for one bot first, using the approval steps above.
