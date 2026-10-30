# Routine runs (template-owned)

Every scheduled routine run follows this file. The live routine prompt only names the bot, its worktree and the routine; everything a run does is here and in the routine's own file in git.

1. **Worktree.** Work only in your own worktree. Run `git pull --ff-only` there first. Your role is your entry in `manager/fleet.json`.
2. **Read the rules, in order** (same list as the thin prompt): `template/rules/common.md`, `manager/overrides.md`, `manager/local/*.md` (top-level files only), `manager/roles/<role>.md`, `manager/local/roles/<role>.md` if it exists, `bots/<slug>/rules.md`, `bots/<slug>/instructions.md` if it exists, `bots/<slug>/state.json`, and `bots/<slug>/kb/INDEX.md` if it exists. Follow them. Precedence: the owner's direct instruction now > common > overrides > role > bot rules.
3. **Find and follow the routine.** Open `bots/<slug>/routines/<routine>.json` and follow its `steps`, and the `stepsFile` it points to if set. If it has neither, follow its legacy `prompt` field. The routine's steps win over the defaults in this file where they say so.
4. **Journal every run**, skips, no-ops and failures included: one line in `bots/<slug>/journal/` (or the fleet's log mechanism named in `manager/local/`) saying what happened. The line ends with a `read:` field listing what you read, `|`-separated, and it must include the routine marker: `routine:<stepsFile name>` if the routine has a `stepsFile`, else `routine:<routine>.json`. Example: `read: rules|state|instructions|routine:daily-check.json`. A run line without the marker did not follow this file.
5. **Save** with `template/scripts/sync.sh "<routine <routine>: result>"`.
6. **Stay quiet** when nothing changed: no message to the owner or other bots, unless the steps say otherwise.
7. **Leave the schedule alone.** Never change, pause or delete the routine's own schedule unless its steps say so (for example "pause this routine when the queue is empty").
8. **Fail safe.** If the worktree, this file or the routine file can't be read: do nothing irreversible, never send, buy or delete, and report that the fleet repo could not be read through one channel: message the manager; only if you are the manager or it cannot be reached, tell the owner.
