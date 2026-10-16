#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# tests/test_migration_notes.sh — the shipped migration notes, linted and run end to end (R1-08).
#
#   t_shipped_notes_lint                 every file in scripts/sumela-migrations/ passes the notes
#                                        lint, and the lint bites on a planted defect
#   t_e2e_repo_steps_v019_fixture        every repo step of upgrade.md plus the release's own
#                                        notes, run by the release clone's runner on a
#                                        v0.19-shaped project (git archive v0.19.0 + setup.sh)
#                                        with forks and a v1 provenance record: the test performs
#                                        each run: - step's scripted equivalent, passes
#                                        --confirmed-by-user where a step is explicit, and
#                                        asserts every verify [RU-I3]
#   t_e2e_jump_0_19_to_latest            the same from v0.19.0 straight to the newest notes'
#                                        version: every version's repo steps in one worktree, one
#                                        apply and one commit [RU-I2]
#
# The release is built from this working tree: a throwaway upstream whose v0.19.0 is the real
# v0.19.0 tree and whose v<target> is this tree (VERSION raised to the newest notes' version
# while it is lower), both annotated tags.
#
# Tools the notes call. Before every task that implements them has landed (update.sh's agent
# mode, R1-04/R1-05; the registry parity script, R1-07), a release tree may lack a script or a
# flag the notes name. The test checks each <script, flag> pair the shipped repo steps call; a
# pair the tree lacks is replaced, in the throwaway release only, by a stub that speaks the
# plan's contract for it, and the run is labelled "stub". Once this tree's .sumela/VERSION
# reaches the newest notes' version (the release task bumps it), a missing pair FAILS instead:
# a release never ships notes its own tools cannot run.
#
# With pwsh on PATH, every e2e also runs through the PowerShell runner: natively (the steps'
# run.ps1 / verify.ps1 lines) once this tree's PowerShell tools take every parameter the notes
# pass, else, outside Windows, routed through bash as under a Restricted execution policy
# (PSExecutionPolicyPreference=Restricted) [RU-I13]. On Windows that policy stops the -File
# runner itself, so before the release the PowerShell pass waits for the tools.
#
# Run from anywhere:  bash tests/test_migration_notes.sh
# Exit 0 = all assertions passed, 1 = a failure (printed above).
# -----------------------------------------------------------------------------
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NOTES_DIR="$REPO_ROOT/scripts/sumela-migrations"
RUNNER="$REPO_ROOT/scripts/sumela-migrate.sh"
[ -f "$RUNNER" ] || { echo "FAIL: $RUNNER missing"; exit 1; }
# shellcheck source=../scripts/lib/sumela-provenance.sh
. "$REPO_ROOT/scripts/lib/sumela-provenance.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
WORK="$(cd "$WORK" && pwd -P)"

PASS=0 FAIL=0
ok()   { echo "  PASS  $1"; PASS=$((PASS + 1)); }
bad()  { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); }
same() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }
has()  { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 (wanted '$3' in:"; printf '%s\n' "$2" | tail -15 | sed 's/^/        /'; echo "        )" ;; esac; }

case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) ON_WINDOWS=true ;; *) ON_WINDOWS=false ;; esac
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_PREFIX
export XDG_STATE_HOME="$WORK/state"
if [ "$ON_WINDOWS" = true ]; then
  mkdir -p "$WORK/localappdata"; LOCALAPPDATA="$(cygpath -w "$WORK/localappdata")"; export LOCALAPPDATA
fi
export SUMELA_SKIP_MEMORY_SETUP=1                    # setup.sh: no pip, no Docker in a fixture
export GIT_ALLOW_PROTOCOL="file:https:ssh:git"
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=t@example.com
# Fixture commits skip the hooks: the e2e checks the notes, not the project's pre-commit.
g() { git -c commit.gpgsign=false -c tag.gpgsign=false -c core.hooksPath="$WORK/no-hooks" -c init.defaultBranch=main "$@"; }
PWSH="$(command -v pwsh 2>/dev/null || true)"

vkey() { LC_ALL=C awk -v v="$1" 'BEGIN { sub(/-rc\.[0-9]+$/, "", v); split(v, a, "."); printf "%06d.%06d.%06d\n", a[1], a[2], a[3] }'; }
TREE_VERSION="$(tr -d ' \t\r\n' < "$REPO_ROOT/.sumela/VERSION")"
LATEST=""
for f in "$NOTES_DIR"/*.md; do
  v="${f##*/}"; v="${v%.md}"
  printf '%s' "$v" | LC_ALL=C grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || continue
  if [ -z "$LATEST" ] || [ "$(vkey "$v")" \> "$(vkey "$LATEST")" ]; then LATEST="$v"; fi
