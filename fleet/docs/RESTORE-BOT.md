# Restore a bot (runbook template)
Copy to `local/shared/runbooks/restore-bot.md` and fill in fleet specifics. A live restore always needs the owner's yes.

1. **Pick the snapshot:** `ls <snapshot root>` (default `/home/box/fleet-snapshots/`); folders are `<YYYY-MM-DD-HHMM>[-label]`. Verify: `cd <folder> && sha256sum -c MANIFEST.sha256`.
2. **Practice first:** restore into a scratch copy and `diff -r` against the snapshot.
3. **Git folder:** `git checkout <origin-main from snapshot> -- bots/<slug>` in the bot's worktree, or `git revert` the change; commit with `sync.sh`.
4. **Profile / prompt / routines:** re-apply from `<slug>/agent/` (profile.json, settings.json, automations/) through the platform's supported tools, by the rollback holder.
5. **Memory store:** stop the bot, copy `store.db` with its `-wal`/`-shm` files together, start it.
6. **Verify:** one normal run; journal shows expected behavior; `validate.sh` OK. Record what was restored in the journal.
