#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# tests/test_migrate_runner.sh — the migration runner, scripts/sumela-migrate.sh (R1-08).
#
# A release ships machine-readable notes (scripts/sumela-migrations/upgrade.md and <X.Y.Z>.md);
# the consumer's agent runs them with the runner: plan, then show, run, verify and record per
# step. This suite builds synthetic upstreams (tagged repositories whose notes run small tools),
# clones of them, and synthetic projects whose .sumela/upstream.conf names the upstream, and pins:
#   - the format and the lint (required keys, ids, requires, expect forms, placeholders, the
#     strict read-only shapes behind consent: none, for run, run.ps1, verify and verify.ps1,
#     in plain ASCII words only: every refused character class on its own), CRLF-tolerant;
#   - the selection: phase, version (from exclusive), id, requires; post-update steps after the
#     apply stamps VERSION; developer steps a teammate skipped; until; declined steps listed; a
#     resumed session; a 0.19 -> latest jump with {TARGET} in one worktree [RU-I1][RU-I2];
#   - the guards: requires met only by done; repo steps only in the upgrade worktree, never after
#     it is gone, on a branch that tracks nothing else; a fail-closed consent gate, run: - steps
#     included; verification by artifact; both ledgers; pre-satisfied developer steps through
#     the read-only gate only; rollback that removes the ledger entry first and restores it on
#     failure; the state kept until the merge reaches the main checkout, then retired;
#   - the trust checks: a clean clone of the project's upstream (or the --trust-origin URL) at an
#     annotated release tag that this URL confirms (an RC is accepted), none of the clone's own
#     git configuration trusted (fsmonitor, insteadOf), notes read from regular blobs at HEAD,
#     installed notes unmodified, --allow-untagged only with SUMELA_MIGRATE_ALLOW_UNTAGGED,
#     credentials never printed, control characters refused [RU-M10]; paths with spaces and
#     quotes reach the steps intact.
#
# Every fixture lives under one temporary directory; the state directory is redirected there.
# Run from anywhere:  bash tests/test_migrate_runner.sh
# Exit 0 = all assertions passed, 1 = a failure (printed above).
# -----------------------------------------------------------------------------
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNNER="$REPO_ROOT/scripts/sumela-migrate.sh"
[ -f "$RUNNER" ] || { echo "FAIL: $RUNNER missing"; exit 1; }
# shellcheck source=../scripts/lib/sumela-provenance.sh
. "$REPO_ROOT/scripts/lib/sumela-provenance.sh"
# shellcheck source=../scripts/lib/sumela-state.sh
. "$REPO_ROOT/scripts/lib/sumela-state.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
WORK="$(cd "$WORK" && pwd -P)"

PASS=0 FAIL=0
ok()   { echo "  PASS  $1"; PASS=$((PASS + 1)); }
bad()  { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); }
same() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }
has()  { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 (wanted '$3' in:"; printf '%s\n' "$2" | tail -15 | sed 's/^/        /'; echo "        )" ;; esac; }
lacks() { case "$2" in *"$3"*) bad "$1 (did not want '$3' in:"; printf '%s\n' "$2" | tail -15 | sed 's/^/        /'; echo "        )" ;; *) ok "$1" ;; esac; }
# rc_is <label> <expected>: checks $RC from the last m call, and shows its output on a mismatch
rc_is() { if [ "$RC" = "$2" ]; then ok "$1"; else bad "$1 (expected exit $2, got $RC; output:"; printf '%s\n' "$OUT" | tail -20 | sed 's/^/        /'; echo "        )"; fi; }
mode_of() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }

case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) ON_WINDOWS=true ;; *) ON_WINDOWS=false ;; esac
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_PREFIX
export XDG_STATE_HOME="$WORK/state"
if [ "$ON_WINDOWS" = true ]; then
  mkdir -p "$WORK/localappdata"; LOCALAPPDATA="$(cygpath -w "$WORK/localappdata")"; export LOCALAPPDATA
fi
export GIT_ALLOW_PROTOCOL="file:https:ssh:git"     # the fixtures' upstreams are local paths
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=t@example.com
g() { git -c commit.gpgsign=false -c tag.gpgsign=false -c core.hooksPath="$WORK/no-hooks" -c init.defaultBranch=main "$@"; }

# m <dir> <args...>: runs the runner from <dir>; $OUT holds stdout and stderr, $RC the exit code
m() { local d="$1"; shift; OUT="$(cd "$d" && bash "$RUNNER" "$@" 2>&1)"; RC=$?; }
# pending_ids: the ids of the "pending" lines of the last plan, space-separated
pending_ids() { printf '%s\n' "$OUT" | LC_ALL=C sed -n 's/^    \([^ ]*\)  .*consent=.*/\1/p' | tr '\n' ' ' | sed 's/ $//'; }

# --- Fixtures ----------------------------------------------------------------------------------
write_tools() {  # <dir>: the commands the synthetic notes run (from the step's checkout)
  mkdir -p "$1/tools"
  cat > "$1/tools/step.sh" <<'EOF'
#!/usr/bin/env bash
# step.sh <name>: one step's effect, in the step's checkout
printf '%s\n' "$1" >> order.log
: > "done-$1"
echo "step $1 ran"
EOF
  cat > "$1/tools/dryrun.sh" <<'EOF'
#!/usr/bin/env bash
# dryrun.sh --plan: the dry run, recorded as plan-<release>; --plan-check: its artifact (read-only)
v="$(tr -d '\r\n' < "$SUMELA_MIGRATE_SRC/.sumela/VERSION")"
if [ "${1:-}" = --plan-check ]; then if [ -f "done-plan-$v" ]; then echo ok; else echo "missing done-plan-$v"; fi; exit 0; fi
printf '%s\n' "plan-$v" >> order.log; : > "done-plan-$v"; echo "dry run for $v"
EOF
  cat > "$1/tools/validate.sh" <<'EOF'
#!/usr/bin/env bash
# validate.sh --check: the validation, recorded as validate-<release>; --status: its artifact (read-only)
v="$(tr -d '\r\n' < "$SUMELA_MIGRATE_SRC/.sumela/VERSION")"
if [ "${1:-}" = --status ]; then if [ -f "done-validate-$v" ]; then echo ok; else echo "missing done-validate-$v"; fi; exit 0; fi
printf '%s\n' "validate-$v" >> order.log; : > "done-validate-$v"; echo "validated $v"
EOF
  cat > "$1/tools/check.sh" <<'EOF'
#!/usr/bin/env bash
# check.sh <name>: the artifact step.sh leaves
if [ -f "done-$1" ]; then echo ok; else echo "missing done-$1"; fi
EOF
  cat > "$1/tools/apply.sh" <<'EOF'
#!/usr/bin/env bash
# apply.sh <version>: the apply step stamps VERSION
printf '%s\n' "apply-$1" >> order.log
: > "done-apply-$1"
printf '%s\n' "$1" > .sumela/VERSION
EOF
  cat > "$1/tools/args.sh" <<'EOF'
#!/usr/bin/env bash
# args.sh: its arguments, one per line, and the two runner variables
for a in "$@"; do printf 'arg=%s\n' "$a"; done
printf 'src=%s\nroot=%s\n' "$SUMELA_MIGRATE_SRC" "$SUMELA_MIGRATE_ROOT"
EOF
  cat > "$1/tools/step.ps1" <<'EOF'
# step.ps1 <name>: step.sh for the PowerShell runner (the same bytes)
param([string]$Name)
$utf8 = New-Object System.Text.UTF8Encoding $false
[IO.File]::AppendAllText((Join-Path (Get-Location).ProviderPath 'order.log'), "$Name`n", $utf8)
[IO.File]::WriteAllText((Join-Path (Get-Location).ProviderPath "done-$Name"), '', $utf8)
Write-Output "step $Name ran"
EOF
  cat > "$1/tools/check.ps1" <<'EOF'
# check.ps1 <name>: check.sh for the PowerShell runner
param([string]$Name)
if (Test-Path -LiteralPath (Join-Path (Get-Location).ProviderPath "done-$Name")) { Write-Output 'ok' } else { Write-Output "missing done-$Name" }
EOF
}