done
[ -n "$LATEST" ] || { echo "FAIL: no <X.Y.Z>.md notes in $NOTES_DIR"; exit 1; }
RELEASED=false; [ "$(vkey "$TREE_VERSION")" \< "$(vkey "$LATEST")" ] || RELEASED=true
TARGET="$LATEST"; [ "$RELEASED" = true ] && TARGET="$TREE_VERSION"

echo "Shipped migration notes (scripts/sumela-migrations/)"
echo "  tree VERSION $TREE_VERSION, newest notes $LATEST, e2e target v$TARGET ($([ "$RELEASED" = true ] && echo release || echo pre-release))"

echo "== t_shipped_notes_lint"
OUT="$(bash "$RUNNER" lint "$NOTES_DIR"/*.md 2>&1)"; RC=$?
same "the notes lint passes every shipped file" 0 "$RC"
[ "$RC" = 0 ] || printf '%s\n' "$OUT" | sed 's/^/        /'
for f in "$NOTES_DIR"/*; do
  bn="${f##*/}"
  case "$bn" in
    README.md) has "README.md is documentation, not notes" "$OUT" "README.md: documentation" ;;
    upgrade.md|*.md) has "$bn is linted" "$OUT" "$bn: ok (" ;;
    *) bad "$bn: every file in scripts/sumela-migrations/ is README.md, upgrade.md or <X.Y.Z>.md" ;;
  esac
