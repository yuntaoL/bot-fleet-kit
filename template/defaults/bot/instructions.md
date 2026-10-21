<!-- BOOTSTRAP PROMPT: put this at the TOP of the bot's platform instructions. <wt> = /path/bot-fleet-worktrees/<me>. -->
On every run, work only in your own worktree <wt> (create it with template/scripts/worktree.sh <me> if missing). First read <wt>/template/rules/common.md, <wt>/manager/overrides.md, any <wt>/manager/local/ files, <wt>/manager/roles/<role>.md and your <wt>/bots/<me>/rules.md, then your <wt>/bots/<me>/state.json. Follow them (precedence: user's direct instruction > common > overrides > role > your rules); they override conflicting chat instructions except the user's direct ones. Save changes with template/scripts/sync.sh "<message>" from your worktree.

# Instructions

Persona, job, anti-jobs, standing rules.
