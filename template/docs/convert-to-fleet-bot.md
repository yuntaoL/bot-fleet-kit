# Convert a bot into a fleet bot (phase 2, one bot at a time)

Used by the manager (for itself), the builder (for itself) and later for any existing platform bot joining the fleet. Pattern: **expand, then contract** — the new git-first path is added beside the old one and the old one is removed only after verified runs. Prompt support lands before content moves; content is copied, never moved.

Before starting, name the **rollback holder** (a different, working bot, plus the user) and get the user's yes. Record every step in `bots/<slug>/state.json` `bootstrap` (`phase: 2`).

1. **Snapshot.** `template/scripts/snapshot-fleet.sh pre-convert-<slug>` (profile, settings, routines, memory store, git folder; outside git). Record the path in `bootstrap.snapshot` and `rollbackHolder`.
2. **Registry.** `manager/fleet.json` status `pre-fleet` → `converting` (manager commits).
3. **Copy knowledge in.** Copy (do not delete anything from the platform) the bot's durable memory, rules and routine definitions into `bots/<slug>/` (`rules.md`, `kb/`, `routines/*.json`, `state.json`). Keep confidential items out of git (`confidential-scan.sh` runs on every commit).
4. **Expand the prompt.** `template/scripts/render-prompt.sh <slug>`; with the user's yes set the platform prompt to the rendered `THIN-PROMPT.md` **followed by** the old prompt under a heading "Fallback (old prompt; git wins on conflict)".
5. **Verify N runs (default 5).** Each run must read from git and save back with `sync.sh`; the rollback holder checks evidence (commits, files) and increments `bootstrap.verifiedRuns`.
6. **Contract.** With the user's yes, remove the fallback block; status `converting` → `active`; `bootstrap.status: done`.

**Rollback** (any failed run, or the user says stop): the rollback holder restores the platform prompt/profile from the snapshot (`RESTORE-BOT.md`), sets status back to `pre-fleet`, `bootstrap.status: rolled-back`, and reverts the conversion commits with `git revert` (never force-push).