done
OUT="$(bash "$RUNNER" lint 2>&1)"; RC=$?
same "lint without arguments checks the same shipped files" 0 "$RC"
mkdir -p "$WORK/planted"; cp "$NOTES_DIR"/*.md "$WORK/planted/"
LC_ALL=C awk '/^id: upgrade-03$/ { f = 1 } f && /^consent: / { print "consent: none"; f = 0; next } { print }' "$NOTES_DIR/upgrade.md" > "$WORK/planted/upgrade.md"
OUT="$(bash "$RUNNER" lint "$WORK/planted/upgrade.md" 2>&1)"; RC=$?
same "the lint bites on the shipped text: consent: none on the apply step" 4 "$RC"
has "…naming the step" "$OUT" "step upgrade-03: consent: none needs"
LC_ALL=C sed 's/"{SRC}\/scripts\/update.sh"/{SRC}\/scripts\/update.sh/' "$NOTES_DIR/upgrade.md" > "$WORK/planted/upgrade.md"
OUT="$(bash "$RUNNER" lint "$WORK/planted/upgrade.md" 2>&1)"; RC=$?
same "…and on an unquoted {SRC}" 4 "$RC"

# --- The release and the project ----------------------------------------------------------------
# repo_needs <notes...>: "<script>\t<flag>" for every flag the repo steps' bash lines (run, verify,
# rollback) pass a scripts/*.sh, and "<script>\t-<Name>" for the PowerShell lines' scripts/*.ps1.
repo_needs() {
  LC_ALL=C awk '
    function scan(cmd,   n, t, i, tok, script) {
      gsub(/"/, "", cmd); n = split(cmd, t, /[ \t]+/); script = ""
      for (i = 1; i <= n; i++) {
        tok = t[i]; sub(/^\{SRC\}\//, "", tok)
        if (tok ~ /^scripts\/[A-Za-z0-9_.-]+\.(sh|ps1)$/) { script = tok; print script "\t"; continue }
        if (script != "" && tok ~ /^--?[A-Za-z][A-Za-z-]*$/) print script "\t" tok
      }
    }
    { sub(/\r$/, "") }
    /^```sumela-step/ { inb = 1; n = 0; repo = 0; next }
    inb && /^```/ { if (repo) for (i = 1; i <= n; i++) scan(c[i]); inb = 0; next }
    inb && /^scope: repo$/ { repo = 1 }
    inb && /^(run|verify|rollback)(\.ps1)?: / { c[++n] = substr($0, index($0, ":") + 2) }' "$@" | LC_ALL=C sort -u
}
# missing_in <tree>: the needed pairs the tree's scripts lack (a .ps1 flag -Name is found as $Name)
missing_in() {
  local tree="$1" s fl
  while IFS="$(printf '\t')" read -r s fl; do
    [ -f "$tree/$s" ] || { printf '%s\t(missing script)\n' "$s"; continue; }
    [ -n "$fl" ] || continue
    case "$s" in
      *.ps1) LC_ALL=C grep -qiE -- "[\$]${fl#-}([^A-Za-z0-9_]|\$)" "$tree/$s" || printf '%s\t%s\n' "$s" "$fl" ;;
      *) LC_ALL=C grep -qF -- "$fl" "$tree/$s" || printf '%s\t%s\n' "$s" "$fl" ;;
    esac
  done
}

write_stub_update() {  # <file>: update.sh's agent mode as the notes use it (R1-04/R1-05 contract)
  cat > "$1" <<'STUB'
#!/usr/bin/env bash
# STUB written by tests/test_migration_notes.sh into a throwaway release ONLY, while this tree's
# updater lacks the agent mode the notes call (R1-04/R1-05). It speaks that contract: --plan,
# --plan-check, --apply-plan, --verify-applied, --stage, --undo-plan. Forks (LOCAL != BASE) are kept.
set -uo pipefail
SRC="" MODE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --source) SRC="$2"; shift ;;
    --plan|--plan-check|--apply-plan|--verify-applied|--stage|--undo-plan) MODE="$1" ;;
    *) echo "stub update.sh: unsupported argument $1" >&2; exit 1 ;;
  esac
  shift
done
ROOT="$PWD"; UPG="$ROOT/.sumela/.upgrade"; mkdir -p "$UPG"; [ -f "$UPG/.gitignore" ] || printf '*\n' > "$UPG/.gitignore"
CORE=".sumela/sumela-prompt.md .sumela/skills .sumela/git-hooks .sumela/rules/templates docs/second-brain/template scripts"
same_text() { cmp -s "$1" "$2" && return 0; [ -f "$1" ] && [ -f "$2" ] && [ "$(tr -d '\r' < "$1" | git hash-object --stdin)" = "$(tr -d '\r' < "$2" | git hash-object --stdin)" ]; }
tree() { mkdir -p "$3"; git -C "$1" archive --format=tar -o "$3.tar" "$2" -- $CORE && tar -xf "$3.tar" -C "$3"; }
fingerprint() { { git -C "$1" rev-parse HEAD; LC_ALL=C sed -n 's/^[a-z]*\t\([^\t]*\)\t.*/\1/p' "$UPG/plan.tsv" | while IFS= read -r p; do if [ -f "$ROOT/$p" ]; then git hash-object -- "$ROOT/$p"; else echo -; fi; done; } | git hash-object --stdin; }
counts() { LC_ALL=C awk -F'\t' '!/^#/ { c[$1]++ } END { printf "%d add, %d apply, %d keep", c["add"], c["apply"], c["keep"] }' "$UPG/plan.tsv"; }
case "$MODE" in
  --plan)
    W="$(mktemp -d)"; base="v$(tr -d '[:space:]' < .sumela/VERSION)"
    tree "$SRC" "$base" "$W/base" && tree "$SRC" HEAD "$W/theirs" || { echo "stub update.sh: cannot read $SRC" >&2; exit 1; }
    { printf '# source %s\n' "$SRC"
      (cd "$W/theirs" && find . -type f | sed 's#^\./##' | LC_ALL=C sort) | while IFS= read -r p; do
        if [ ! -e "$ROOT/$p" ]; then a=add
        elif same_text "$ROOT/$p" "$W/theirs/$p"; then continue
        elif [ -f "$W/base/$p" ] && same_text "$ROOT/$p" "$W/base/$p"; then a=apply
        else a=keep; fi
        if [ -f "$ROOT/$p" ]; then b="$(git hash-object -- "$ROOT/$p")"; else b=-; fi
        printf '%s\t%s\t%s\n' "$a" "$p" "$b"
      done; } > "$UPG/plan.tsv"
    printf '# fingerprint %s\n' "$(fingerprint "$SRC")" >> "$UPG/plan.tsv"
    rm -rf "$W"
    echo "plan: $(counts) (stub; forks are kept)"; LC_ALL=C awk -F'\t' '$1 == "keep" { print "  keep  " $2 }' "$UPG/plan.tsv" ;;
  --plan-check)
    [ -f "$UPG/plan.tsv" ] || { echo "no plan"; exit 4; }
    [ "$(sed -n 's/^# fingerprint //p' "$UPG/plan.tsv")" = "$(fingerprint "$SRC")" ] || { echo "stale plan"; exit 4; }
    echo "plan ok: $(counts)" ;;
  --apply-plan)
    [ -f "$UPG/plan.tsv" ] && [ "$(sed -n 's/^# fingerprint //p' "$UPG/plan.tsv")" = "$(fingerprint "$SRC")" ] || { echo "stale plan" >&2; exit 4; }
    W="$(mktemp -d)"; tree "$SRC" HEAD "$W/theirs"; : > "$UPG/applied.tsv"
    while IFS="$(printf '\t')" read -r a p _; do
      case "$a" in add|apply) mkdir -p "$(dirname "$ROOT/$p")"; cp "$W/theirs/$p" "$ROOT/$p.tmp.$$" && mv -f "$ROOT/$p.tmp.$$" "$ROOT/$p"; printf '%s\n' "$p" >> "$UPG/applied.tsv" ;; esac
    done < "$UPG/plan.tsv"
    v="$(git -C "$SRC" show HEAD:.sumela/VERSION | tr -d '[:space:]')"; old="$(tr -d '[:space:]' < .sumela/VERSION)"
    printf '%s\n' "$v" > .sumela/VERSION; printf '.sumela/VERSION\n' >> "$UPG/applied.tsv"
    . "$SRC/scripts/lib/sumela-provenance.sh"
    sumela_record_write "$v" complete --base-version "$old" --files "$(cat "$UPG/applied.tsv")" || exit 1
    rm -rf "$W"; echo "applied the plan: v$v (stub)" ;;
  --verify-applied)
    src="$(sed -n 's/^# source //p' "$UPG/plan.tsv")"; v="$(tr -d '[:space:]' < .sumela/VERSION)"; k=0
    while IFS="$(printf '\t')" read -r a p b; do
      [ "$a" = keep ] || continue
      [ "$(git hash-object -- "$ROOT/$p")" = "$b" ] || { echo "kept file changed: $p"; exit 3; }; k=$((k + 1))
    done < "$UPG/plan.tsv"
    [ "$v" = "$(git -C "$src" show HEAD:.sumela/VERSION | tr -d '[:space:]')" ] || { echo "VERSION is $v"; exit 3; }
    echo "verified: upgrade complete $v; $k kept unchanged; 0 merged keep their local lines" ;;
  --stage)
    while IFS= read -r p; do git add -A -- "$p"; done < "$UPG/applied.tsv"; echo "staged $(wc -l < "$UPG/applied.tsv" | tr -d ' ') paths" ;;
  --undo-plan)
    [ -f "$UPG/applied.tsv" ] || { echo "nothing to undo"; exit 0; }
    while IFS= read -r p; do
      if git cat-file -e "HEAD:./$p" 2>/dev/null; then git checkout -q HEAD -- "$p"
      else git rm -q --cached --ignore-unmatch -- "$p"; rm -f -- "$p"; fi
    done < "$UPG/applied.tsv"
    rm -f "$UPG/applied.tsv" "$UPG/plan.tsv"; echo "undone: every applied path is back at HEAD (stub)" ;;
  *) echo "stub update.sh: no mode" >&2; exit 1 ;;