# The generic procedure, shaped like the shipped upgrade.md (7 steps; 07 is ledger: none).
write_generic() {  # <notes dir>
  mkdir -p "$1"
  cat > "$1/upgrade.md" <<'EOF'
# Synthetic upgrade procedure

```sumela-step
id: upgrade-01
title: Create the upgrade worktree for v{TARGET}
scope: repo
when: pre-update
consent: confirm
run: -
verify: git -C "{ROOT}" rev-parse --abbrev-ref HEAD
expect: match:upgrade-{TARGET}$
rollback: b="$(git -C "{ROOT}" rev-parse --abbrev-ref HEAD)" && c="$(git -C "{ROOT}" rev-parse --path-format=absolute --git-common-dir)" && cd "$c/.." && git worktree remove --force "{ROOT}" && git branch -D "$b"
agent: git worktree add --no-track -b <prefix>upgrade-{TARGET} <worktree> <base>, then set prefix= base= worktree=
```

```sumela-step
id: upgrade-02
title: Dry run
scope: repo
when: pre-update
requires: upgrade-01
consent: none
run: bash "{SRC}/tools/dryrun.sh" --plan
verify: bash "{SRC}/tools/dryrun.sh" --plan-check
expect: equals:ok
```

```sumela-step
id: upgrade-03
title: Apply
scope: repo
when: update
requires: upgrade-02
consent: confirm
run: bash "{SRC}/tools/apply.sh" "{TARGET}"
verify: bash "{SRC}/tools/check.sh" "apply-{TARGET}"
expect: equals:ok
rollback: bash -c "rm -f done-apply-{TARGET}"
```

```sumela-step
id: upgrade-04
title: Parity
scope: repo
when: post-update
requires: upgrade-03
consent: confirm
run: bash "{SRC}/tools/step.sh" "parity-{TARGET}"
run.ps1: & "{SRC}/tools/step.ps1" "parity-{TARGET}"
verify: bash "{SRC}/tools/check.sh" "parity-{TARGET}"
verify.ps1: & "{SRC}/tools/check.ps1" "parity-{TARGET}"
expect: equals:ok
rollback: bash -c "exit 7"
```

```sumela-step
id: upgrade-05
title: Mirrors
scope: repo
when: post-update
requires: upgrade-03
consent: confirm
run: bash "{SRC}/tools/step.sh" "mirrors-{TARGET}"
verify: bash "{SRC}/tools/check.sh" "mirrors-{TARGET}"
expect: equals:ok
```

```sumela-step
id: upgrade-06
title: Validate
scope: repo
when: post-update
requires: upgrade-04
consent: none
run: bash "{SRC}/tools/validate.sh" --check
verify: bash "{SRC}/tools/validate.sh" --status
expect: equals:ok
```

```sumela-step
id: upgrade-07
title: Commit
scope: repo
when: finalize
requires: upgrade-06
consent: confirm
ledger: none
run: -
verify: git -C "{ROOT}" log -1 --format=%s
expect: match:upgrade to v{TARGET}
rollback: git -C "{ROOT}" reset --soft HEAD~1
agent: commit with a subject containing upgrade to v{TARGET}
```
EOF
}
# step_block <id> <scope> <when> <extra key: value lines...>: one step that runs step.sh v<id>
step_block() {
  local id="$1" sc="$2" wh="$3" l; shift 3
  printf '```sumela-step\nid: %s\ntitle: Step %s\nscope: %s\nwhen: %s\nconsent: confirm\n' "$id" "$id" "$sc" "$wh"
  for l in "$@"; do printf '%s\n' "$l"; done
  if [ "$sc" = repo ]; then
    printf 'run: bash "{SRC}/tools/step.sh" "v%s"\nverify: bash "{SRC}/tools/check.sh" "v%s"\n' "$id" "$id"
  else
    printf 'run: bash "{ROOT}/tools/step.sh" "v%s"\nverify: bash "{ROOT}/tools/check.sh" "v%s"\n' "$id" "$id"
  fi
  printf 'expect: equals:ok\n```\n\n'
}
# The composition notes: three versions' steps around the generic procedure.
write_compose() {  # <notes dir>
  write_generic "$1"
  { echo "# 0.20.0"; echo
    step_block 0.20.0-01 repo post-update
    step_block 0.20.0-02 developer first-session
    step_block 0.20.0-03 repo post-update "until: 0.20.2"; } > "$1/0.20.0.md"
  { echo "# 0.20.1"; echo
    step_block 0.20.1-01 repo post-update "requires: upgrade-04"
    step_block 0.20.1-02 repo update "requires: upgrade-02"; } > "$1/0.20.1.md"
  { echo "# 0.20.2"; echo
    step_block 0.20.2-01 repo pre-update "requires: upgrade-01"
    step_block 0.20.2-02 repo post-update; } > "$1/0.20.2.md"
}
# mk_release <dir> <version> <tag|-> <notes dir>: an upstream repository at a tagged commit
mk_release() {
  local d="$1" v="$2" tag="$3" notes="$4"
  mkdir -p "$d/.sumela" "$d/scripts/sumela-migrations"
  g init -q "$d"
  printf '%s\n' "$v" > "$d/.sumela/VERSION"
  printf '*.sh text eol=lf\n*.ps1 text eol=lf\n' > "$d/.gitattributes"
  cp "$notes"/*.md "$d/scripts/sumela-migrations/"
  write_tools "$d"
  g -C "$d" add -A && g -C "$d" commit -qm "release $v"
  [ "$tag" = - ] || g -C "$d" tag -a -m "release $tag" "$tag"
}
# src_of <release> -> <release>.clone: a clone of the upstream, at its HEAD, its tags fetched
src_of() {
  local r="$1" c="$1.clone" head
  head="$(git -C "$r" rev-parse HEAD)"
  [ -d "$c" ] || g clone -q -- "$r" "$c" 2>/dev/null
  g -C "$c" fetch -q --tags --force --prune --prune-tags origin 2>/dev/null
  g -C "$c" -c advice.detachedHead=false checkout -q --detach "$head"
  printf '%s' "$c"
}
# mk_project <dir> <version> [<notes dir>]: a project at <version>, its upstream $UP when set,
# the notes installed when given
mk_project() {
  local d="$1" v="$2"
  mkdir -p "$d/.sumela"
  g init -q "$d"
  printf '%s\n' "$v" > "$d/.sumela/VERSION"
  printf 'app\n' > "$d/app.txt"
  printf '*.sh text eol=lf\n*.ps1 text eol=lf\n' > "$d/.gitattributes"
  printf '.sumela/.last-update.json\n' > "$d/.gitignore"
  [ -n "${UP:-}" ] && printf '# upstream\n%s\n' "$UP" > "$d/.sumela/upstream.conf"
  if [ $# -ge 3 ]; then mkdir -p "$d/scripts/sumela-migrations"; cp "$3"/*.md "$d/scripts/sumela-migrations/"; write_tools "$d"; fi
  g -C "$d" add -A && g -C "$d" commit -qm "project at $v"
}
# do_worktree <project> <worktree> <target>: upgrade-01's agent instruction, scripted
do_worktree() {
  g -C "$1" worktree add -q --no-track -b "sumela/upgrade-$3" "$2" main >/dev/null 2>&1
  m "$1" set prefix=sumela/ base=main "worktree=$2"
}
# step_through <project> <ids...>: show, run (or the scripted equivalent), verify, record done
STEP_LOG=""
step_through() {
  local p="$1" id; shift
  for id in "$@"; do
    m "$p" show "$id"; [ "$RC" = 0 ] || { STEP_LOG="$STEP_LOG show $id: exit $RC ($OUT);"; continue; }
    case "$id" in
      upgrade-01) do_worktree "$p" "$WT" "$TGT" ;;
      upgrade-07) (cd "$WT" && g add -A && g commit -qm "chore(sumela): upgrade to v$TGT") >/dev/null 2>&1; RC=0 ;;
      *) m "$p" run "$id" ;;
    esac
    [ "$RC" = 0 ] || { STEP_LOG="$STEP_LOG run $id: exit $RC ($OUT);"; continue; }
    m "$p" verify "$id"; [ "$RC" = 0 ] || { STEP_LOG="$STEP_LOG verify $id: exit $RC ($OUT);"; continue; }
    m "$p" record "$id" done; [ "$RC" = 0 ] || STEP_LOG="$STEP_LOG record $id: exit $RC ($OUT);"
  done
}
state_of() { cat "$1/.sumela/.upgrade/migrate.state" 2>/dev/null; }

NOTES="$WORK/notes"; write_compose "$NOTES"
GEN="$WORK/notes-generic"; write_generic "$GEN"
{ step_block 0.20.0-01 repo post-update; } > "$GEN/0.20.0.md"

echo "Migration runner (scripts/sumela-migrate.sh)"

echo "== t_parse_and_validate_required_keys"
m "$REPO_ROOT" lint "$NOTES/upgrade.md" "$NOTES/0.20.0.md" "$NOTES/0.20.1.md" "$NOTES/0.20.2.md"
rc_is "the synthetic notes lint clean" 0
has "…each file is reported with its step count" "$OUT" "upgrade.md: ok (7 steps)"
has "…a version file too" "$OUT" "0.20.0.md: ok (3 steps)"
BADN="$WORK/bad"; mkdir -p "$BADN"; cp "$NOTES/upgrade.md" "$BADN/upgrade.md"
lint_case() {  # <label> <expected message> <file name> <content>
  printf '%s' "$4" > "$BADN/$3"
  m "$REPO_ROOT" lint "$BADN/$3"
  if [ "$RC" = 4 ]; then has "$1 → exit 4" "$OUT" "$2"; else bad "$1 → exit 4 (got $RC: $OUT)"; fi
  rm -f "$BADN/$3"
}
lint_ok() {  # <label> <file name> <content>
  printf '%s' "$3" > "$BADN/$2"
  m "$REPO_ROOT" lint "$BADN/$2"
  if [ "$RC" = 0 ]; then ok "$1"; else bad "$1 (exit $RC: $OUT)"; fi
  rm -f "$BADN/$2"
}
blk() { printf '```sumela-step\n%s\n```\n' "$1"; }
FULL='id: 0.21.0-01
title: T
scope: repo
when: post-update
consent: confirm
run: bash scripts/x.sh
verify: bash scripts/x.sh --check
expect: exit0'
mod() { printf '%s\n' "$FULL" | sed "$1"; }   # <sed script>: FULL with one change
NONE() { mod "s/^consent: .*/consent: none/; s|^run: .*|run: $1|"; }   # <run line>: a consent: none step
lint_case "a missing verify" "missing verify" 0.21.0.md "$(blk "$(printf '%s\n' "$FULL" | grep -v '^verify:')")"
lint_case "a missing title" "missing title" 0.21.0.md "$(blk "$(printf '%s\n' "$FULL" | grep -v '^title:')")"
lint_case "an unknown key" "unknown key expects" 0.21.0.md "$(blk "$FULL
expects: exit0")"
lint_case "a duplicate key" "duplicate key run" 0.21.0.md "$(blk "$FULL
run: bash y.sh")"
lint_case "an id of another version" "must be 0.21.0-<NN>" 0.21.0.md "$(blk "$(mod 's/^id: .*/id: 0.20.0-01/')")"
lint_case "a duplicate id" "duplicate id 0.21.0-01" 0.21.0.md "$(blk "$FULL")
$(blk "$FULL")"
lint_case "an unterminated block" "unterminated sumela-step block" 0.21.0.md "$(printf '```sumela-step\n%s\n' "$FULL")"
lint_case "a line that is not key: value" "not a key: value line" 0.21.0.md "$(blk "$FULL
just words")"
lint_case "a bad scope" "scope must be repo or developer" 0.21.0.md "$(blk "$(mod 's/^scope: .*/scope: team/')")"
lint_case "a bad when" "when must be" 0.21.0.md "$(blk "$(mod 's/^when: .*/when: later/')")"
lint_case "a consent value in another case" "consent must be none, confirm or explicit, not Explicit" 0.21.0.md "$(blk "$(mod 's/^consent: .*/consent: Explicit/')")"
lint_case "an unknown consent value" "consent must be none, confirm or explicit, not yes" 0.21.0.md "$(blk "$(mod 's/^consent: .*/consent: yes/')")"
lint_case "a ledger value other than none" "ledger takes only none" 0.21.0.md "$(blk "$FULL
ledger: yes")"
lint_case "an until that is not X.Y.Z" "until must be a version X.Y.Z, not 0.22" 0.21.0.md "$(blk "$FULL
until: 0.22")"
lint_case "a bad expect form" "expect must be" 0.21.0.md "$(blk "$(mod 's/^expect: .*/expect: nonzero/')")"
lint_case "{ROOT} in expect" "expect cannot use {ROOT}" 0.21.0.md "$(blk "$(mod 's/^expect: .*/expect: match:{ROOT}/')")"
lint_case "an invalid match pattern" "not a valid extended regular expression" 0.21.0.md "$(blk "$(mod 's/^expect: .*/expect: match:a(b/')")"
lint_case "a POSIX class in match" "POSIX class" 0.21.0.md "$(blk "$(mod 's/^expect: .*/expect: match:[[:digit:]]/')")"
lint_case "a requires that resolves nowhere" "requires 0.21.0-09" 0.21.0.md "$(blk "$FULL
requires: 0.21.0-09")"
lint_case "a requires cycle" "requires forms a cycle" 0.21.0.md "$(blk "$FULL
requires: 0.21.0-02")
$(blk "$(mod 's/^id: .*/id: 0.21.0-02/')
requires: 0.21.0-01")"
lint_case "a runnable step without run.ps1 or a bash line" "needs run.ps1" 0.21.0.md "$(blk "$(mod 's/^run: .*/run: git config --local x y/')")"
lint_case "consent none on a writing run" "consent: none needs" 0.21.0.md "$(blk "$(NONE 'bash scripts/x.sh')")"
lint_case "consent none with bash -c and a read-only flag tacked on" "consent: none needs" 0.21.0.md "$(blk "$(NONE 'bash -c "rm -rf docs .sumela" --check')")"
lint_case "consent none with write flags beside the check flag" "consent: none needs" 0.21.0.md "$(blk "$(NONE 'bash scripts/sumela-registry-parity.sh --sync --yes --check')")"
lint_case "consent none with a single-quoted command beside git config --get" "consent: none needs" 0.21.0.md "$(blk "$(NONE "bash -c 'git config --unset-all user.name' git config --get")")"
lint_case "consent none on a chained command" "consent: none needs" 0.21.0.md "$(blk "$(NONE 'bash x.sh --check; rm -rf y')")"
lint_case "consent none with && after the check" "consent: none needs" 0.21.0.md "$(blk "$(NONE 'bash scripts/x.sh --check && rm -rf docs')")"
lint_case "consent none with a writing run.ps1" "consent: none needs a read-only run.ps1 too" 0.21.0.md "$(blk "$(NONE 'bash scripts/update.sh --plan')
run.ps1: powershell -NoProfile -File scripts/update.ps1 -ApplyPlan")"
lint_ok "consent none on the read-only shapes: --source and a mode flag, with its PowerShell twin" 0.21.0.md "$(blk "$(NONE 'bash "{SRC}/scripts/update.sh" --source "{SRC}" --plan')
run.ps1: powershell -NoProfile -File \"{SRC}/scripts/update.ps1\" -SourceDir \"{SRC}\" -Plan")"
lint_ok "…validate-structure.sh alone" 0.21.0.md "$(blk "$(NONE 'bash scripts/validate-structure.sh')")"
lint_ok "…git config --local --get <key>, in both forms" 0.21.0.md "$(blk "$(NONE 'git config --local --get sumela.k')
run.ps1: git config --local --get sumela.k")"
lint_ok "…--has-baseline <name>" 0.21.0.md "$(blk "$(NONE 'bash scripts/sumela-token-report.sh --has-baseline pre-0.20.1')")"
# The read-only shapes take plain words only, so bash and PowerShell split a line alike: every
# character outside [A-Za-z0-9_./:=@%+-], whole double-quoted strings and the placeholders is
# refused, each class on its own (a mutant that lets any one through fails here).
none_blk() {  # <run line> <verify line> [<key: value line>...]: one consent: none step
  local r="$1" v="$2" l; shift 2
  printf '```sumela-step\nid: 0.21.0-01\ntitle: T\nscope: repo\nwhen: post-update\nconsent: none\nrun: %s\nverify: %s\n' "$r" "$v"
  for l in "$@"; do printf '%s\n' "$l"; done
  printf 'expect: exit0\n```\n'
}
RO_V='bash scripts/x.sh --check'
ro_bad() {  # <label> <run line>: refused as a consent: none run
  lint_case "consent none refuses $1" "consent: none needs run: - or a read-only run" 0.21.0.md "$(none_blk "$2" "$RO_V")"
}
ro_bad_ps() {  # <label> <run.ps1 line>: refused as a consent: none run.ps1
  lint_case "consent none refuses, in run.ps1, $1" "consent: none needs a read-only run.ps1 too" 0.21.0.md "$(none_blk "$RO_V" "$RO_V" "run.ps1: $2")"
}
LQ="$(printf '\342\200\234')"; RQ="$(printf '\342\200\235')"; LQ9="$(printf '\342\200\236')"
LS="$(printf '\342\200\230')"; RS="$(printf '\342\200\231')"; EN="$(printf '\342\200\223')"; NBSP="$(printf '\302\240')"
ro_bad '$( ) inside a string' 'bash scripts/x.sh --source "$(touch PWNED)" --check'
ro_bad 'a backtick inside a string' 'bash scripts/x.sh --source "a`touch PWNED`" --check'
ro_bad 'a $ in a word' 'bash scripts/x.sh --source $HOME --check'
ro_bad '# (bash drops the rest of the line, the mode flag with it)' 'bash scripts/x.sh --source #x --check'
ro_bad 'a ; inside a string' 'bash scripts/x.sh --source "a;b" --check'
ro_bad 'an & inside a string' 'bash scripts/x.sh --source "a&b" --check'
ro_bad 'a pipe' 'bash scripts/x.sh --check | tee out'
ro_bad 'a redirection out' 'bash scripts/x.sh --check > out'
ro_bad 'a redirection in' 'bash scripts/x.sh --check < in'
ro_bad 'parentheses' 'bash scripts/x.sh --source (x) --check'
ro_bad 'braces that are no placeholder' 'bash scripts/x.sh --source {a,b} --check'
ro_bad 'a single-quoted word' "bash scripts/x.sh --source 'a b' --check"
ro_bad 'a backslash' 'bash scripts/x.sh --source a\ b --check'
ro_bad 'a glob' 'bash scripts/*.sh --check'
ro_bad 'a ? glob' 'bash scripts/x.sh --source a? --check'
ro_bad 'a bracket glob' 'bash scripts/x.sh --source a[b] --check'
ro_bad 'a tilde' 'bash scripts/x.sh --source ~/x --check'
ro_bad 'a !' 'bash scripts/x.sh --source a!b --check'
ro_bad 'a quote inside a word' 'bash scripts/x.sh --source a"b c"d --check'
ro_bad 'a word glued to a string' 'bash scripts/x.sh --source "a"b --check'
ro_bad 'a string glued to a word' 'bash scripts/x.sh --source a"b c" --check'
ro_bad 'a brace that opens no placeholder' 'bash scripts/x.sh --source a{b --check'
ro_bad 'a word that starts with a brace (a script block in PowerShell)' 'bash scripts/x.sh --source {b --check'
ro_bad 'an empty string' 'bash scripts/x.sh --source "" --check'
ro_bad 'curly double quotes (U+201C, U+201D)' "bash scripts/x.sh --source \"a$LQ --sync ${RQ}b\" --check"
ro_bad 'a low double quote (U+201E)' "bash scripts/x.sh --source \"a$LQ9 --sync ${RQ}b\" --check"
ro_bad 'curly single quotes (U+2018, U+2019)' "bash scripts/x.sh --source ${LS}a b$RS --check"
ro_bad 'an en dash (U+2013)' "bash scripts/x.sh ${EN}${EN}check"
ro_bad 'a no-break space (U+00A0)' "bash scripts/x.sh --check${NBSP}--sync"
ro_bad 'a comma outside a string (an array in PowerShell)' 'bash scripts/x.sh --source a,b --check'
ro_bad 'a word that starts with @ (splatting in PowerShell)' 'bash scripts/x.sh --source @x --check'
ro_bad 'git -C with an option for a directory' 'git -C --exec-path=x config --get k'
lint_case "consent none refuses a tab" "a value holds a tab character" 0.21.0.md "$(none_blk "bash scripts/x.sh$(printf '\t')--check" "$RO_V")"
ro_bad_ps 'curly quotes that close an ASCII quote in PowerShell' "pwsh -NoProfile -File tools/x.ps1 -SourceDir \"a$LQ -Sync ${LQ}b\" -Check"
ro_bad_ps 'curly quotes around a git subcommand' "git -C \".$LQ branch -D feature -- $LQ.\" config --get sumela.k"
ro_bad_ps 'a comma (PowerShell passes a,-Sync as two arguments)' 'pwsh -NoProfile -File tools/x.ps1 -SourceDir a,-Sync -Check'
ro_bad_ps 'splatting' 'pwsh -NoProfile -File tools/x.ps1 -SourceDir @x -Check'
ro_bad_ps 'a $ inside a string' 'pwsh -NoProfile -File tools/x.ps1 -SourceDir "$env:TEMP" -Check'
ro_bad_ps 'a backtick-escaped quote' 'pwsh -NoProfile -File tools/x.ps1 -SourceDir "a`" -Sync -Check'
ro_bad_ps 'an en dash for a parameter' "pwsh -NoProfile -File tools/x.ps1 ${EN}Sync -Check"
lint_ok "plain words, whole strings with spaces and commas, @ and : inside a word" 0.21.0.md "$(none_blk 'bash scripts/x.sh --source "{SRC}/a b,c" --check' 'bash scripts/x.sh --source user@host:x/y --check' 'run.ps1: pwsh -NoProfile -File "{SRC}/tools/x.ps1" -SourceDir "{SRC}/a b" -Check')"
# consent: none runs its verify without asking too: verify and verify.ps1 take the same shapes.
lint_case "consent none with a writing verify on a run: - step" "consent: none needs a read-only verify too" 0.21.0.md "$(none_blk '-' 'bash -c "touch PWNED"' 'agent: nothing to do')"
lint_case "consent none with a writing verify beside a read-only run" "consent: none needs a read-only verify too" 0.21.0.md "$(none_blk "$RO_V" 'bash scripts/x.sh --sync')"
lint_case "consent none with a writing verify.ps1" "consent: none needs a read-only verify.ps1 too" 0.21.0.md "$(none_blk "$RO_V" "$RO_V" 'verify.ps1: pwsh -NoProfile -File tools/x.ps1 -Sync')"
lint_ok "consent none on a run: - step whose verify is read-only" 0.21.0.md "$(none_blk '-' 'git -C "{ROOT}" config --local --get sumela.k' 'agent: nothing to do' 'verify.ps1: powershell -NoProfile -File "{SRC}/tools/x.ps1" -Check')"
lint_case "an unknown placeholder" "unknown placeholder {HOME}" 0.21.0.md "$(blk "$(mod 's/^run: .*/run: bash "{HOME}\/x.sh"/')")"
lint_case "an unquoted {SRC}" "must sit inside double quotes" 0.21.0.md "$(blk "$(mod 's/^run: .*/run: bash {SRC}\/x.sh/')")"
lint_case "a single-quoted {ROOT}" "must sit inside double quotes" 0.21.0.md "$(blk "$(mod "s/^run: .*/run: bash '{ROOT}\/x.sh'/")")"
lint_case "an escaped {SRC}" "must sit inside double quotes" 0.21.0.md "$(blk "$(mod 's/^run: .*/run: bash "\\{SRC}\/x.sh"/')")"
lint_ok "a placeholder quoted inside \$( … ) is fine" 0.21.0.md "$(blk "$(mod 's/^run: .*/run: bash -c "$(git -C "{ROOT}" rev-parse HEAD)"/')")"
lint_case "{SRC} in a developer step" "a developer step cannot use {SRC}" 0.21.0.md "$(blk "$(mod 's/^scope: .*/scope: developer/; s/^when: .*/when: first-session/; s/^run: .*/run: bash "{SRC}\/x.sh"/')")"
lint_case "a run: - step without agent" "needs an agent: instruction" 0.21.0.md "$(blk "$(mod 's/^run: .*/run: -/')")"
lint_case "until at or below the file's version" "is not above 0.21.0" 0.21.0.md "$(blk "$FULL
until: 0.21.0")"
lint_case "a pre-update version step without requires: upgrade-01" "needs requires: upgrade-01" 0.21.0.md "$(blk "$(mod 's/^when: .*/when: pre-update/')")"
lint_case "a developer step in upgrade.md" "upgrade.md holds repo steps only" upgrade.md "$(blk "$(mod 's/^id: .*/id: upgrade-01/; s/^scope: .*/scope: developer/')")"
lint_case "a file name that is not a version" "not a notes file name" notes.md "$(blk "$FULL")"
lint_case "requires across scopes" "requires stays within one scope" 0.21.0.md "$(blk "$FULL")
$(blk "$(mod 's/^id: .*/id: 0.21.0-02/; s/^scope: .*/scope: developer/; s/^when: .*/when: first-session/')
requires: 0.21.0-01")"
cp "$NOTES/upgrade.md" "$BADN/upgrade.md"
lint_ok "full-line comments are allowed" 0.21.0.md "$(blk "$FULL
# a full-line comment is allowed
   # an indented one too")"
LC_ALL=C sed 's/$/\r/' "$NOTES/0.20.1.md" > "$BADN/0.20.1.md"
m "$REPO_ROOT" lint "$BADN/0.20.1.md"; rc_is "CRLF notes lint clean" 0
has "…and parse to the same steps" "$OUT" "0.20.1.md: ok (2 steps)"
# The runner refuses to plan from invalid notes in the release (exit 4), and records nothing.
INV="$WORK/inv-notes"; write_generic "$INV"; printf '%s' "$(blk "$(printf '%s\n' "$FULL" | grep -v '^verify:' | sed 's/0.21.0/0.20.0/')")" > "$INV/0.20.0.md"
mk_release "$WORK/inv-rel" 0.20.0 v0.20.0 "$INV"; UP="$WORK/inv-rel" mk_project "$WORK/inv-proj" 0.19.0
m "$WORK/inv-proj" plan --source "$(src_of "$WORK/inv-rel")" --scope repo
rc_is "plan from a release whose notes fail the lint exits 4" 4
has "…and names the defect, at its path in the clone" "$OUT" "$WORK/inv-rel.clone/scripts/sumela-migrations/0.20.0.md:1: step 0.20.0-01: missing verify"
if [ ! -e "$WORK/inv-proj/.sumela/.upgrade/migrate.state" ]; then ok "…and writes no state"; else bad "…and writes no state"; fi
m "$WORK/inv-proj" status; same "…so status stays usable" "pending_repo=0 pending_developer=0" "$OUT"
# CRLF notes committed in a release run like LF ones.
CRN="$WORK/crlf-notes"; write_generic "$CRN"; for f in "$CRN"/*.md; do LC_ALL=C sed 's/$/\r/' "$f" > "$f.x" && mv "$f.x" "$f"; done
mk_release "$WORK/crlf-rel" 0.20.0 - "$CRN"
printf '*.md -text\n*.sh text eol=lf\n' > "$WORK/crlf-rel/.gitattributes"
g -C "$WORK/crlf-rel" add -A && g -C "$WORK/crlf-rel" commit -qm crlf && g -C "$WORK/crlf-rel" tag -a -m v v0.20.0
CL="$(src_of "$WORK/crlf-rel")"
if LC_ALL=C grep -q $'\r' "$CL/scripts/sumela-migrations/upgrade.md"; then ok "…the fixture's notes carry CRLF"; else bad "…the fixture's notes carry CRLF"; fi
UP="$WORK/crlf-rel" mk_project "$WORK/crlf-proj" 0.19.0
m "$WORK/crlf-proj" plan --source "$CL" --scope repo
rc_is "plan reads CRLF notes" 0
same "…in the same order as LF notes" "upgrade-01 upgrade-02 upgrade-03 upgrade-04 upgrade-05 upgrade-06 upgrade-07" "$(pending_ids)"

echo "== t_plan_orders_by_phase_version_requires"
mk_release "$WORK/rel" 0.20.2 v0.20.2 "$NOTES"; UP="$WORK/rel" mk_project "$WORK/p1" 0.19.0
REL_SRC="$(src_of "$WORK/rel")"
m "$WORK/p1" plan --source "$REL_SRC" --scope repo
rc_is "plan --source exits 0" 0
same "phase, then version (generic steps count as the target), then id, with requires respected" \
  "upgrade-01 0.20.2-01 upgrade-02 0.20.1-02 upgrade-03 0.20.0-01 0.20.2-02 upgrade-04 0.20.1-01 upgrade-05 upgrade-06 upgrade-07" "$(pending_ids)"
has "…it ends with the two counts" "$OUT" "pending_repo=12 pending_developer=0"
has "…and names the first step" "$OUT" "next: show upgrade-01"
has "…the state records the commit plan --source verified" "$(state_of "$WORK/p1")" "commit=$(git -C "$WORK/rel" rev-parse HEAD)"
m "$WORK/p1" run upgrade-02
rc_is "run refuses a step whose requires is not done" 1
has "…and names it" "$OUT" "upgrade-01 (not done yet)"
m "$WORK/p1" run 0.20.0-01
rc_is "a repo step without requires does not run in the main checkout either" 1
has "…it needs the upgrade worktree" "$OUT" "runs in the upgrade worktree, which upgrade-01 creates"
m "$WORK/p1" record upgrade-01 not-applicable
rc_is "nothing is recorded in the main checkout" 1
if [ ! -e "$WORK/p1/order.log" ] && [ ! -d "$WORK/p1/.sumela/migrations-applied" ]; then ok "…the main checkout gets no step output and no ledger"; else bad "…the main checkout gets no step output and no ledger"; fi
m "$WORK/p1" run upgrade-01
rc_is "run of a run: - step only prints its agent: line" 0
has "…the instruction, with {TARGET} substituted" "$OUT" "agent: git worktree add --no-track -b <prefix>upgrade-0.20.2"

echo "== t_target_placeholder_composes_0_19_to_latest"
P="$WORK/p1"; WT="$WORK/p1-upgrade"; TGT=0.20.2; STEP_LOG=""
m "$P" plan --source "$REL_SRC" --scope repo; ORDER="$(pending_ids)"
# shellcheck disable=SC2086  # the ids are words
step_through "$P" $ORDER
same "every step shows, runs, verifies and records in plan order" "" "$STEP_LOG"
same "one worktree on one branch named by {TARGET}" "sumela/upgrade-0.20.2" "$(git -C "$WT" rev-parse --abbrev-ref HEAD)"
same "…created without an upstream to push to" "" "$(git -C "$WT" config --get branch.sumela/upgrade-0.20.2.merge)"
same "…and only one linked worktree" 2 "$(git -C "$P" worktree list | grep -c .)"
same "the steps ran in the worktree, in order, with {TARGET} substituted" \
  "v0.20.2-01 plan-0.20.2 v0.20.1-02 apply-0.20.2 v0.20.0-01 v0.20.2-02 parity-0.20.2 v0.20.1-01 mirrors-0.20.2 validate-0.20.2" \
  "$(tr '\n' ' ' < "$WT/order.log" | sed 's/ $//')"
same "one apply stamped the target" 0.20.2 "$(tr -d '\r\n' < "$WT/.sumela/VERSION")"
same "the ledgers: generic steps @target, version steps by id; none for ledger: none or a moot step" \
  "0.20.0-01 0.20.1-01 0.20.1-02 0.20.2-01 0.20.2-02 upgrade-01@0.20.2 upgrade-02@0.20.2 upgrade-03@0.20.2 upgrade-04@0.20.2 upgrade-05@0.20.2 upgrade-06@0.20.2" \
  "$(ls "$WT/.sumela/migrations-applied" | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"
same "the one upgrade commit carries every ledger entry" 11 "$(git -C "$WT" show --name-only --format= HEAD | grep -c '^\.sumela/migrations-applied/')"
same "the main checkout is untouched (its runtime directory ignores itself)" "" "$(git -C "$P" status --porcelain)"
same "…and stays at v0.19.0" 0.19.0 "$(tr -d '\r\n' < "$P/.sumela/VERSION")"
m "$P" status
same "status: nothing pending" "pending_repo=0 pending_developer=0" "$OUT"
m "$P" plan --source "$REL_SRC" --scope repo
has "plan says every step is recorded (ledger: none included), the merge still to come" "$OUT" "every repo step is recorded: merge the upgrade pull request"
if [ -e "$P/.sumela/.upgrade/migrate.state" ]; then ok "…and keeps its state until the main checkout has the merge"; else bad "…and keeps its state until the main checkout has the merge"; fi

echo "== t_post_update_steps_survive_stamp"
mk_release "$WORK/rel20" 0.20.0 v0.20.0 "$GEN"; UP="$WORK/rel20" mk_project "$WORK/p2" 0.19.0
REL20_SRC="$(src_of "$WORK/rel20")"
P="$WORK/p2"; WT="$WORK/p2-upgrade"; TGT=0.20.0; STEP_LOG=""
m "$P" plan --source "$REL20_SRC" --scope repo
step_through "$P" upgrade-01 upgrade-02 upgrade-03
same "the first three steps pass" "" "$STEP_LOG"
same "the apply stamped VERSION in the worktree" 0.20.0 "$(tr -d '\r\n' < "$WT/.sumela/VERSION")"
m "$P" plan --source "$REL20_SRC" --scope repo
same "the version step and steps 04–07 are still listed" "0.20.0-01 upgrade-04 upgrade-05 upgrade-06 upgrade-07" "$(pending_ids)"
has "…from the v0.19.0 the upgrade started at" "$OUT" "Repo steps: v0.19.0 -> v0.20.0"
m "$WT" plan --source "$REL20_SRC" --scope repo
same "a session inside the worktree sees the same plan" "0.20.0-01 upgrade-04 upgrade-05 upgrade-06 upgrade-07" "$(pending_ids)"
m "$P" run upgrade-03
rc_is "a recorded step is not run again" 1
has "…and says why" "$OUT" "already recorded (done)"

echo "== t_requires_need_done_and_declined_is_listed"
m "$P" record 0.20.0-01 declined; rc_is "a step can be declined" 0
m "$P" plan --source "$REL20_SRC" --scope repo
has "plan lists the declined step as still to do" "$OUT" "declined (still to do; run <id> when ready): 0.20.0-01"
lacks "…not among the pending ones" "$(pending_ids)" "0.20.0-01"
m "$P" status
has "status reports it on a second line" "$OUT" "declined_repo=1 declined_developer=0"
m "$P" record upgrade-04 declined
m "$P" run upgrade-06
rc_is "a step whose requires was declined does not run" 1
has "…and says so" "$OUT" "upgrade-04 (declined)"
m "$P" record upgrade-06 done
rc_is "…nor can it be recorded done" 1
m "$P" run upgrade-04; rc_is "a declined step runs when the user is ready" 0
m "$P" record upgrade-04 done; rc_is "…and records done" 0
m "$P" run upgrade-06; rc_is "…which unblocks the step that requires it" 0

echo "== t_resume_in_new_session"
UP="$WORK/rel20" mk_project "$WORK/p3" 0.19.0
P="$WORK/p3"; WT="$WORK/p3-upgrade"; TGT=0.20.0; STEP_LOG=""
g clone -q "$WORK/rel20" "$WORK/clone3" && g -C "$WORK/clone3" -c advice.detachedHead=false checkout -q v0.20.0
m "$P" plan --source "$WORK/clone3" --scope repo
step_through "$P" upgrade-01 upgrade-02
state="$(state_of "$P")"
has "the state records where the upgrade started" "$state" "from=0.19.0"
has "…its target and tag" "$state" "tag=v0.20.0"
has "…the clone's origin" "$state" "url=$WORK/rel20"
has "…the worktree" "$state" "worktree=$WT"
has "…and the branch the worktree is on" "$state" "branch=sumela/upgrade-0.20.0"
rm -rf "$WORK/clone3"
m "$P" status
same "status is offline: a missing clone is not cloned" "pending_repo=0 pending_developer=0" "$(printf '%s\n' "$OUT" | grep '^pending_')"
has "…and says the upgrade is unfinished" "$OUT" "release clone $WORK/clone3 is missing"
m "$P" plan --scope repo
rc_is "a new session resumes from the state alone" 0
has "…cloning the recorded tag again" "$OUT" "cloning $WORK/rel20 at v0.20.0 again"
same "…and lists what is left, in order" "upgrade-03 0.20.0-01 upgrade-04 upgrade-05 upgrade-06" "$(pending_ids)"
has "…running in the recorded worktree" "$OUT" "root:  $WT"
step_through "$P" upgrade-03
same "the resumed session continues in the worktree" "" "$STEP_LOG"
same "…where the apply happened" 0.20.0 "$(tr -d '\r\n' < "$WT/.sumela/VERSION")"

echo "== t_worktree_gone_refuses_and_rollback_restores"
P="$WORK/p3"; WT="$WORK/p3-upgrade"
L="$WT/.sumela/migrations-applied/upgrade-03@0.20.0"
m "$P" run upgrade-04; m "$P" record upgrade-04 done
m "$P" rollback upgrade-04 --confirmed-by-user
rc_is "a rollback whose line fails exits 1" 1
if [ -f "$WT/.sumela/migrations-applied/upgrade-04@0.20.0" ]; then ok "…and its ledger entry is restored"; else bad "…and its ledger entry is restored"; fi
has "…and says so" "$OUT" "restored the ledger entry"
m "$P" rollback upgrade-03 --confirmed-by-user
rc_is "a rollback whose line succeeds exits 0" 0
if [ ! -f "$L" ]; then ok "…and its ledger entry is gone: the step is pending again"; else bad "…and its ledger entry is gone"; fi
if [ ! -e "$WT/done-apply-0.20.0" ]; then ok "…its effect undone"; else bad "…its effect undone"; fi
g -C "$P" worktree remove --force "$WT"
m "$P" record upgrade-05 not-applicable
rc_is "once the recorded worktree is gone, repo steps refuse to record" 1
has "…and say why" "$OUT" "no longer exists: repo steps neither run, record nor roll back without it"
m "$P" run 0.20.0-01
rc_is "…and to run" 1
m "$P" rollback upgrade-04 --confirmed-by-user
rc_is "…and to roll back (never in the main checkout)" 1
same "the main checkout is untouched" "" "$(git -C "$P" status --porcelain)"

echo "== t_rollback_removes_the_worktree_and_branch"
UP="$WORK/rel20" mk_project "$WORK/p4" 0.19.0
P="$WORK/p4"; WT="$WORK/p4-upgrade"; TGT=0.20.0; STEP_LOG=""
m "$P" plan --source "$REL20_SRC" --scope repo
step_through "$P" upgrade-01 upgrade-02
echo stray > "$WT/untracked.txt"
m "$P" rollback upgrade-01 --confirmed-by-user
rc_is "upgrade-01's rollback runs (its ledger entry goes first)" 0
if [ ! -d "$WT" ]; then ok "…the worktree is removed with everything in it"; else bad "…the worktree is removed"; fi
same "…the branch is deleted" "" "$(git -C "$P" branch --list 'sumela/upgrade-0.20.0')"
lacks "…and the state forgets the worktree" "$(state_of "$P")" "worktree="
m "$P" plan --scope repo
same "upgrade-01 is pending again, in the main checkout" "upgrade-01 upgrade-02 upgrade-03 0.20.0-01 upgrade-04 upgrade-05 upgrade-06" "$(pending_ids)"

echo "== t_complete_upgrade_retires_state"
UP="$WORK/rel20" mk_project "$WORK/p5" 0.19.0
P="$WORK/p5"; WT="$WORK/p5-upgrade"; TGT=0.20.0; STEP_LOG=""
g clone -q "$WORK/rel20" "$WORK/clone5" && g -C "$WORK/clone5" -c advice.detachedHead=false checkout -q v0.20.0
m "$P" plan --source "$WORK/clone5" --scope repo; ORDER="$(pending_ids)"
# shellcheck disable=SC2086
step_through "$P" $ORDER
m "$P" plan --source "$WORK/clone5" --scope repo
has "with every step recorded and the merge still to come, plan says what is left" "$OUT" "every repo step is recorded: merge the upgrade pull request, then update the main checkout"
if [ -e "$P/.sumela/.upgrade/migrate.state" ]; then ok "…and keeps the state: the rollbacks need it before the merge"; else bad "…and keeps the state: the rollbacks need it before the merge"; fi
m "$P" plan --scope repo
lacks "…and so does plan without --source" "$OUT" "is complete"
g -C "$P" merge -q --no-ff -m "Merge the upgrade" sumela/upgrade-0.20.0 && rm -rf "$WORK/clone5"
m "$P" status
same "after the merge, status reports nothing pending, offline" "pending_repo=0 pending_developer=0" "$OUT"
m "$P" plan --scope repo
has "plan reports the upgrade complete from the main checkout's VERSION" "$OUT" "the upgrade to v0.20.0 is complete (the main checkout is at v0.20.0)"
lacks "…without cloning the release again" "$OUT" "cloning"
if [ ! -e "$P/.sumela/.upgrade/migrate.state" ]; then ok "…and removes the state"; else bad "…and removes the state"; fi
# Every step recorded, the pull request not merged: the user abandons it. The rollbacks still work.
UP="$WORK/rel20" mk_project "$WORK/p5r" 0.19.0
P="$WORK/p5r"; WT="$WORK/p5r-upgrade"; STEP_LOG=""
m "$P" plan --source "$REL20_SRC" --scope repo; ORDER="$(pending_ids)"
# shellcheck disable=SC2086
step_through "$P" $ORDER
m "$P" plan
log=""
for id in upgrade-07 upgrade-03 upgrade-01; do m "$P" rollback "$id" --confirmed-by-user; [ "$RC" = 0 ] || log="$log $id: exit $RC ($OUT);"; done
same "after the last step and a plain plan, the rollbacks run before the merge" "" "$log"
if [ ! -d "$WT" ]; then ok "…upgrade-01's removes the worktree"; else bad "…upgrade-01's removes the worktree"; fi
same "…and the branch" "" "$(git -C "$P" branch --list 'sumela/upgrade-0.20.0')"
# The next release, with an earlier state left behind, starts once that upgrade is complete.
UP="$WORK/rel20" mk_project "$WORK/p6" 0.19.0
P="$WORK/p6"; WT="$WORK/p6-upgrade"; STEP_LOG=""
m "$P" plan --source "$REL20_SRC" --scope repo; ORDER="$(pending_ids)"
# shellcheck disable=SC2086
step_through "$P" $ORDER
G21="$WORK/notes-021"; write_generic "$G21"; mk_release "$WORK/rel21" 0.20.1 v0.20.1 "$G21"
printf '# upstream\n%s\n' "$WORK/rel21" > "$P/.sumela/upstream.conf"
m "$P" plan --source "$(src_of "$WORK/rel21")" --scope repo
rc_is "the next release refuses while the earlier upgrade's worktree is unmerged" 1
has "…naming how to abandon it" "$OUT" "rollback upgrade-01 --confirmed-by-user"
g -C "$P" merge -q --no-ff -m "Merge the upgrade" sumela/upgrade-0.20.0
m "$P" plan --source "$(src_of "$WORK/rel21")" --scope repo
rc_is "once it is merged into the main checkout, the next release starts" 0
has "…retiring the earlier state" "$OUT" "the upgrade to v0.20.0 is complete (the main checkout is at v0.20.0)"
has "…and recording the new one" "$OUT" "recorded the upgrade v0.20.0 -> v0.20.1"

echo "== t_teammate_after_pull_sees_developer_steps"
TM="$WORK/tm-notes"; mkdir -p "$TM"
{ step_block 0.20.0-01 developer first-session "until: 0.20.2"
  step_block 0.20.0-02 developer first-session "until: 0.20.1"
  step_block 0.20.0-03 repo post-update; } > "$TM/0.20.0.md"
{ step_block 0.20.1-01 developer first-session; } > "$TM/0.20.1.md"
{ step_block 0.20.2-01 developer first-session; } > "$TM/0.20.2.md"
write_generic "$TM"
mk_project "$WORK/tm" 0.20.1 "$TM"
m "$WORK/tm" plan --scope developer
rc_is "plan --scope developer needs no clone and no state" 0
same "VERSION already at the target: every skipped version's developer steps are listed" "0.20.0-01 0.20.1-01" "$(pending_ids)"
lacks "…not a moot one (until at or below the installed version)" "$OUT" "0.20.0-02 "
lacks "…not one above the installed version" "$OUT" "0.20.2-01"
lacks "…and never a repo step" "$OUT" "0.20.0-03"
m "$WORK/tm" run 0.20.0-01; rc_is "a developer step runs from the installed notes" 0
m "$WORK/tm" record 0.20.0-01 done; rc_is "…and records done after its verify passes" 0
m "$WORK/tm" status --scope developer
same "status counts what is left" "pending_developer=1" "$OUT"
g -C "$WORK/tm" worktree add -q -b feat "$WORK/tm-wt" main >/dev/null 2>&1
m "$WORK/tm-wt" plan --scope developer
same "a linked worktree of the same clone shares the developer ledger" "0.20.1-01" "$(pending_ids)"
m "$WORK/tm" record 0.20.1-01 declined
m "$WORK/tm" plan --scope developer
has "a declined developer step stays listed" "$OUT" "declined (still to do; run <id> when ready): 0.20.1-01"
m "$WORK/tm" status --scope developer
same "…and counted apart" "pending_developer=0
declined_developer=1" "$OUT"

echo "== t_presatisfied_developer_step_auto_recorded"
PS_N="$WORK/ps-notes"; mkdir -p "$PS_N"
cat > "$PS_N/0.20.0.md" <<'EOF'
```sumela-step
id: 0.20.0-01
title: Record a dev key
scope: developer
when: first-session
consent: confirm
run: bash "{ROOT}/tools/step.sh" key
verify: git config --local --get sumela.testKey
expect: non-empty
agent: pick a key
```

```sumela-step
id: 0.20.0-02
title: A check that is not read-only by the allow-list
scope: developer
when: first-session
consent: confirm
run: bash "{ROOT}/tools/step.sh" other
verify: test -f app.txt
expect: exit0
```

```sumela-step
id: 0.20.0-03
title: A verify that writes, passed off with a read-only flag
scope: developer
when: first-session
consent: explicit
run: bash "{ROOT}/tools/step.sh" w
verify: bash -c "touch PLAN-RAN-THIS" --check
expect: exit0
```

```sumela-step
id: 0.20.0-04
title: A verify whose mode flag bash would drop as a comment
scope: developer
when: first-session
consent: explicit
run: bash "{ROOT}/tools/step.sh" c
verify: bash tools/writer.sh --source #x --check
expect: exit0
```
EOF
mk_project "$WORK/ps" 0.20.0 "$PS_N"
printf '#!/usr/bin/env bash\ncase " $* " in *" --check "*) echo check only ;; *) : > PLAN-RAN-WRITER ;; esac\n' > "$WORK/ps/tools/writer.sh"
g -C "$WORK/ps" add -A && g -C "$WORK/ps" commit -qm writer
g -C "$WORK/ps" config --local sumela.testKey abc
m "$WORK/ps" plan --scope developer
rc_is "plan exits 0" 0
has "a developer step whose read-only verify passes is recorded done (pre-satisfied)" "$OUT" "recorded 0.20.0-01 done (pre-satisfied)"
same "…and is no longer pending; a passing verify outside the allow-list is never run by plan" "0.20.0-02 0.20.0-03 0.20.0-04" "$(pending_ids)"
if [ ! -e "$WORK/ps/PLAN-RAN-THIS" ]; then ok "…nor is a writing verify with a read-only flag tacked on"; else bad "…nor is a writing verify with a read-only flag tacked on"; fi
if [ ! -e "$WORK/ps/PLAN-RAN-WRITER" ]; then ok "…nor one whose # would make bash drop its mode flag"; else bad "…nor one whose # would make bash drop its mode flag"; fi
LOG="$(cd "$WORK/ps" && sumela_state_dir)/migrations.log"
has "the developer ledger holds the entry" "$(cat "$LOG" 2>/dev/null)" "0.20.0-01	done (pre-satisfied)	"

echo "== t_verify_expect_forms"
VF="$WORK/vf-notes"; mkdir -p "$VF"
vblk() {  # <nn> <verify> <expect>
  printf '```sumela-step\nid: 0.20.0-%s\ntitle: V%s\nscope: developer\nwhen: first-session\nconsent: confirm\nrun: bash "{ROOT}/tools/step.sh" v%s\nverify: %s\nexpect: %s\n```\n\n' "$1" "$1" "$1" "$2" "$3"
}
{ vblk 01 'bash -c "exit 0"' exit0
  vblk 02 'bash -c "exit 1"' exit0
  vblk 03 'printf yes' non-empty
  vblk 04 'printf ""' non-empty
  vblk 05 'printf ""' empty
  vblk 06 'printf x' empty
  vblk 07 'printf yes' equals:yes
  vblk 08 'printf yess' equals:yes
  vblk 09 'printf "yes\r\n"' equals:yes
  vblk 10 'printf "a\nverified: upgrade complete 0.20.0; 0 kept\n"' 'match:^verified: upgrade complete {TARGET};'
  vblk 11 'printf "verified: upgrade complete 0.20.1;"' 'match:^verified: upgrade complete {TARGET};'
  vblk 12 'bash -c "echo on-stderr >&2"' 'match:^on-stderr$'
  vblk 13 'bash -c "printf yes; exit 2"' equals:yes
  vblk 14 'printf "upgrade complete 0x20y0"' 'match:complete {TARGET}$'; } > "$VF/0.20.0.md"
mk_project "$WORK/vf" 0.20.0 "$VF"
vexp() {  # <nn> <expected rc> <label>
  m "$WORK/vf" verify "0.20.0-$1"
  if [ "$RC" = "$2" ]; then ok "$3"; else bad "$3 (expected exit $2, got $RC: $(printf '%s' "$OUT" | tail -3))"; fi
}
vexp 01 0 "exit0 holds when verify exits 0"
vexp 02 3 "exit0 fails when verify exits 1"
vexp 03 0 "non-empty holds on output"
vexp 04 3 "non-empty fails on no output"
vexp 05 0 "empty holds on no output"
vexp 06 3 "empty fails on output"
vexp 07 0 "equals: holds on the exact output"
vexp 08 3 "equals: fails on other output"
vexp 09 0 "equals: ignores a CRLF line end"
vexp 13 3 "a verify that exits non-zero fails whatever its output"
vexp 10 0 "match: holds on one matching line ({TARGET} is the installed version for a developer step)"
vexp 12 0 "match: reads stderr too"
vexp 11 3 "match: fails without a matching line"
vexp 14 3 "match: takes {TARGET}'s dots literally"
m "$WORK/vf" verify 0.20.0-07
has "verify prints the command and its output" "$OUT" '$ printf yes'
has "…and the verdict" "$OUT" "verify 0.20.0-07: ok (expect equals:yes)"

echo "== t_verify_fails_when_artifact_missing_despite_exit0_run"
AM="$WORK/am-notes"; mkdir -p "$AM"
cat > "$AM/0.20.0.md" <<'EOF'
```sumela-step
id: 0.20.0-01
title: A step whose command succeeds without producing its artifact
scope: developer
when: first-session
consent: confirm
run: bash -c "echo did nothing"
verify: test -f artifact.txt
expect: exit0
```
EOF
mk_project "$WORK/am" 0.20.0 "$AM"
m "$WORK/am" run 0.20.0-01; rc_is "the command exits 0" 0
m "$WORK/am" verify 0.20.0-01; rc_is "…but verify fails on the missing artifact (exit 3)" 3
m "$WORK/am" record 0.20.0-01 done; rc_is "record done refuses without the artifact (exit 3)" 3
has "…and says so" "$OUT" "not recorded"
m "$WORK/am" status --scope developer; same "…so the step stays pending" "pending_developer=1" "$OUT"
m "$WORK/am" record 0.20.0-01 not-applicable; rc_is "not-applicable needs no verify" 0
m "$WORK/am" status --scope developer; same "…and settles the step" "pending_developer=0" "$OUT"

echo "== t_repo_ledger_recorded_in_provenance"
WT="$WORK/p2-upgrade"
L="$WT/.sumela/migrations-applied/upgrade-02@0.20.0"
same "a generic step's ledger is named <id>@<target> and holds status, at and version" "status: done|at: |version: 0.20.0" \
  "$(LC_ALL=C sed 's/^at: .*/at: /' "$L" | tr '\n' '|' | sed 's/|$//')"
if LC_ALL=C grep -Eq '^at: [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$L"; then ok "…at is a UTC timestamp"; else bad "…at is a UTC timestamp ($(cat "$L"))"; fi
if LC_ALL=C grep -q $'\r' "$L"; then bad "…written with LF"; else ok "…written with LF"; fi
FILES="$(sumela_record_files "$WT/.sumela/.last-update.json")"
has "every repo ledger entry is in the provenance record's files" "$FILES" ".sumela/migrations-applied/upgrade-01@0.20.0"
has "…the third too" "$FILES" ".sumela/migrations-applied/upgrade-03@0.20.0"
same "a declined version step's ledger is named by its id" "status: declined" "$(head -1 "$WT/.sumela/migrations-applied/0.20.0-01")"
has "…and is in files too" "$(sumela_record_files "$WT/.sumela/.last-update.json")" ".sumela/migrations-applied/0.20.0-01"

echo "== t_developer_ledger_mode_0600"
LOG="$(cd "$WORK/tm" && sumela_state_dir)/migrations.log"
if [ "$ON_WINDOWS" = true ]; then
  echo "  SKIP  POSIX modes (Windows: %LOCALAPPDATA% is per-user)"
elif [ -f "$LOG" ]; then
  same "the developer ledger is 0600" 600 "$(mode_of "$LOG")"
  same "…inside a 0700 state directory" 700 "$(mode_of "$(dirname "$LOG")")"
  if LC_ALL=C grep -Eq '^0\.20\.0-01	(done|declined|not-applicable|done \(pre-satisfied\))	[0-9T:Z-]+$' "$LOG"; then ok "…one <id><TAB><status><TAB><UTC> line per entry"; else bad "…one <id><TAB><status><TAB><UTC> line per entry ($(cat "$LOG"))"; fi
else
  bad "a developer ledger exists"
fi

echo "== t_untagged_source_refused"
mk_release "$WORK/untagged" 0.20.0 - "$GEN"; UP="$WORK/untagged" mk_project "$WORK/u" 0.19.0
m "$WORK/u" plan --source "$(src_of "$WORK/untagged")" --scope repo
rc_is "a clone whose HEAD has no release tag is refused" 1
has "…naming the tag it needs" "$OUT" "not at an annotated release tag v0.20.0"
if [ ! -e "$WORK/u/.sumela/.upgrade/migrate.state" ]; then ok "…and nothing is recorded"; else bad "…and nothing is recorded"; fi
g -C "$WORK/untagged" tag v0.20.0
m "$WORK/u" plan --source "$(src_of "$WORK/untagged")" --scope repo
rc_is "a lightweight tag is refused (cat-file -t must say tag)" 1
g -C "$WORK/untagged" tag -d v0.20.0 >/dev/null; g -C "$WORK/untagged" tag -a -m x v0.20.1
m "$WORK/u" plan --source "$(src_of "$WORK/untagged")" --scope repo
rc_is "a tag of another version is refused" 1
g -C "$WORK/untagged.clone" tag -a -m forged v0.20.0
m "$WORK/u" plan --source "$WORK/untagged.clone" --scope repo
rc_is "a tag made in the clone alone is refused: the upstream does not have it" 1
has "…git ls-remote says so" "$OUT" "says v0.20.0 is absent"
g -C "$WORK/untagged.clone" tag -d v0.20.0 >/dev/null
m "$WORK/u" plan --source "$(src_of "$WORK/untagged")" --scope repo --allow-untagged
rc_is "--allow-untagged alone is refused: it is for maintainer tests only" 1
has "…which take SUMELA_MIGRATE_ALLOW_UNTAGGED=1 as well" "$OUT" "SUMELA_MIGRATE_ALLOW_UNTAGGED=1"
export SUMELA_MIGRATE_ALLOW_UNTAGGED=1
m "$WORK/u" plan --source "$(src_of "$WORK/untagged")" --scope repo --allow-untagged
unset SUMELA_MIGRATE_ALLOW_UNTAGGED
rc_is "--allow-untagged with SUMELA_MIGRATE_ALLOW_UNTAGGED=1 (maintainer tests) proceeds" 0
has "…and says so" "$OUT" "--allow-untagged"
mk_project "$WORK/u2" 0.19.0
m "$WORK/u2" plan --source "$REL20_SRC" --scope repo
rc_is "a clone whose origin is not the project's upstream is refused" 1
has "…naming both and the default" "$OUT" "not from this project's upstream https://github.com/tolgakisaogullari/SumelaOS.git (.sumela/upstream.conf, else https://github.com/tolgakisaogullari/SumelaOS.git)"
m "$WORK/u2" plan --source "$REL20_SRC" --scope repo --confirmed-by-user
rc_is "--confirmed-by-user does not trust another origin" 1
has "…the refusal names --trust-origin" "$OUT" "pass --trust-origin <url> once the user confirms that source"
m "$WORK/u2" plan --source "$REL20_SRC" --scope repo --trust-origin "$WORK/elsewhere"
rc_is "--trust-origin with a URL that is not the clone's origin is refused" 1
has "…saying so" "$OUT" "as --trust-origin says"
m "$WORK/u2" status --trust-origin "$WORK/rel20"
rc_is "only plan --source takes --trust-origin" 1
m "$WORK/u2" plan --source "$REL20_SRC" --scope repo --trust-origin "$WORK/rel20"
rc_is "--trust-origin <the clone's origin> proceeds, once the user confirmed it" 0
has "…which the output records" "$OUT" "which the user confirmed"
UP="$WORK/rel20" mk_project "$WORK/u3" 0.19.0
CU="$WORK/rel20.clone"
printf 'echo TAMPERED\n' >> "$CU/tools/step.sh"
m "$WORK/u3" plan --source "$CU" --scope repo
rc_is "a clone with a modified tool is refused" 1
has "…its local changes named" "$OUT" "has local changes"
g -C "$CU" checkout -q -- tools/step.sh
echo x > "$CU/tools/extra.sh"
m "$WORK/u3" plan --source "$CU" --scope repo
rc_is "a clone with an untracked file is refused" 1
rm -f "$CU/tools/extra.sh"
printf '\n# staged\n' >> "$CU/scripts/sumela-migrations/upgrade.md"; g -C "$CU" add scripts/sumela-migrations/upgrade.md
m "$WORK/u3" plan --source "$CU" --scope repo
rc_is "a clone with staged notes is refused" 1
g -C "$CU" reset -q --hard
g -C "$CU" update-index --assume-unchanged scripts/sumela-migrations/upgrade.md
LC_ALL=C sed 's/^consent: confirm$/consent: none/' "$CU/scripts/sumela-migrations/upgrade.md" > "$CU/x.tmp" && cat "$CU/x.tmp" > "$CU/scripts/sumela-migrations/upgrade.md" && rm -f "$CU/x.tmp"
m "$WORK/u3" plan --source "$CU" --scope repo
rc_is "a clone that hides an edit (assume-unchanged) is refused" 1
has "…and says how" "$OUT" "hides local changes"
g -C "$CU" update-index --no-assume-unchanged scripts/sumela-migrations/upgrade.md; g -C "$CU" checkout -q -- scripts/sumela-migrations/upgrade.md
CANARY="s3cr3tCANARY"
g -C "$CU" config remote.origin.url "https://alice:$CANARY@example.invalid/x/SumelaOS.git"
m "$WORK/u3" plan --source "$CU" --scope repo
rc_is "a credentialed origin that is not the upstream is refused" 1
lacks "…and the credential is never printed" "$OUT" "$CANARY"
has "…the URL is shown without it" "$OUT" "comes from https://example.invalid/x/SumelaOS.git, not from"
CANARY_OUT="$OUT"
OUT="$(cd "$WORK/u3" && GIT_ALLOW_PROTOCOL=file bash "$RUNNER" plan --source "$CU" --scope repo --trust-origin "https://alice:$CANARY@example.invalid/x/SumelaOS.git" 2>&1)"; RC=$?
rc_is "a confirmed origin that cannot be asked for the tag is refused (the tag check needs it)" 1
has "…naming it without the credential" "$OUT" "cannot ask https://example.invalid/x/SumelaOS.git for v0.20.0"
CANARY_OUT="$CANARY_OUT$OUT"
lacks "the canary credential appears in no output, nor in any state file" "$CANARY_OUT$(cat "$WORK/u3/.sumela/.upgrade/migrate.state" 2>/dev/null)" "$CANARY"
g -C "$CU" config remote.origin.url "$WORK/rel20"
# The clone's own git configuration is not trusted: no fsmonitor hook runs, and no
# url.<x>.insteadOf can make the tag check ask another repository.
g -C "$CU" config core.fsmonitor "touch \"$WORK/FSMONITOR-RAN\"; false"
m "$WORK/u3" plan --source "$CU" --scope repo
rc_is "a clean clone with an fsmonitor hook in its config is checked" 0
if [ ! -e "$WORK/FSMONITOR-RAN" ]; then ok "…without running that hook"; else bad "…without running that hook"; fi
g -C "$CU" config --unset core.fsmonitor
g clone -q "$WORK/rel20" "$WORK/fork"; printf 'echo FORK\n' >> "$WORK/fork/tools/step.sh"
g -C "$WORK/fork" commit -qam fork && g -C "$WORK/fork" tag -a -f -m fork v0.20.0 >/dev/null
g clone -q "$WORK/fork" "$WORK/fork.clone" && g -C "$WORK/fork.clone" -c advice.detachedHead=false checkout -q v0.20.0
g -C "$WORK/fork.clone" remote set-url origin "$WORK/rel20"
g -C "$WORK/fork.clone" config "url.$WORK/fork.insteadOf" "$WORK/rel20"
rm -f "$WORK/u3/.sumela/.upgrade/migrate.state"
m "$WORK/u3" plan --source "$WORK/fork.clone" --scope repo
rc_is "a fork's commit under the upstream's URL is refused, insteadOf in the clone or not" 1
has "…the upstream itself says the tag is elsewhere" "$OUT" "$WORK/rel20 says v0.20.0 is $(git -C "$WORK/rel20" rev-parse 'v0.20.0^{commit}')"
if [ "$ON_WINDOWS" != true ]; then
  NL="$WORK/clone
worktree=$WORK/evil"
  g clone -q "$WORK/rel20" "$NL" && g -C "$NL" -c advice.detachedHead=false checkout -q v0.20.0
  m "$WORK/u3" plan --source "$NL" --scope repo
  rc_is "a clone path with a newline is refused" 1
  has "…saying why" "$OUT" "holds a control character"
  lacks "…and nothing reaches the state" "$(state_of "$WORK/u3")" "worktree=$WORK/evil"
fi
m "$WORK/rel20" plan --source "$CU" --scope repo
rc_is "the runner refuses to run inside the release clone's upstream itself" 1
m "$CU" plan --source "$CU" --scope repo
rc_is "…and inside the release clone itself" 1
has "…saying so" "$OUT" "the release clone is this repository"
m "$WORK/u3" status --source "$CU"
rc_is "only plan takes --source" 1

echo "== t_rc_tag_accepted"
mk_release "$WORK/rc" 0.20.0 v0.20.0-rc.1 "$GEN"; UP="$WORK/rc" mk_project "$WORK/rcp" 0.19.0
m "$WORK/rcp" plan --source "$(src_of "$WORK/rc")" --scope repo
rc_is "an annotated v<target>-rc.<n> tag is accepted" 0
has "…the target stays the release's VERSION" "$OUT" "v0.19.0 -> v0.20.0"
same "…and the RC tag is recorded" "tag=v0.20.0-rc.1" "$(grep '^tag=' "$WORK/rcp/.sumela/.upgrade/migrate.state")"
g -C "$WORK/rc" tag -a -m final v0.20.0
m "$WORK/rcp" plan --source "$(src_of "$WORK/rc")" --scope repo
same "the final tag on the same commit is preferred" "tag=v0.20.0" "$(grep '^tag=' "$WORK/rcp/.sumela/.upgrade/migrate.state")"
mk_release "$WORK/rcbad" 0.20.0 v0.20.0-rc.x "$GEN"
printf '# upstream\n%s\n' "$WORK/rcbad" > "$WORK/rcp/.sumela/upstream.conf"
m "$WORK/rcp" plan --source "$(src_of "$WORK/rcbad")" --scope repo
rc_is "a malformed RC tag is refused" 1
BV="$WORK/badv"; mk_release "$BV" 0.20 v0.20 "$GEN"
printf '# upstream\n%s\n' "$BV" > "$WORK/rcp/.sumela/upstream.conf"
m "$WORK/rcp" plan --source "$(src_of "$BV")" --scope repo
rc_is "a release whose VERSION is not X.Y.Z is refused" 1
has "…naming it" "$OUT" "not a release version"

echo "== t_modified_installed_notes_refused"
mk_project "$WORK/mod" 0.20.1 "$TM"
m "$WORK/mod" plan --scope developer; rc_is "unmodified installed notes are read" 0
printf '\n# local edit\n' >> "$WORK/mod/scripts/sumela-migrations/0.20.0.md"
m "$WORK/mod" plan --scope developer
rc_is "installed notes that differ from HEAD are refused" 1
has "…naming the fix" "$OUT" "differ from HEAD"
m "$WORK/mod" run 0.20.0-01
rc_is "…for every command" 1
g -C "$WORK/mod" checkout -q -- scripts/sumela-migrations/0.20.0.md
step_block 0.19.5-01 developer first-session > "$WORK/mod/scripts/sumela-migrations/0.19.5.md"
m "$WORK/mod" plan --scope developer
rc_is "an untracked notes file is not a source of steps" 0
lacks "…its step is not listed, though its version would select it" "$OUT" "0.19.5-01"
# A notes file committed as a symlink would point outside HEAD: it is refused.
mk_project "$WORK/sym" 0.20.1 "$TM"
step_block 0.19.9-01 developer first-session > "$WORK/outside.md"
blob="$(printf '%s' "$WORK/outside.md" | git -C "$WORK/sym" hash-object -w --stdin)"
g -C "$WORK/sym" update-index --add --cacheinfo "120000,$blob,scripts/sumela-migrations/0.19.9.md"
g -C "$WORK/sym" commit -qm "notes as a symlink" && g -C "$WORK/sym" checkout -q -- scripts/sumela-migrations/0.19.9.md
m "$WORK/sym" plan --scope developer
rc_is "a notes file committed as a symlink is refused" 1
has "…saying why" "$OUT" "is not a regular file (mode 120000"
lacks "…and its target's step is never listed" "$OUT" "0.19.9-01  "

echo "== t_explicit_consent_requires_flag"
EX="$WORK/ex-notes"; mkdir -p "$EX"
cat > "$EX/0.20.0.md" <<'EOF'
```sumela-step
id: 0.20.0-01
title: An invasive step
scope: developer
when: first-session
consent: explicit
run: bash "{ROOT}/tools/step.sh" invasive
verify: bash "{ROOT}/tools/check.sh" invasive
expect: equals:ok
rollback: bash -c "rm -f done-invasive"
```

```sumela-step
id: 0.20.0-02
title: Loosen a control (agent-performed)
scope: developer
when: first-session
consent: explicit
run: -
verify: git config --local --get sumela.loose
expect: equals:yes
agent: run git config --local sumela.loose yes
```
EOF
mk_project "$WORK/ex" 0.20.0 "$EX"
m "$WORK/ex" run 0.20.0-02
rc_is "an explicit run: - step refuses without --confirmed-by-user too (exit 2)" 2
lacks "…and does not hand out its agent: line" "$OUT" "agent: run git config"
m "$WORK/ex" run 0.20.0-02 --confirmed-by-user
rc_is "with --confirmed-by-user it prints the agent: line" 0
has "…the instruction itself" "$OUT" "agent: run git config --local sumela.loose yes"
m "$WORK/ex" run 0.20.0-01
rc_is "an explicit step refuses without --confirmed-by-user (exit 2)" 2
if [ ! -e "$WORK/ex/done-invasive" ]; then ok "…and runs nothing"; else bad "…and runs nothing"; fi
m "$WORK/ex" run 0.20.0-01 --confirmed-by-user
rc_is "with --confirmed-by-user it runs" 0
if [ -e "$WORK/ex/done-invasive" ]; then ok "…and its command ran"; else bad "…and its command ran"; fi
m "$WORK/ex" record 0.20.0-01 done; rc_is "…and records" 0
m "$WORK/ex" rollback 0.20.0-01
rc_is "rollback needs --confirmed-by-user too (exit 2)" 2
m "$WORK/ex" rollback 0.20.0-01 --confirmed-by-user
rc_is "rollback runs the step's rollback line" 0
if [ ! -e "$WORK/ex/done-invasive" ]; then ok "…which undid the artifact"; else bad "…which undid the artifact"; fi
m "$WORK/ex" status --scope developer
same "…and the step is pending again (beside the agent-performed one)" "pending_developer=2" "$OUT"

echo "== t_until_makes_step_moot_and_from_is_exclusive"
UT="$WORK/until-notes"; write_generic "$UT"
{ step_block 0.20.0-01 repo post-update "until: 0.20.1"
  step_block 0.20.0-02 repo post-update "until: 0.20.2"; } > "$UT/0.20.0.md"
{ step_block 0.20.1-01 repo post-update; } > "$UT/0.20.1.md"
mk_release "$WORK/until-rel" 0.20.1 v0.20.1 "$UT"; UP="$WORK/until-rel" mk_project "$WORK/up" 0.19.0
m "$WORK/up" plan --source "$(src_of "$WORK/until-rel")" --scope repo
lacks "a jump past until drops the step" "$OUT" "0.20.0-01 "
has "…a later until keeps it" "$OUT" "0.20.0-02 "
m "$WORK/up" run 0.20.0-01
rc_is "run refuses a moot step" 1
has "…and says why" "$OUT" "is moot"
m "$WORK/up" show 0.20.0-01
has "show says so too" "$OUT" "status: moot (until 0.20.1; the release is v0.20.1)"
UP="$WORK/until-rel" mk_project "$WORK/up2" 0.20.0
m "$WORK/up2" plan --source "$(src_of "$WORK/until-rel")" --scope repo
lacks "a version step at the version the upgrade starts from is not selected (from is exclusive)" "$OUT" "0.20.0-02 "
has "…the next version's is" "$OUT" "0.20.1-01 "
m "$WORK/tm" show 0.20.0-02
has "a developer step with until <= the installed version is moot" "$OUT" "status: moot (until 0.20.1; this install is at v0.20.1)"

echo "== t_agent_step_needs_the_worktree"
AG="$WORK/agent-notes"; write_generic "$AG"
cat > "$AG/0.20.0.md" <<'EOF'
```sumela-step
id: 0.20.0-01
title: An agent step without requires
scope: repo
when: post-update
consent: confirm
run: -
verify: bash "{SRC}/tools/check.sh" agent
expect: equals:ok
agent: edit the settings file in {ROOT}
```
EOF
mk_release "$WORK/agent-rel" 0.20.0 v0.20.0 "$AG"; UP="$WORK/agent-rel" mk_project "$WORK/ag" 0.19.0
m "$WORK/ag" plan --source "$(src_of "$WORK/agent-rel")" --scope repo
rc_is "plan lists the agent step" 0
m "$WORK/ag" run 0.20.0-01
rc_is "a run: - repo step other than upgrade-01 is refused in the main checkout" 1
has "…it needs the upgrade worktree" "$OUT" "runs in the upgrade worktree, which upgrade-01 creates"
lacks "…and its agent: line, which names {ROOT}, is not printed" "$OUT" "agent: edit the settings file"
m "$WORK/ag" show 0.20.0-01
has "show says what works in the main checkout" "$OUT" "(no upgrade worktree yet: only upgrade-01 and verify work here)"
m "$WORK/ag" run upgrade-01
rc_is "upgrade-01's agent: line is printed there" 0

echo "== t_set_worktree_moves_from"
UP="$WORK/until-rel" mk_project "$WORK/sf" 0.19.0
printf '0.20.0\n' > "$WORK/sf/.sumela/VERSION"; g -C "$WORK/sf" commit -qam "main at 0.20.0"
g -C "$WORK/sf" branch base-0.19 HEAD~1
m "$WORK/sf" plan --source "$(src_of "$WORK/until-rel")" --scope repo
has "the plan starts from the main checkout's v0.20.0" "$OUT" "v0.20.0 -> v0.20.1"
g -C "$WORK/sf" worktree add -q --no-track -b sumela/upgrade-0.20.1 "$WORK/sf-wt" base-0.19 >/dev/null 2>&1
m "$WORK/sf" set prefix=sumela/ base=base-0.19 "worktree=$WORK/sf-wt"
has "set worktree= takes the worktree's older VERSION as the start" "$OUT" "the upgrade now starts from v0.19.0"
m "$WORK/sf" plan --source "$(src_of "$WORK/until-rel")" --scope repo
has "…so the steps of the versions it spans are listed" "$OUT" "0.20.0-02 "

echo "== t_subst_quotes_paths_with_spaces_and_quotes"
SQ="$WORK/sq-notes"; write_generic "$SQ"
cat > "$SQ/0.20.0.md" <<'EOF'
```sumela-step
id: 0.20.0-01
title: Paths reach the step intact
scope: repo
when: post-update
consent: confirm
run: bash "{SRC}/tools/args.sh" "{ROOT}" "{SRC}/x y" v{TARGET}
verify: bash "{SRC}/tools/args.sh" "{ROOT}"
expect: match:^arg=
agent: the clone is {SRC} and the checkout {ROOT}
```
EOF
if [ "$ON_WINDOWS" = true ]; then ODD="$WORK/odd dir 'a' \$x \`b\`"   # Windows forbids " in names
else ODD="$WORK/odd dir \"q\" 'a' \$x \`b\`"; fi
mkdir -p "$ODD"
mk_release "$ODD/rel" 0.20.0 v0.20.0 "$SQ"; UP="$ODD/rel" mk_project "$ODD/proj" 0.19.0
ODD_SRC="$(src_of "$ODD/rel")"
m "$ODD/proj" plan --source "$ODD_SRC" --scope repo; rc_is "plan accepts a clone path with spaces and quotes" 0
P="$ODD/proj"; WT="$ODD/proj upgrade"; TGT=0.20.0; STEP_LOG=""
step_through "$P" upgrade-01
same "the worktree path with spaces and quotes is recorded" "" "$STEP_LOG"
m "$P" show 0.20.0-01
has "show prints the command with environment references" "$OUT" 'run: bash "${SUMELA_MIGRATE_SRC}/tools/args.sh" "${SUMELA_MIGRATE_ROOT}" "${SUMELA_MIGRATE_SRC}/x y" v0.20.0'
has "…and the agent text with the plain paths" "$OUT" "agent: the clone is $ODD_SRC and the checkout $WT"
m "$P" run 0.20.0-01
rc_is "the step runs" 0
has "{ROOT} arrives as one argument, byte for byte" "$OUT" "arg=$WT"
has "{SRC} inside a longer quoted word too" "$OUT" "arg=$ODD_SRC/x y"
has "{TARGET} is substituted literally" "$OUT" "arg=v0.20.0"
has "the step sees SUMELA_MIGRATE_SRC" "$OUT" "src=$ODD_SRC"
m "$P" verify 0.20.0-01; rc_is "verify runs with the same environment" 0

echo "== t_set_and_state"
m "$WORK/u2" set worktree="$WORK/rel"
rc_is "set refuses a directory that is not a worktree of this repository" 1
m "$WORK/u2" set "worktree=$WORK/u2"
rc_is "set refuses the main checkout: the upgrade runs in a linked worktree" 1
has "…and says so" "$OUT" "is the main checkout"
m "$WORK/u2" set clone=/elsewhere
rc_is "set refuses a key that plan --source owns" 1
m "$WORK/u2" set base=no-such-ref
rc_is "set refuses a base that is not a commit" 1
m "$WORK/u2" set 'prefix=bad prefix/'
rc_is "set refuses a prefix that makes no branch name" 1
m "$WORK/u2" set "prefix=a$(printf '\t')b/"
rc_is "set refuses a value with a control character" 1
# The upgrade branch tracks nothing but its own remote branch: else a push could land on the base.
g -C "$WORK/u2" worktree add -q -b sumela/upgrade-0.20.0 "$WORK/u2-wt" main >/dev/null 2>&1
g -C "$WORK/u2" branch -q --set-upstream-to=main sumela/upgrade-0.20.0
m "$WORK/u2" set "worktree=$WORK/u2-wt"
rc_is "set refuses a worktree whose branch tracks another branch (the base)" 1
has "…naming it and the fix" "$OUT" "tracks refs/heads/main: a push could land there"
m "$WORK/u2" set branch=sumela/upgrade-0.20.0
rc_is "…and such a branch named by set branch= too" 1
g -C "$WORK/u2" branch -q --unset-upstream sumela/upgrade-0.20.0
g -C "$WORK/u2" config branch.sumela/upgrade-0.20.0.remote origin
g -C "$WORK/u2" config branch.sumela/upgrade-0.20.0.merge refs/heads/sumela/upgrade-0.20.0
m "$WORK/u2" set "worktree=$WORK/u2-wt"
rc_is "…and accepts one that tracks its own remote branch (after git push -u)" 0
m "$WORK/tm" set prefix=sumela/
rc_is "set needs an upgrade in progress" 1

echo ""
echo "Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
