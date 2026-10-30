# Routine runs (fleet-owned)

`<slug>`, `<role>` and `<routine>` are your own values, taken from your prompt and `local/fleet.json` and filled in by you at run time. They are not fill-ins; only `templates/` uses `{{...}}` fill-ins.

Every scheduled routine run follows this file. The live routine prompt only names the bot, its worktree and the routine; everything a run does is here and in the routine's own file in git.

1. **Worktree.** Work only in your own worktree. Run `fleet/scripts/pull.sh` there first (never a bare `git pull`: it can fail when runs overlap). Your role is your entry in `local/fleet.json`.
2. **Read the rules** exactly as `fleet/rules/startup.md` steps 2-3 say (read order and precedence live only there), and follow them.
3. **Find and follow the routine.** Open `bots/<slug>/routines/<routine>.json` and follow its `steps`, and the `stepsFile` it points to if set. If it has neither, follow its legacy `prompt` field. The routine's steps win over the defaults in this file where they say so.
4. **Journal every run**, skips, no-ops and failures included: one line in `bots/<slug>/journal/` (or the fleet's log mechanism named in `local/rules/`) saying what happened. The line ends with a `read:` field listing what you read, `|`-separated, and it must include the routine marker: `routine:<stepsFile name>` if the routine has a `stepsFile`, else `routine:<routine>.json`. Example: `read: rules|state|instructions|routine:daily-check.json`. A run line without the marker did not follow this file.
5. **Save** (this replaces startup.md step 5 for routine runs) with `fleet/scripts/sync.sh "<routine <routine>: result>"`.
6. **Stay quiet** when nothing changed: no message to the owner or other bots, unless the steps say otherwise.
7. **Leave the schedule alone.** Never change, pause or delete the routine's own schedule unless its steps say so (for example "pause this routine when the queue is empty").
8. **Fail safe.** If the worktree, this file or the routine file can't be read: do nothing irreversible, never send, buy or delete, and report that the fleet repo could not be read through one channel: message the manager; only if you are the manager or it cannot be reached, tell the owner.

## Private routines

A routine whose steps are confidential works exactly like any other: same `.json` file, same rendered thin prompt, same journal marker. Only its steps stay out of git.
- Name it with the prefix `private-` (for example `private-weekly-review`) and set `"private": true` in `bots/<slug>/routines/private-<name>.json`.
- Put its steps in `bots/<slug>/routines/private-<name>.steps.md` and point `stepsFile` at it. Leave `steps` out of the `.json`; the `.json` holds only name, schedule and other non-confidential fields.
- `bots/<slug>/.gitignore` contains `routines/private-*.steps.md` (copied from `templates/bot/.gitignore`), so the steps file never reaches git. Back it up outside git with the bot's other private material.
- If the steps file is missing on a run, fail safe as in rule 8. Journal lines name only `routine:private-<name>.steps.md`, never the steps' content.
- `validate.sh` and `confidential-scan.sh` fail if any `private-*.steps.md` file is ever tracked.