esac
STUB
}
write_stub_parity() {  # <file>: the registry parity contract as the notes use it (R1-07)
  cat > "$1" <<'STUB'
#!/usr/bin/env bash
# STUB written by tests/test_migration_notes.sh into a throwaway release ONLY, while this tree
# lacks scripts/sumela-registry-parity.sh (R1-07): --plan, --check, --sync --yes, no drift.
for a in "$@"; do case "$a" in --plan|--check|--sync|--yes) ;; *) echo "stub parity: unsupported $a" >&2; exit 1 ;; esac; done
echo "registry parity: 0 drifted (stub)"
STUB
}

# The throwaway upstream: v0.19.0 is the real v0.19.0 tree; v<TARGET> is this working tree.
REL="$WORK/upstream"; mkdir -p "$REL"
g init -q "$REL"
g -C "$REPO_ROOT" -c core.autocrlf=false archive v0.19.0 | tar -x -C "$REL"
g -C "$REL" add -A && g -C "$REL" commit -qm "SumelaOS 0.19.0" && g -C "$REL" tag -a -m v0.19.0 v0.19.0
g -C "$REL" rm -rq . >/dev/null
( cd "$REPO_ROOT" && git -c core.quotePath=false ls-files -z --cached --others --exclude-standard |
    while IFS= read -r -d '' p; do [ -f "$p" ] && printf '%s\0' "$p"; done ) > "$WORK/release.list"
