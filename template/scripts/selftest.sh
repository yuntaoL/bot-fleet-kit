#!/usr/bin/env bash
# Usage: template/scripts/selftest.sh [--keep]
# Scratch-clone end-to-end test of the two-phase bootstrap (git side), run from any checkout of the template or a fleet.
# Builds a throwaway template repo + private fleet repo under a temp dir with fake owner "Alex Test" and bots
# Atlas (manager) / Forge (builder) / Pip (worker), then: phase 1 (bootstrap-fleet.md), rerun no-op, phase 2
# (convert-to-fleet-bot.md) incl. one forced rollback, strict required-role validation. Touches nothing outside the temp dir.
# Platform steps (creating bots, changing prompts) cannot be scripted and are simulated by state/registry changes.
set -euo pipefail
SRC="$(git rev-parse --show-toplevel)"; KEEP=${1:-}
T="$(mktemp -d)"; [ "$KEEP" = --keep ] || trap 'rm -rf "$T"' EXIT
ok(){ echo "PASS $*"; }; die(){ echo "FAIL $*" >&2; exit 1; }
export GIT_AUTHOR_NAME=selftest GIT_AUTHOR_EMAIL=selftest@example.invalid GIT_COMMITTER_NAME=selftest GIT_COMMITTER_EMAIL=selftest@example.invalid
export GIT_CONFIG_GLOBAL="$T/gitconfig"; git config --global init.defaultBranch main; git config --global user.name selftest; git config --global user.email selftest@example.invalid
# 0. role defaults never use bare docs/ paths (roles are read from the fleet root, docs live at template/docs/)
! grep -nE '(^|[^/[:alnum:]_])docs/' "$SRC"/template/defaults/roles/*.md || die "bare docs/ path in template/defaults/roles (use template/docs/)"; ok "role defaults use template/docs/ paths"
# 1. throwaway public template (only template-repo paths) + tag
mkdir -p "$T/tpl"; (cd "$SRC" && tar -cf - template .github README.md LICENSE $( [ -d examples ] && echo examples ) 2>/dev/null) | tar -x -C "$T/tpl"
V="$(cat "$T/tpl/template/VERSION")"
git -C "$T/tpl" init -q && git -C "$T/tpl" add -A && BOT_FLEET_UPGRADE=1 git -C "$T/tpl" commit -qm "template v$V" --no-verify && git -C "$T/tpl" tag "v$V"
git clone -q --bare "$T/tpl" "$T/bot-fleet-template.git"
# 2. "Use this template" -> private fleet repo (fresh history)
mkdir -p "$T/seed" && git -C "$T/tpl" archive HEAD | tar -x -C "$T/seed"
git -C "$T/seed" init -q && git -C "$T/seed" add -A && git -C "$T/seed" commit -qm "Initial commit" --no-verify
git clone -q --bare "$T/seed" "$T/my-fleet.git"
H="$T/home"; mkdir -p "$H"; export BOT_FLEET_WORKTREES="$H/bot-fleet-worktrees"
git clone -q "$T/my-fleet.git" "$H/bot-fleet"; cd "$H/bot-fleet"
# ---- phase 1 (bootstrap-fleet.md) ----
template/scripts/bootstrap.sh "$T/bot-fleet-template.git" >/dev/null && git push -q origin HEAD:main; ok "bootstrap.sh"
python3 - <<'PY'
import json; p="manager/fleet.json"; f=json.load(open(p)); f["owner"]="alextest"; f["owner_name"]="Alex Test"
f["bots"]=[{"slug":"atlas","name":"Atlas","id":"fake-atlas","role":"manager","status":"pre-fleet"},
           {"slug":"forge","name":"Forge","id":"fake-forge","role":"builder","status":"pre-fleet"}]
json.dump(f,open(p,"w"),indent=2); open(p,"a").write("\n")
PY
for s in atlas forge; do [ -d bots/$s ] || cp -r template/defaults/bot bots/$s; rm -f bots/$s/routines/example.json
  python3 -c "import json;p='bots/$s/state.json';d=json.load(open(p));d['bootstrap']={'phase':1,'step':'env','status':'in-progress'};json.dump(d,open(p,'w'),indent=2)"; done
git add -A && BOT_ROLE=manager git commit -qm "manager: phase 1 fleet entries" && git push -q origin HEAD:main; ok "fleet entries (pre-fleet)"
template/scripts/worktree.sh --all >/dev/null; mkdir -p "$H/bot-logs" "$H/fleet-snapshots"
for s in atlas forge; do [ "$(git -C "$BOT_FLEET_WORKTREES/$s" config fleet.bot)" = $s ] || die "identity $s"; done; ok "worktrees + identity"
for s in atlas forge; do (cd "$BOT_FLEET_WORKTREES/$s" && template/scripts/render-prompt.sh $s >/dev/null); done
P="$BOT_FLEET_WORKTREES/atlas/bots/atlas/THIN-PROMPT.md"
grep -q "You are Atlas, one bot in Alex Test's fleet." "$P" || die "rendered prompt (atlas)"
grep -q "You are Forge, one bot in Alex Test's fleet." "$BOT_FLEET_WORKTREES/forge/bots/forge/THIN-PROMPT.md" || die "rendered prompt (forge)"
! grep -q '{{' "$BOT_FLEET_WORKTREES"/*/bots/*/THIN-PROMPT.md || die "unfilled placeholder"; ok "render-prompt (Alex Test, no {{...}})"
for s in atlas forge; do (cd "$BOT_FLEET_WORKTREES/$s" && python3 -c "import json,datetime;p='bots/$s/state.json';d=json.load(open(p));d['bootstrap']={'phase':1,'step':'done','status':'done','updated':datetime.datetime.now(datetime.timezone.utc).isoformat()};json.dump(d,open(p,'w'),indent=2)" && template/scripts/sync.sh "phase 1 done" "bots/$s/" >/dev/null); done; ok "sync.sh as each bot"
(cd "$BOT_FLEET_WORKTREES/atlas" && git pull -q --ff-only && template/scripts/validate.sh --pre-fleet >/dev/null) || die "validate --pre-fleet"; ok "validate.sh --pre-fleet"
# rerun is a no-op
git pull -q --ff-only; before="$(git rev-parse HEAD)"
template/scripts/bootstrap.sh "$T/bot-fleet-template.git" >/dev/null; template/scripts/worktree.sh --all >/dev/null
[ "$(git rev-parse HEAD)" = "$before" ] && [ -z "$(git status --porcelain)" ] || die "rerun not a no-op"; ok "phase 1 rerun is a no-op"
# ---- phase 2 (convert-to-fleet-bot.md) ----
reg(){ (cd "$BOT_FLEET_WORKTREES/atlas" && git pull -q --ff-only && python3 -c "import json;p='manager/fleet.json';f=json.load(open(p));[b.update(status='$2') for b in f['bots'] if b['slug']=='$1'];json.dump(f,open(p,'w'),indent=2)" && template/scripts/sync.sh "$1 -> $2" manager/ >/dev/null); }
conv(){ s=$1; reg $s converting; (cd "$BOT_FLEET_WORKTREES/$s" && git pull -q --ff-only && mkdir -p bots/$s/kb && printf -- '---\ntype: memory\nupdated: today\n---\n# copied memory\n' > bots/$s/kb/memory.md \
  && python3 -c "import json;p='bots/$s/state.json';d=json.load(open(p));d['bootstrap']={'phase':2,'step':'verify','status':'in-progress','snapshot':'scratch','rollbackHolder':'$2','verifiedRuns':5};json.dump(d,open(p,'w'),indent=2)" \
  && template/scripts/sync.sh "convert: copy memory, 5 verified runs" >/dev/null); }
conv atlas forge; reg atlas active; ok "manager converted (rollback holder: builder)"
conv forge atlas; c="$(git -C "$BOT_FLEET_WORKTREES/forge" rev-parse HEAD)"
(cd "$BOT_FLEET_WORKTREES/forge" && git revert --no-edit "$c" >/dev/null && git push -q origin HEAD:main) || die "rollback revert"
reg forge pre-fleet; [ ! -f "$BOT_FLEET_WORKTREES/forge/bots/forge/kb/memory.md" ] || die "rollback left files"; ok "forced rollback of builder (git revert, status pre-fleet)"
conv forge atlas; reg forge active; ok "builder converted after rollback (rollback holder: manager)"
# a builder-created worker
(cd "$BOT_FLEET_WORKTREES/atlas" && git pull -q --ff-only && python3 -c "import json;p='manager/fleet.json';f=json.load(open(p));f['bots'].append({'slug':'pip','name':'Pip','id':'fake-pip','role':'worker','status':'active'});json.dump(f,open(p,'w'),indent=2)" \
  && cp -r template/defaults/bot bots/pip && rm bots/pip/routines/example.json && template/scripts/render-prompt.sh pip >/dev/null && template/scripts/sync.sh "add pip" manager/ bots/pip/ >/dev/null); ok "new worker added + rendered"
(cd "$BOT_FLEET_WORKTREES/atlas" && git pull -q --ff-only && BOT_FLEET_STRICT_ROLES=1 template/scripts/validate.sh >/dev/null) || die "strict validate after phase 2"; ok "validate.sh strict roles after phase 2"
# negative checks
(cd "$BOT_FLEET_WORKTREES/atlas" && python3 -c "import json;p='manager/fleet.json';f=json.load(open(p));[b.update(status='paused') for b in f['bots'] if b['role']=='builder'];json.dump(f,open(p,'w'),indent=2)" \
  && ! BOT_FLEET_STRICT_ROLES=1 template/scripts/validate.sh >/dev/null 2>&1 && template/scripts/validate.sh 2>&1 | grep -c "WARN required roles" >/dev/null && git checkout -q manager/fleet.json) || die "required-role invariant"
(cd "$BOT_FLEET_WORKTREES/atlas" && echo '{{OWNER_NAME}}' >> bots/atlas/THIN-PROMPT.md && ! template/scripts/validate.sh >/dev/null 2>&1 && git checkout -q bots/atlas/THIN-PROMPT.md) || die "placeholder check"
(cd "$BOT_FLEET_WORKTREES/forge" && echo x > bots/atlas/x.md && git add bots/atlas/x.md; r=0; git commit -qm "forge: write atlas" >/dev/null 2>&1 || r=1; git reset -q; rm -f bots/atlas/x.md; [ $r = 1 ]) || die "ownership hook"
(cd "$BOT_FLEET_WORKTREES/atlas" && echo "- local edit" >> manager/roles/worker.md && { out="$(template/scripts/validate.sh 2>&1)"; grep -q "WARN role drift: manager/roles/worker.md" <<<"$out"; } \
  && ! BOT_FLEET_STRICT_ROLES=1 template/scripts/validate.sh >/dev/null 2>&1 && git checkout -q manager/roles/worker.md) || die "role drift check"
# rename (0.9.1, rename-bot skill): pip -> wren, folder + worktree + branch
A="$BOT_FLEET_WORKTREES/atlas"; R=template/scripts/rename-bot.sh
(cd "$A" && git pull -q --ff-only && template/scripts/worktree.sh pip >/dev/null && h="$(git rev-parse HEAD)" && $R pip wren expand --dry-run >/dev/null && $R pip wren worktree --dry-run >/dev/null \
  && [ "$(git rev-parse HEAD)" = "$h" ] && [ ! -e bots/wren ] && [ -d "$BOT_FLEET_WORKTREES/pip" ]) || die "rename dry-run changed something"
(cd "$A" && python3 -c "import json;p='manager/fleet.json';f=json.load(open(p));[b.update(slug='wren',name='Wren',previousSlugs=['pip']) for b in f['bots'] if b['slug']=='pip'];json.dump(f,open(p,'w'),indent=2)" \
  && template/scripts/sync.sh "rename pip -> wren (registry)" manager/ >/dev/null) || die "rename registry"
(cd "$BOT_FLEET_WORKTREES/forge" && git pull -q --ff-only && BOT_RESTORE=1 $R pip wren expand >/dev/null && git push -q origin HEAD:main) || die "rename expand"
(cd "$A" && git pull -q --ff-only && $R pip wren worktree >/dev/null) || die "rename worktree"
W="$BOT_FLEET_WORKTREES/wren"; [ -d "$W" ] && [ ! -e "$BOT_FLEET_WORKTREES/pip" ] && [ "$(git -C "$W" config fleet.bot)" = wren ] && [ "$(git -C "$W" branch --show-current)" = wt/wren ] || die "rename worktree result"
(cd "$W" && git pull -q --ff-only && template/scripts/render-prompt.sh wren >/dev/null && grep -q "You are Wren" bots/wren/THIN-PROMPT.md && template/scripts/sync.sh "re-render" bots/wren/ >/dev/null \
  && BOT_NAME=pip $R pip wren contract >/dev/null && git push -q origin HEAD:main && [ ! -e bots/pip ]) || die "rename contract"
(cd "$A" && git pull -q --ff-only && out="$(BOT_FLEET_STRICT_ROLES=1 template/scripts/validate.sh 2>&1)" && ! grep -q "WARN worktree" <<<"$out" \
  && [ "$($R pip wren refs)" = "rename-bot: no references" ]) || die "validate/refs after rename"
ok "rename pip -> wren (dry-run no-op, registry, expand, worktree+branch move, re-render, contract, validate clean)"
# negative: worktree dir != fleet.bot warns (used to be skipped silently)
(cd "$A" && git worktree move "$W" "$BOT_FLEET_WORKTREES/wren-old" && { out="$(template/scripts/validate.sh 2>&1)"; grep -q "WARN worktree dir .*wren-old != fleet.bot 'wren'" <<<"$out"; } \
  && git worktree move "$BOT_FLEET_WORKTREES/wren-old" "$W") || die "worktree dir mismatch check"
# rename drift (owner renamed a bot in the app): read-only DRIFT, nothing changed
PR="$T/profiles"; for b in atlas:Atlas forge:Forge wren:Wren; do mkdir -p "$PR/fake-${b%%:*}"; echo "{\"name\":\"${b#*:}\"}" > "$PR/fake-${b%%:*}/profile.json"; done
(cd "$A" && template/scripts/check-names.sh "$PR" >/dev/null) || die "check-names clean"
echo '{"name":"Robin"}' > "$PR/fake-wren/profile.json"
(cd "$A" && h="$(git rev-parse HEAD)"; r=0; out="$(template/scripts/check-names.sh "$PR")" || r=$?; [ $r = 3 ] && grep -q "DRIFT wren: fleet.json name 'Wren' != live name 'Robin'" <<<"$out" \
  && [ "$(git rev-parse HEAD)" = "$h" ] && [ -z "$(git status --porcelain)" ]) || die "check-names drift"
ok "rename drift: check-names clean, then DRIFT (exit 3) with old+new names, repo unchanged"
ok "negative checks (no active builder warns/fails strict; leftover {{...}} fails; role drift warns/fails strict; cross-bot write blocked; worktree dir mismatch warns)"
echo "selftest: ALL PASS ($T)"