( cd "$REPO_ROOT" && tar -c -f - --null -T "$WORK/release.list" ) | tar -x -f - -C "$REL"
[ "$RELEASED" = true ] || printf '%s\n' "$TARGET" > "$REL/.sumela/VERSION"
NEEDS="$(repo_needs "$NOTES_DIR/upgrade.md" "$NOTES_DIR"/[0-9]*.md)"
MISSING="$(printf '%s\n' "$NEEDS" | LC_ALL=C grep -v '\.ps1	' | missing_in "$REL")"
MISSING_PS="$(printf '%s\n' "$NEEDS" | LC_ALL=C grep '\.ps1	' | missing_in "$REL")"
MODE=real
if [ -n "$MISSING" ]; then
  if [ "$RELEASED" = true ]; then
    bad "the release tree implements every script and flag its notes call (missing: $(printf '%s\n' "$MISSING" | tr '\t\n' ' ;'))"
  else
    MODE=stub
    echo "  NOTE  pre-release stub mode: this tree lacks $(printf '%s\n' "$MISSING" | tr '\t\n' ' ;')"
    printf '%s\n' "$MISSING" | cut -f1 | LC_ALL=C sort -u | while IFS= read -r s; do
      case "$s" in
        scripts/update.sh) write_stub_update "$REL/$s" ;;
        scripts/sumela-registry-parity.sh) write_stub_parity "$REL/$s" ;;
        *) echo "  FAIL  no stub for $s: implement it or extend this test"; exit 1 ;;
      esac
    done || bad "every missing script has a stub"
  fi
fi
g -C "$REL" add -A && g -C "$REL" commit -qm "SumelaOS $TARGET" && g -C "$REL" tag -a -m "v$TARGET" "v$TARGET"

# The v0.19-shaped project: git archive v0.19.0, its own setup.sh, three forked CORE files and
# a v1 provenance record that lists them (the shape of a project an old updater upgraded). The
# archive is taken with core.autocrlf=false: v0.19.0 predates the *.sh eol=lf pin, and a CRLF
# setup.sh would not run (the e2e still checks out every worktree and clone with CRLF under
# the CI's core.autocrlf=true).
TEMPLATE="$WORK/template"; mkdir -p "$TEMPLATE"
g init -q "$TEMPLATE"
g -C "$REPO_ROOT" -c core.autocrlf=false archive v0.19.0 | tar -x -C "$TEMPLATE"
g -C "$TEMPLATE" add -A && g -C "$TEMPLATE" commit -qm "vendor SumelaOS 0.19.0"
if ( cd "$TEMPLATE" && bash scripts/setup.sh --non-interactive --project-name Demo --project-purpose "a demo fixture" \
      --stacks backend --ides claude --governance solo ) > "$WORK/setup.log" 2>&1; then :; else
  bad "the v0.19.0 setup.sh builds the fixture"; tail -20 "$WORK/setup.log" | sed 's/^/        /'
fi
FORKS=".sumela/skills/brainstorming/SKILL.md .sumela/rules/security_protocol.md scripts/status.sh"
for f in $FORKS; do printf '\n<!-- local fork line: %s -->\n' "$f" >> "$TEMPLATE/$f"; done
# The project's upstream is the throwaway one: the runner trusts a clone of it only.
printf '# SumelaOS upstream for this fixture\n%s\n' "$REL" > "$TEMPLATE/.sumela/upstream.conf"
# The project's hooks are not under test (fixture commits skip them), but a step line that runs
# git in the upgrade worktree (upgrade-04's rollback: git checkout) runs that worktree's copies.
# A v0.19 checkout has no eol pin, so under the CI's core.autocrlf=true they would be written
# with CRLF and fail the line ("env: bash\r", exit 127). They are pinned to LF in
# .git/info/attributes, which every worktree shares; every other file still checks out with CRLF.
printf '.sumela/git-hooks/* text eol=lf\n' > "$TEMPLATE/.git/info/attributes"
g -C "$TEMPLATE" add -A && g -C "$TEMPLATE" commit -qm "project: configure SumelaOS and fork three files"
{ printf '{\n  "version": "0.19.0",\n  "updated_at": "2026-09-19T10:00:00Z",\n  "pending_rerun": false,\n  "files": [\n'
  printf '    "%s",\n' $FORKS | sed '$ s/,$//'
  printf '  ]\n}\n'; } > "$TEMPLATE/.sumela/.last-update.json"
if git -C "$TEMPLATE" check-ignore -q .sumela/.last-update.json; then ok "the fixture's v1 record is gitignored, as setup makes it"; else bad "the fixture's v1 record is gitignored"; fi
same "the fixture is clean after setup" "" "$(git -C "$TEMPLATE" status --porcelain)"

# --- One end-to-end run ------------------------------------------------------------------------------
# mig: the release clone's runner, run from the project (the README's procedure)
MIG=()
mig() { local d="$1"; shift; OUT="$(cd "$d" && "${MIG[@]}" "$@" 2>&1)"; RC=$?; }
expected_ids() {  # <target>: the repo step ids the shipped notes select for 0.19.0 -> <target>, as a set
  LC_ALL=C awk -v t="$(vkey "$1")" '
    function vk(v, a) { split(v, a, "."); return sprintf("%06d.%06d.%06d", a[1], a[2], a[3]) }
    FNR == 1 { fv = FILENAME; sub(/.*\//, "", fv); sub(/\.md$/, "", fv) }
    { sub(/\r$/, "") }
    /^```sumela-step/ { inb = 1; id = ""; sc = ""; u = ""; next }
    inb && /^```/ { inb = 0
      if (sc != "repo") next
      if (fv != "upgrade" && !(vk(fv) > "000000.000019.000000" && vk(fv) <= t)) next
      if (u != "" && vk(u) <= t) next
      print id; next }
    inb && /^id: / { id = substr($0, 5) } inb && /^scope: / { sc = substr($0, 8) } inb && /^until: / { u = substr($0, 8) }' "$NOTES_DIR/upgrade.md" "$NOTES_DIR"/[0-9]*.md | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//'
}
# e2e <label> <target> <runner: bash|ps-native|ps-gitbash> [rollback]
# The project gets its own bare origin, with push.default=upstream: a branch that tracked the
# base would push into it. With "rollback", every shipped repo rollback runs after the commit, in
# reverse order, instead of the completion check.
e2e() {
  local label="$1" T="$2" how="$3" mode="${4:-}" P WT CL O id order log="" n runl consent mainsha b
  P="$WORK/$label/project"; WT="$WORK/$label/upgrade wt"; CL="$WORK/$label/release clone"; O="$WORK/$label/origin.git"
  mkdir -p "$WORK/$label"; cp -R "$TEMPLATE" "$P"
  g clone -q --bare "$P" "$O" && g -C "$P" remote add origin "$O" && g -C "$P" fetch -q origin && g -C "$P" config push.default upstream
  mainsha="$(git -C "$O" rev-parse main)"
  g clone -q "$REL" "$CL" && g -C "$CL" -c advice.detachedHead=false checkout -q "v$T"
  if [ "$how" = ps-gitbash ]; then
    MIG=(env PSExecutionPolicyPreference=Restricted "$PWSH" -NoProfile -File "$CL/scripts/sumela-migrate.ps1")
  elif [ "$how" = ps-native ]; then
    MIG=("$PWSH" -NoProfile -File "$CL/scripts/sumela-migrate.ps1")
  else
    MIG=(bash "$CL/scripts/sumela-migrate.sh")
  fi
  mig "$P" plan --source "$CL" --scope repo
  if [ "$RC" != 0 ]; then bad "[$label] plan --source exits 0 (exit $RC: $(printf '%s' "$OUT" | tail -5))"; return; fi
  order="$(printf '%s\n' "$OUT" | LC_ALL=C sed -n 's/^    \([^ ]*\)  .*consent=.*/\1/p' | tr '\n' ' ' | sed 's/ $//')"
  same "[$label] the plan selects upgrade.md and every version's repo steps for v0.19.0 -> v$T" \
    "$(expected_ids "$T")" "$(printf '%s\n' $order | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"
  case "$order" in "upgrade-01 "*) ok "[$label] the worktree step comes first" ;; *) bad "[$label] the worktree step comes first ($order)" ;; esac
  for id in $order; do
    mig "$P" show "$id"; [ "$RC" = 0 ] || { log="$log show $id ($RC);"; continue; }
    runl="$(printf '%s\n' "$OUT" | sed -n 's/^run: //p')"; consent="$(printf '%s\n' "$OUT" | sed -n 's/^consent: //p')"
    case "$id" in
      upgrade-01)      # the agent line, scripted: a branch that tracks nothing, from the remote base, then set
        g -C "$P" worktree add -q --no-track -b "sumela/upgrade-$T" "$WT" origin/main >/dev/null 2>&1 || { log="$log worktree add;"; continue; }
        mig "$P" set prefix=sumela/ base=origin/main "worktree=$WT"; [ "$RC" = 0 ] || { log="$log set ($RC: $OUT);"; continue; } ;;
      upgrade-05)      # the agent line: not-applicable without .sumela/mirrors.conf
        if [ ! -f "$WT/.sumela/mirrors.conf" ]; then
          mig "$P" record "$id" not-applicable; [ "$RC" = 0 ] || log="$log record $id ($RC);"; continue
        fi
        mig "$P" run "$id"; [ "$RC" = 0 ] || { log="$log run $id ($RC: $(printf '%s' "$OUT" | tail -3));"; continue; } ;;
      upgrade-07)      # the agent line, scripted: stage the applied rows and the ledgers, one commit, a push by explicit refspec
        ( cd "$WT" && bash scripts/update.sh --stage && g add -- .sumela/migrations-applied/ &&
          g commit -qm "chore(sumela): upgrade to v$T" && g push -q -u origin "HEAD:refs/heads/sumela/upgrade-$T" ) > "$WORK/$label/commit.log" 2>&1 ||
          { log="$log commit ($(tail -3 "$WORK/$label/commit.log"));"; continue; } ;;
      *)
        if [ "$runl" = "-" ]; then log="$log $id is run: - and this test has no scripted equivalent (add one);"; continue; fi
        if [ "$consent" = explicit ]; then mig "$P" run "$id" --confirmed-by-user; else mig "$P" run "$id"; fi
        [ "$RC" = 0 ] || { log="$log run $id ($RC: $(printf '%s' "$OUT" | tail -3));"; continue; } ;;
    esac
    mig "$P" verify "$id"; [ "$RC" = 0 ] || { log="$log verify $id ($RC: $(printf '%s' "$OUT" | tail -4));"; continue; }
    mig "$P" record "$id" done; [ "$RC" = 0 ] || log="$log record $id ($RC);"
  done
  same "[$label] every step runs and every verify passes, in plan order" "" "$log"
  same "[$label] the upgrade lives on one branch named by {TARGET}" "sumela/upgrade-$T" "$(git -C "$WT" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  same "[$label] …one commit above the base" 1 "$(git -C "$WT" rev-list --count origin/main..HEAD 2>/dev/null)"
  same "[$label] the push went to the upgrade branch on the remote" "$(git -C "$WT" rev-parse HEAD)" "$(git -C "$O" rev-parse "refs/heads/sumela/upgrade-$T" 2>/dev/null)"
  same "[$label] …never to the base (push.default=upstream)" "$mainsha" "$(git -C "$O" rev-parse main)"
  same "[$label] …and the branch now tracks its own remote branch" "origin/sumela/upgrade-$T" "$(git -C "$WT" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)"
  same "[$label] …whose subject names the release" "chore(sumela): upgrade to v$T" "$(git -C "$WT" log -1 --format=%s 2>/dev/null)"
  same "[$label] the worktree is at v$T" "$T" "$(tr -d '\r\n' < "$WT/.sumela/VERSION")"
  n=0; for f in $FORKS; do LC_ALL=C grep -qF "local fork line: $f" "$WT/$f" || { bad "[$label] fork $f keeps its local line"; n=1; }; done
  [ "$n" = 0 ] && ok "[$label] every fork keeps its local line"
  same "[$label] the upgrade commit carries a ledger entry for every recorded step but the procedural one" \
    "$(printf '%s\n' $order | LC_ALL=C grep -vxc upgrade-07)" \
    "$(git -C "$WT" show --name-only --format= HEAD | LC_ALL=C grep -c '^\.sumela/migrations-applied/')"
  has "[$label] the ledgers are in the provenance record's files" \
    "$(sumela_record_files "$WT/.sumela/.last-update.json" 2>&1)" ".sumela/migrations-applied/upgrade-02@$T"
  same "[$label] the main checkout is untouched" "" "$(git -C "$P" status --porcelain)"
  same "[$label] …and stays at v0.19.0" 0.19.0 "$(tr -d '\r\n' < "$P/.sumela/VERSION")"
  mig "$WT" plan --scope developer
  if [ "$RC" = 0 ]; then ok "[$label] the upgraded worktree reads its committed notes for developer steps"
  else bad "[$label] the upgraded worktree reads its committed notes for developer steps (exit $RC: $(printf '%s' "$OUT" | tail -3))"; fi
  mig "$P" status
  same "[$label] status: nothing is left" "pending_repo=0 pending_developer=0" "$OUT"
  if [ "$mode" = rollback ]; then
    # Every shipped repo rollback, in reverse order, before the merge (README step 9).
    log=""
    for id in $(printf '%s\n' $order | LC_ALL=C sed '1!G;h;$!d'); do
      mig "$P" show "$id"
      printf '%s\n' "$OUT" | grep -q '^rollback: ' || continue
      mig "$P" rollback "$id" --confirmed-by-user; [ "$RC" = 0 ] || log="$log rollback $id ($RC: $(printf '%s' "$OUT" | tail -3));"
      case "$id" in
        upgrade-07) same "[$label] upgrade-07's rollback undoes the upgrade commit" "$(git -C "$P" rev-parse origin/main)" "$(git -C "$WT" rev-parse HEAD 2>/dev/null)" ;;
        upgrade-03) same "[$label] upgrade-03's rollback (--undo-plan) restores VERSION in the worktree" 0.19.0 "$(tr -d '\r\n' < "$WT/.sumela/VERSION" 2>/dev/null)" ;;
      esac
    done
    same "[$label] every shipped rollback line runs" "" "$log"
    if [ ! -d "$WT" ]; then ok "[$label] upgrade-01's rollback removes the worktree"; else bad "[$label] upgrade-01's rollback removes the worktree"; fi
    same "[$label] …and the local upgrade branch" "" "$(git -C "$P" branch --list "sumela/upgrade-$T")"
    same "[$label] the main checkout is untouched" "" "$(git -C "$P" status --porcelain)"
    mig "$P" plan --source "$CL" --scope repo
    has "[$label] after the rollbacks the upgrade starts over at upgrade-01" "$OUT" "    upgrade-01  "
    return
  fi
  mig "$P" plan --source "$CL" --scope repo
  has "[$label] plan says every repo step is recorded (the procedural one included) and the merge is left" "$OUT" "every repo step is recorded: merge the upgrade pull request"
  if [ -e "$P/.sumela/.upgrade/migrate.state" ]; then ok "[$label] …and keeps its state until the merge (the rollbacks need it)"; else bad "[$label] …and keeps its state until the merge (the rollbacks need it)"; fi
  # The pull request is merged and the main checkout updated: the upgrade is complete.
  g -C "$P" merge -q --no-ff -m "Merge the upgrade to v$T" "sumela/upgrade-$T" > "$WORK/$label/merge.log" 2>&1 || bad "[$label] the upgrade branch merges into the main checkout ($(tail -3 "$WORK/$label/merge.log"))"
  mig "$P" plan --scope repo
  has "[$label] once the main checkout has the merge, plan reports the upgrade complete" "$OUT" "the upgrade to v$T is complete (the main checkout is at v$T)"
  if [ ! -e "$P/.sumela/.upgrade/migrate.state" ]; then ok "[$label] …and removes its state"; else bad "[$label] …and removes its state"; fi
}

PS_HOW=none
if [ -n "$PWSH" ] && [ -f "$REPO_ROOT/scripts/sumela-migrate.ps1" ]; then
  if [ -z "$MISSING_PS" ]; then PS_HOW=ps-native
  elif [ "$ON_WINDOWS" != true ]; then PS_HOW=ps-gitbash
  fi
fi
ps_pass() {  # <label> <target>
  case "$PS_HOW" in
    ps-native) echo "  -- the PowerShell runner, running the steps' PowerShell forms"; e2e "$1" "$2" ps-native ;;
    ps-gitbash) echo "  -- the PowerShell runner, routed through bash (Restricted execution policy)"; e2e "$1" "$2" ps-gitbash ;;
    *) if [ -z "$PWSH" ] || [ ! -f "$REPO_ROOT/scripts/sumela-migrate.ps1" ]; then echo "  SKIP  the PowerShell runner (pwsh or scripts/sumela-migrate.ps1 unavailable)"
       else echo "  SKIP  the PowerShell runner on Windows before its tools take every parameter (see the NOTE)"; fi ;;
  esac
}
echo "== t_e2e_repo_steps_v019_fixture ($MODE)"
e2e e2e-bash "$TARGET" bash
echo "  -- every shipped repo rollback, in reverse order, before the merge"
e2e rollback-bash "$TARGET" bash rollback
ps_pass e2e-ps "$TARGET"
if [ -n "$MISSING_PS" ]; then
  if [ "$RELEASED" = true ]; then
    bad "the release tree implements every PowerShell script and parameter its notes call (missing: $(printf '%s\n' "$MISSING_PS" | tr '\t\n' ' ;'))"
  else
    echo "  NOTE  run.ps1 lines not run natively before the release (missing: $(printf '%s\n' "$MISSING_PS" | tr '\t\n' ' ;'))"
  fi
fi

echo "== t_e2e_jump_0_19_to_latest ($MODE)"
JUMP="$LATEST"; [ "$(vkey "$TARGET")" \> "$(vkey "$JUMP")" ] && JUMP="$TARGET"
if [ "$JUMP" = "$TARGET" ]; then
  echo "  NOTE  the newest notes are v$JUMP, the release itself: the jump is the run above with every version's notes in (0.19.0, $JUMP]"
fi
e2e jump-bash "$JUMP" bash
ps_pass jump-ps "$JUMP"

echo ""
echo "Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
