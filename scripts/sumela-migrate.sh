#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# sumela-migrate.sh — run a SumelaOS release's migration steps, in order (v0.20.0+).
#
# A release ships machine-readable notes in scripts/sumela-migrations/: upgrade.md (the
# version-agnostic repo procedure) and <X.Y.Z>.md (the steps one version needs). This runner
# selects the steps that are still pending, prints each one with its placeholders substituted,
# runs it from the right checkout, verifies it by the artifact it names (never by the exit code
# alone) and writes its ledger entry. scripts/sumela-migrations/README.md is the agent
# procedure and the notes format; scripts/sumela-migrate.ps1 is the PowerShell twin.
#
# Usage (from inside the project's checkout; the runner may live in the release clone):
#   bash <clone>/scripts/sumela-migrate.sh plan --source <clone> [--scope repo|developer] [--trust-origin <url>]
#   bash scripts/sumela-migrate.sh plan [--scope repo|developer]  # resume, or developer steps
#   bash scripts/sumela-migrate.sh set <key>=<value>...           # prefix, base, branch, worktree
#   bash scripts/sumela-migrate.sh show <id>
#   bash scripts/sumela-migrate.sh run <id> [--confirmed-by-user]
#   bash scripts/sumela-migrate.sh verify <id>
#   bash scripts/sumela-migrate.sh record <id> done|declined|not-applicable
#   bash scripts/sumela-migrate.sh rollback <id> --confirmed-by-user
#   bash scripts/sumela-migrate.sh status [--scope repo|developer]
#   bash scripts/sumela-migrate.sh lint [<notes.md>...]
# --trust-origin <url> (plan --source only): the user confirmed a release clone of <url>, which is
# not the project's upstream; the clone's origin must be <url>, and <url> must confirm the tag.
# --allow-untagged (maintainer tests only, and only with SUMELA_MIGRATE_ALLOW_UNTAGGED=1 in the
# environment) accepts a release clone whose HEAD is not an annotated v<X.Y.Z> or
# v<X.Y.Z>-rc.<n> tag.
#
# Exit codes: 0 ok; 1 error (usage, refused source, failed command); 2 consent required (a step
# whose consent is not none or confirm, a run: - one included, or a rollback, without
# --confirmed-by-user); 3 verify failed; 4 invalid notes.
#
# The release clone (plan --source) is trusted only when: its path is plain (no control
# character); it is a clean checkout (every tracked file as committed, nothing untracked, no
# assume-unchanged or skip-worktree entry); HEAD is at an annotated v<target> or v<target>-rc.<n>
# tag; its origin is this project's upstream (.sumela/upstream.conf, else the default below) or
# the URL the user confirmed (--trust-origin), a local path on Windows in any of its spellings
# (/c/x, C:\x, file:///C:/x: url_key); and `git ls-remote <that URL> <tag>^{}`, run
# outside every repository, names HEAD. The clone's own git configuration is not trusted: no
# fsmonitor hook, untracked cache or relaxed stat check applies (cgit), and no url.<x>.insteadOf
# can redirect the ls-remote. Later commands check the same clone offline against the commit
# and origin plan recorded. Notes are read from the HEAD blobs with cat-file (regular files only,
# never a symlink), never from the working tree.
#
# Beyond printing and running:
#   - run and record done refuse a step whose requires are not recorded done;
#   - repo steps run, record and roll back only in the upgrade worktree (upgrade-01 creates it;
#     set worktree=... records it, and refuses a branch that tracks anything but its own remote
#     branch), never in the main checkout, where only upgrade-01's agent: line is printed; a
#     step with run: - only prints its agent: line, after the consent gate;
#   - run refuses a moot or out-of-range step, and one already recorded (unless it was declined);
#   - record done re-runs the verify first and records nothing when it fails;
#   - plan records a developer step whose read-only verify (the lint's allow-list) already
#     passes as "done (pre-satisfied)", and lists the declined steps of both scopes;
#   - rollback removes the step's ledger entry, runs its rollback line (restoring the entry if
#     the line fails), and so makes the step pending again; a repo rollback needs the upgrade
#     worktree, and stops once the main checkout reaches the target (after the merge,
#     git revert -m 1 <merge> undoes the repo steps);
#   - plan removes migrate.state once the main checkout's VERSION reaches the target (the merge
#     is in), or once every repo step is recorded and the upgrade worktree is gone; until then it
#     stays, so the repo rollbacks still work before the merge; status reports nothing pending.
#
# Files:
#   <main checkout>/.sumela/.upgrade/migrate.state   key=value lines: from, target, tag, commit,
#       clone, url (written by plan --source), prefix, base, branch, worktree (written by set),
#       and procedural (the recorded ledger: none steps, as <name>:<status> words). The main
#       checkout is the first entry of `git worktree list`; a resumed or new session reads it.
#   .sumela/migrations-applied/<id>   the repo ledger (tracked; a generic step's file is
#       upgrade-<NN>@<target>): "status:", "at:" and "version:" lines, added to the provenance
#       record's "files" (scripts/lib/sumela-provenance.sh). Written in {ROOT}.
#   <state dir>/migrations.log        the developer ledger, "<id>\t<status>\t<UTC>" per line,
#       mode 0600 in the 0700 per-developer state directory (scripts/lib/sumela-state.sh).
#
# Trust boundary: repo steps come only from the verified release clone; developer steps only from
# the notes committed at the HEAD of the checkout the runner runs in (unmodified against HEAD).
# Nothing else is ever read as a step. Steps run with {SRC} and {ROOT} as ${SUMELA_MIGRATE_SRC}
# and ${SUMELA_MIGRATE_ROOT}, so a path with spaces or quotes is never re-parsed; {TARGET} is the
# validated release version (the clone's .sumela/VERSION; an RC tag v<X.Y.Z>-rc.<n> selects its
# release's notes), regex-escaped inside a match: expect. {ROOT} is the upgrade worktree once
# upgrade-01 has recorded it, else the main checkout; a developer step runs in the checkout the
# runner runs in, with {TARGET} = the installed version.
#
# bash 3.2 compatible; CRLF-tolerant readers; LF writers; temp-then-rename writes. Command
# output is never suppressed.
# -----------------------------------------------------------------------------
if [ -z "${BASH_VERSION:-}" ]; then
  echo "sumela-migrate: run it with bash: bash scripts/sumela-migrate.sh <command>" >&2
  exit 1
fi
set -uo pipefail

PROG="sumela-migrate"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
NOTES_REL="scripts/sumela-migrations"
# The framework's own repository: the upstream when .sumela/upstream.conf names none (update.sh
# uses the same default).
DEFAULT_UPSTREAM="https://github.com/tolgakisaogullari/SumelaOS.git"
TAB="$(printf '\t')"
# Git Bash, MSYS2 or Cygwin: git is a native Windows program there (see native_path).
case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) ON_WINDOWS=true ;; *) ON_WINDOWS=false ;; esac
# A hook's environment would point every git call (and every step) at another layout.
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_PREFIX

say()  { printf '%s\n' "$PROG: $*"; }
warn() { printf '%s\n' "$PROG: $*" >&2; }
die()  { warn "$*"; exit 1; }

usage() {
  cat <<'EOF'
usage: sumela-migrate.sh <command> [arguments] [options]
  plan [--scope repo|developer] [--source <clone> [--trust-origin <url>]]   list the pending steps in order
  set <key>=<value>...                               record confirmed values (prefix, base, branch, worktree)
  show <id>                                          print a step, placeholders substituted
  run <id> [--confirmed-by-user]                     run a step's command from {ROOT}
  verify <id>                                        exit 0 only when verify exits 0 and expect holds
  record <id> done|declined|not-applicable           write the ledger entry (done re-runs verify first)
  rollback <id> --confirmed-by-user                  run a step's rollback line; the step is pending again
  status [--scope repo|developer]                    print pending_repo=<n> pending_developer=<n>
  lint [<notes.md>...]                               check notes files (default: the shipped ones)
options: --confirmed-by-user (run, rollback: the user typed the confirmation),
         --trust-origin <url> (plan --source: the user confirmed a clone of <url>, which is not
         the project's upstream), --allow-untagged (maintainer tests only, with
         SUMELA_MIGRATE_ALLOW_UNTAGGED=1)
exit: 0 ok; 1 error; 2 consent required; 3 verify failed; 4 invalid notes
See scripts/sumela-migrations/README.md.
EOF
}

# --- Arguments ------------------------------------------------------------------------------
CMD="${1:-}"
[ $# -gt 0 ] && shift
SCOPE="" SOURCE="" TRUST_ORIGIN="" CONFIRMED=false ALLOW_UNTAGGED=false
ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --scope)  [ $# -ge 2 ] || { warn "--scope needs repo or developer"; exit 1; }; SCOPE="$2"; shift ;;
    --scope=*) SCOPE="${1#--scope=}" ;;
    --source) [ $# -ge 2 ] || { warn "--source needs a directory"; exit 1; }; SOURCE="$2"; shift ;;
    --source=*) SOURCE="${1#--source=}" ;;
    --trust-origin) [ $# -ge 2 ] || { warn "--trust-origin needs the URL the user confirmed"; exit 1; }; TRUST_ORIGIN="$2"; shift ;;
    --trust-origin=*) TRUST_ORIGIN="${1#--trust-origin=}" ;;
    --confirmed-by-user) CONFIRMED=true ;;
    --allow-untagged) ALLOW_UNTAGGED=true ;;
    -h|--help) usage; exit 0 ;;
    --) shift; while [ $# -gt 0 ]; do ARGS+=("$1"); shift; done; break ;;
    -*) warn "unknown option: $1"; usage >&2; exit 1 ;;
    *) ARGS+=("$1") ;;
  esac
  shift
done
case "$SCOPE" in ''|repo|developer) ;; *) warn "--scope must be repo or developer, not '$SCOPE'"; exit 1 ;; esac
if [ -n "$SOURCE" ] && [ "$CMD" != plan ]; then
  warn "only plan takes --source: the other commands read the release clone that plan --source recorded"; exit 1
fi
if [ -n "$TRUST_ORIGIN" ] && { [ "$CMD" != plan ] || [ -z "$SOURCE" ]; }; then
  warn "--trust-origin goes with plan --source <clone>: it names the clone's origin the user confirmed"; exit 1
fi
if [ "$ALLOW_UNTAGGED" = true ] && [ -z "${SUMELA_MIGRATE_ALLOW_UNTAGGED:-}" ]; then
  warn "--allow-untagged is for maintainer tests only: it also takes SUMELA_MIGRATE_ALLOW_UNTAGGED=1 in the environment"; exit 1
fi
NARGS=${#ARGS[@]}
arg() { if [ "$1" -lt "$NARGS" ]; then printf '%s' "${ARGS[$1]}"; fi; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/sumela-migrate.XXXXXX")" || die "cannot create a temporary directory"
trap 'rm -rf "$WORK"' EXIT
TABLE="$WORK/table.tsv"; : > "$TABLE"

# --- Shared awk functions (the lint, the selection and the read-only gate use them) --------------
AWK_LIB='
function vkey(v,   a) { sub(/-rc\.[0-9]+$/, "", v); split(v, a, "."); return sprintf("%06d.%06d.%06d", a[1] + 0, a[2] + 0, a[3] + 0) }
function base(f,   b) { b = f; sub(/.*\//, "", b); return b }
function dirof(f,   d) { d = f; if (d !~ /\//) return "."; sub(/\/[^\/]*$/, "", d); return d }
# words(s, t): the words of a command line made of plain characters only, in t[1..n]; -1 for
# anything else. A word is a run of [A-Za-z0-9_./:=@%+-] that does not start with @ (PowerShell
# splats @name), or one whole double-quoted string of those characters, spaces and commas (a
# quote never sits inside a word; no empty string). Words are separated by spaces. {SRC},
# {ROOT} and {TARGET} may sit in either. Refused, so bash and PowerShell split the line alike:
# a tab, # (a comment in bash), $, a backtick, ; & | < > ( ) { } outside a placeholder, a single
# quote, a backslash, * ? [ ] ~ !, a comma outside a string (an array in PowerShell), and every
# character outside ASCII (PowerShell reads curly quotes as quotes and en dashes as dashes).
function words(s, t,   n, i, L, c, w, st, pl) {
  n = 0; w = ""; st = 0; L = length(s); i = 1     # st: 0 between words, 1 in a word, 2 in a string, 3 just after one
  while (i <= L) {
    c = substr(s, i, 1)
    if (c == " ") {
      if (st == 2) w = w c
      else { if (st != 0) { t[++n] = w; w = "" }; st = 0 }
      i++; continue
    }
    if (st == 3) return -1
    if (c == "\"") {
      if (st == 0) st = 2
      else if (st == 2) { if (w == "") return -1; st = 3 }
      else return -1
      i++; continue
    }
    if (c == "{") {
      pl = 0
      if (substr(s, i, 5) == "{SRC}") pl = 5
      else if (substr(s, i, 6) == "{ROOT}") pl = 6
      else if (substr(s, i, 8) == "{TARGET}") pl = 8
      if (pl == 0) return -1
      w = w substr(s, i, pl); i += pl
      if (st == 0) st = 1
      continue
    }
    if (index("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_./:=@%+-", c) == 0 && !(st == 2 && c == ",")) return -1
    if (st == 0 && c == "@") return -1
    w = w c; i++
    if (st == 0) st = 1
  }
  if (st == 2) return -1
  if (st != 0) t[++n] = w
  return n
}
function is_script(w, ext) { return w !~ /^-/ && w ~ ("^([{](SRC|ROOT)[}]/)?([A-Za-z0-9_.-]+/)*[A-Za-z0-9_.-]+[.]" ext "$") }
function ro_mode(w) { return (w == "--plan" || w == "--plan-check" || w == "--status" || w == "--check" || w == "--verify-applied") }
# git [-C <dir>] config [--local|--global|--worktree] --get <key>, and nothing else
function git_get(t, n, from,   i) {
  i = from
  if (i <= n && t[i] == "-C") { if (i + 1 > n || t[i + 1] ~ /^-/) return 0; i += 2 }
  if (i > n || t[i] != "config") return 0
  i++
  if (i <= n && (t[i] == "--local" || t[i] == "--global" || t[i] == "--worktree")) i++
  if (i > n || t[i] != "--get") return 0
  return (i + 1 == n && t[n] ~ /^[A-Za-z0-9._-]+$/)
}
# A read-only bash line [RU-M10]: bash <script.sh> [--source <dir>] with exactly one of --plan,
# --plan-check, --status, --check, --verify-applied or --has-baseline <name>; bash
# <path>/validate-structure.sh with no argument; or git config ... --get <key>.
function readonly_cmd(s,   t, n, i, sc) {
  n = words(s, t); if (n < 1) return 0
  if (t[1] == "git") return git_get(t, n, 2)
  if (t[1] != "bash" || n < 2 || !is_script(t[2], "sh")) return 0
  sc = base(t[2])
  if (sc == "validate-structure.sh") return (n == 2)
  i = 3
  if (i <= n && t[i] == "--source") { if (i + 1 > n || t[i + 1] ~ /^-/) return 0; i += 2 }
  if (i > n) return 0
  if (ro_mode(t[i])) return (i == n)
  if (t[i] == "--has-baseline") return (i + 1 == n && t[n] ~ /^[A-Za-z0-9._-]+$/)
  return 0
}
# The PowerShell twin of that shape: powershell|pwsh [-NoProfile] [-NonInteractive] -File
# <script.ps1> [-SourceDir|-Source <dir>] with exactly one of -Plan, -PlanCheck, -Status, -Check,
# -VerifyApplied, -HasBaseline <name> (or their --forms); or git config ... --get <key>.
function readonly_ps(s,   t, n, i, l) {
  n = words(s, t); if (n < 1) return 0
  l = tolower(t[1])
  if (l == "git") return git_get(t, n, 2)
  if (l != "powershell" && l != "pwsh") return 0
  i = 2
  while (i <= n && (tolower(t[i]) == "-noprofile" || tolower(t[i]) == "-noninteractive")) i++
  if (i > n || tolower(t[i]) != "-file") return 0
  i++
  if (i > n || !is_script(t[i], "ps1")) return 0
  i++
  l = tolower(t[i])
  if (i <= n && (l == "-sourcedir" || l == "-source" || t[i] == "--source")) { if (i + 1 > n || t[i + 1] ~ /^-/) return 0; i += 2 }
  if (i > n) return 0
  l = tolower(t[i])
  if (l == "-plan" || l == "-plancheck" || l == "-status" || l == "-check" || l == "-verifyapplied" || ro_mode(t[i])) return (i == n)
  if (l == "-hasbaseline" || t[i] == "--has-baseline") return (i + 1 == n && t[n] ~ /^[A-Za-z0-9._-]+$/)
  return 0
}
# Every {SRC} and {ROOT} sits inside double quotes, in the quoting context it is written in:
# backslash escapes in bash lines, backtick escapes in PowerShell lines (isps); nothing expands
# inside single quotes; $( ... ) opens a new context. An escaped placeholder never expands.
function dq_ok(s, isps,   i, n, c, st, sp, stk) {
  st = 0; n = length(s); sp = 0
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (st == 2) {
      if (c == "\047") st = 0
      else if (substr(s, i, 5) == "{SRC}" || substr(s, i, 6) == "{ROOT}") return 0
      continue
    }
    if ((!isps && c == "\\") || (isps && c == "`")) {
      if (substr(s, i + 1, 5) == "{SRC}" || substr(s, i + 1, 6) == "{ROOT}") return 0
      i++; continue
    }
    if (c == "$" && substr(s, i + 1, 1) == "(") { stk[++sp] = st; st = 0; i++; continue }
    if (c == ")" && st == 0 && sp > 0) { st = stk[sp--]; continue }
    if (c == "\"") { if (isps && st == 1 && substr(s, i + 1, 1) == "\"") { i++; continue }; st = (st == 1) ? 0 : 1; continue }
    if (st == 0 && c == "\047") { st = 2; continue }
    if (substr(s, i, 5) == "{SRC}" || substr(s, i, 6) == "{ROOT}") { if (st != 1) return 0 }
  }
  return 1
}
'

# --- Notes: parse, check, load ---------------------------------------------------------------
# parse_notes <file>... -> rows, file order:
#   B<TAB>file<TAB>line<TAB>block              a ```sumela-step fence
#   S<TAB>file<TAB>line<TAB>block<TAB>key<TAB>value
#   E<TAB>file<TAB>line<TAB>message            a malformed line
parse_notes() {
  LC_ALL=C awk '
    FNR == 1 { if (inb) print "E\t" pf "\t" bs "\tunterminated sumela-step block (no closing fence)"; inb = 0; pf = FILENAME }
    { l = $0; sub(/\r$/, "", l) }
    !inb && l ~ /^```sumela-step[ \t]*$/ { inb = 1; blk++; bs = FNR; print "B\t" FILENAME "\t" FNR "\t" blk; next }
    inb && l ~ /^```[ \t]*$/ { inb = 0; next }
    inb && l ~ /^[ \t]*(#|$)/ { next }
    inb {
      p = index(l, ":")
      if (p == 0) { print "E\t" FILENAME "\t" FNR "\tnot a key: value line: " l; next }
      key = substr(l, 1, p - 1); val = substr(l, p + 1); sub(/^[ \t]+/, "", val); sub(/[ \t]+$/, "", val)
      if (key == "" || key ~ /[ \t]/) { print "E\t" FILENAME "\t" FNR "\tnot a key: value line: " l; next }
      if (index(val, "\t")) { print "E\t" FILENAME "\t" FNR "\ta value holds a tab character (key " key ")"; next }
      print "S\t" FILENAME "\t" FNR "\t" blk "\t" key "\t" val
    }
    END { if (inb) print "E\t" pf "\t" bs "\tunterminated sumela-step block (no closing fence)" }' "$@"
}

# check_rows <report-list-file> < rows -> "D<TAB>file<TAB>line<TAB>message" defects for the files
# the list names, and "M<TAB>file<TAB>line<TAB>pattern" for each match: pattern to compile.
check_rows() {
  MIG_REPORT="$1" LC_ALL=C awk "$AWK_LIB"'
    function defect(f, l, m) { if (f in report) print "D\t" f "\t" l "\t" m }
    function ph(s, f, l, k, iscmd, isdev,   rest, name, pre) {
      rest = s
      while (match(rest, /\{[A-Za-z_][A-Za-z0-9_]*\}/)) {
        name = substr(rest, RSTART + 1, RLENGTH - 2)
        pre = (RSTART > 1) ? substr(rest, RSTART - 1, 1) : ""
        rest = substr(rest, RSTART + RLENGTH)
        if (pre == "$") continue
        if (name != "SRC" && name != "ROOT" && name != "TARGET") { defect(f, l, "unknown placeholder {" name "} in " k " (only {SRC}, {ROOT} and {TARGET})"); continue }
        if (isdev && name == "SRC") defect(f, l, "a developer step cannot use {SRC}: a teammate has no release clone")
        if (k == "expect" && name != "TARGET") defect(f, l, "expect cannot use {" name "}")
      }
      if (iscmd && !dq_ok(s, k ~ /\.ps1$/)) defect(f, l, "{SRC} and {ROOT} must sit inside double quotes in " k)
    }
    BEGIN {
      FS = "\t"
      RO_SH = "bash <script.sh> [--source <dir>] with one of --plan, --plan-check, --status, --check, --verify-applied or --has-baseline <name>; bash <path>/validate-structure.sh; or git [-C <dir>] config [--local] --get <key>, in plain words and whole double-quoted strings of [A-Za-z0-9_./:=@%+-]"
      RO_PS = "powershell -NoProfile -File <script.ps1> [-SourceDir <dir>] with one of -Plan, -PlanCheck, -Status, -Check, -VerifyApplied or -HasBaseline <name>; or git [-C <dir>] config [--local] --get <key>, in plain words and whole double-quoted strings of [A-Za-z0-9_./:=@%+-]"
      known = " id title scope when requires consent run run.ps1 verify verify.ps1 expect rollback rollback.ps1 agent ledger until "
      nreq = split("id title scope when consent run verify expect", reqk, " ")
      while ((getline line < ENVIRON["MIG_REPORT"]) > 0) report[line] = 1
    }
    $1 == "E" { defect($2, $3, $4); next }
    $1 == "B" { b = $4; nb++; order[nb] = b; bf[b] = $2; bl[b] = $3; next }
    $1 == "S" {
      b = $4; k = $5; v = $6
      if (index(known, " " k " ") == 0) { defect($2, $3, "unknown key " k); next }
      if ((b, k) in val) { defect($2, $3, "duplicate key " k " in one step"); next }
      if (v == "") { defect($2, $3, "empty value for " k); next }
      val[b, k] = v; kl[b, k] = $3; keys[b] = keys[b] " " k
      next
    }
    END {
      for (i = 1; i <= nb; i++) {        # pass 1: ids, per directory
        b = order[i]; f = bf[b]; d = dirof(f); id = ((b, "id") in val) ? val[b, "id"] : ""
        if (id == "") continue
        if ((d, id) in owner) { defect(f, kl[b, "id"], "duplicate id " id " (also in " bf[owner[d, id]] ":" bl[owner[d, id]] ")"); dup[b] = 1; continue }
        owner[d, id] = b
      }
      for (i = 1; i <= nb; i++) {        # pass 2: each step
        b = order[i]; f = bf[b]; d = dirof(f); bn = base(f); l = bl[b]
        generic = (bn == "upgrade.md"); fver = bn; sub(/\.md$/, "", fver)
        id = ((b, "id") in val) ? val[b, "id"] : ""
        if (id == "") { defect(f, l, "a step without an id"); continue }
        if (dup[b]) continue
        for (j = 1; j <= nreq; j++) if (!((b, reqk[j]) in val)) defect(f, l, "step " id ": missing " reqk[j] (reqk[j] == "verify" && val[b, "run"] == "-" ? " (a run: - step must name its verify)" : ""))
        if (generic) { if (id !~ /^upgrade-[0-9][0-9]$/) defect(f, kl[b, "id"], "id " id " must be upgrade-<NN> in upgrade.md") }
        else if (substr(id, 1, length(fver) + 1) != fver "-" || substr(id, length(fver) + 2) !~ /^[0-9][0-9]$/) defect(f, kl[b, "id"], "id " id " must be " fver "-<NN> in " bn)
        sc = val[b, "scope"]; wh = val[b, "when"]; co = val[b, "consent"]; r = val[b, "run"]
        if ((b, "scope") in val && sc != "repo" && sc != "developer") defect(f, kl[b, "scope"], "scope must be repo or developer, not " sc)
        if (generic && (b, "scope") in val && sc != "repo") defect(f, kl[b, "scope"], "upgrade.md holds repo steps only")
        if ((b, "when") in val && wh !~ /^(pre-update|update|post-update|finalize|first-session|quiet-window)$/) defect(f, kl[b, "when"], "when must be pre-update, update, post-update, finalize, first-session or quiet-window, not " wh)
        if ((b, "consent") in val && co !~ /^(none|confirm|explicit)$/) defect(f, kl[b, "consent"], "consent must be none, confirm or explicit, not " co)
        if ((b, "ledger") in val && val[b, "ledger"] != "none") defect(f, kl[b, "ledger"], "ledger takes only none (leave it out for a ledger entry)")
        if ((b, "until") in val) {
          u = val[b, "until"]
          if (u !~ /^[0-9]+\.[0-9]+\.[0-9]+$/) defect(f, kl[b, "until"], "until must be a version X.Y.Z, not " u)
          else if (!generic && vkey(u) <= vkey(fver)) defect(f, kl[b, "until"], "until " u " is not above " fver ": the step would never be selected")
        }
        if ((b, "expect") in val) {
          e = val[b, "expect"]
          if (e == "exit0" || e == "non-empty" || e == "empty" || e ~ /^equals:/) ;
          else if (e ~ /^match:./) {
            p = substr(e, 7)
            if (p ~ /\[\[:/ || p ~ /\\[A-Za-z0-9]/) defect(f, kl[b, "expect"], "match: uses a POSIX class or a backslash escape; keep to the subset both runners read alike")
            else print "M\t" f "\t" kl[b, "expect"] "\t" p
          } else defect(f, kl[b, "expect"], "expect must be exit0, non-empty, empty, equals:<s> or match:<ERE>, not " e)
        }
        if ((b, "run") in val) {
          if (r != "-" && !((b, "run.ps1") in val) && r !~ /^bash[ \t]/) defect(f, kl[b, "run"], "step " id ": a runnable step needs run.ps1, or a run line that starts with bash (the PowerShell runner sends it to Git Bash)")
          if (r == "-" && !((b, "agent") in val)) defect(f, l, "step " id ": a run: - step needs an agent: instruction")
        }
        # consent: none runs without asking, and so does its verify: every command line it has
        # must be one of the read-only shapes.
        if ((b, "consent") in val && co == "none") {
          if ((b, "run") in val && r != "-" && !readonly_cmd(r)) defect(f, kl[b, "consent"], "step " id ": consent: none needs run: - or a read-only run: " RO_SH)
          if ((b, "run.ps1") in val && !readonly_ps(val[b, "run.ps1"])) defect(f, kl[b, "run.ps1"], "step " id ": consent: none needs a read-only run.ps1 too: " RO_PS)
          if ((b, "verify") in val && !readonly_cmd(val[b, "verify"])) defect(f, kl[b, "verify"], "step " id ": consent: none needs a read-only verify too (it runs without asking): " RO_SH)
          if ((b, "verify.ps1") in val && !readonly_ps(val[b, "verify.ps1"])) defect(f, kl[b, "verify.ps1"], "step " id ": consent: none needs a read-only verify.ps1 too: " RO_PS)
        }
        n = split(substr(keys[b], 2), ks, " ")
        for (j = 1; j <= n; j++) {
          k = ks[j]
          ph(val[b, k], f, kl[b, k], k, k ~ /^(run|verify|rollback)(\.ps1)?$/, sc == "developer")
        }
        if ((b, "requires") in val) {
          m = split(val[b, "requires"], rq, /[ ,]+/)
          for (j = 1; j <= m; j++) {
            q = rq[j]; if (q == "") continue
            if (q == id) { defect(f, kl[b, "requires"], "step " id " requires itself"); continue }
            if (!((d, q) in owner)) { defect(f, kl[b, "requires"], "step " id " requires " q ", which no notes file in " d " defines"); continue }
            if (val[owner[d, q], "scope"] != sc) { defect(f, kl[b, "requires"], "step " id " (" sc ") requires " q " (" val[owner[d, q], "scope"] "): requires stays within one scope"); continue }
            edge[b] = edge[b] " " owner[d, q]
          }
        }
        if (!generic && sc == "repo" && wh == "pre-update" && (" " val[b, "requires"] " ") !~ /[ ,]upgrade-01[ ,]/) defect(f, l, "step " id ": a pre-update repo step needs requires: upgrade-01 (repo steps run in the upgrade worktree it creates)")
      }
      # requires cycles (Kahn): whatever cannot be ordered sits on a cycle
      for (i = 1; i <= nb; i++) { b = order[i]; if (!((b, "id") in val) || dup[b]) continue; live[b] = 1; nl++
        m = split(substr(edge[b], 2), es, " "); indeg[b] = m }
      changed = 1
      while (changed) {
        changed = 0
        for (b in live) if (!placed[b] && indeg[b] == 0) {
          placed[b] = 1; changed = 1
          for (c in live) if (!placed[c]) { m = split(substr(edge[c], 2), es, " "); for (j = 1; j <= m; j++) if (es[j] == b) indeg[c]-- }
        }
      }
      for (b in live) if (!placed[b]) defect(bf[b], bl[b], "step " val[b, "id"] ": requires forms a cycle")
    }'
}

# lint_files <report-files...>: prints defects as file:line: message; returns 4 on any defect.
# Every notes file beside a reported one is read too, so requires resolves across the directory
# (LINT_SCAN_DIR=false: only the files given, as the runner loads exactly the committed ones).
LINT_SCAN_DIR=true
lint_files() {
  local f bn rep="$WORK/report.list" ctx="$WORK/context.list" defects="$WORK/defects" d p n=0
  : > "$rep"; : > "$ctx"; : > "$defects"
  for f in "$@"; do
    case "$f" in */*) ;; *) f="./$f" ;; esac       # the same spelling the directory scan produces
    bn="${f##*/}"
    case "$bn" in
      README.md) say "$f: documentation, not notes (skipped)"; continue ;;
      upgrade.md) ;;
      *.md) if ! printf '%s' "${bn%.md}" | LC_ALL=C grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
              printf '%s:1: not a notes file name (upgrade.md or <X.Y.Z>.md)\n' "$f" >> "$defects"; continue; fi ;;
      *) printf '%s:1: not a notes file name (upgrade.md or <X.Y.Z>.md)\n' "$f" >> "$defects"; continue ;;
    esac
    [ -f "$f" ] && [ -r "$f" ] || { printf '%s:1: cannot read the file\n' "$f" >> "$defects"; continue; }
    printf '%s\n' "$f" >> "$rep"
    d="$(dirname "$f")"
    [ "$LINT_SCAN_DIR" = true ] && for p in "$d"/upgrade.md "$d"/*.md; do
      [ -f "$p" ] || continue
      case "${p##*/}" in upgrade.md) ;; *) printf '%s' "${p##*/}" | LC_ALL=C grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.md$' || continue ;; esac
      p="$d/${p##*/}"
      LC_ALL=C grep -qxF -- "$p" "$ctx" || printf '%s\n' "$p" >> "$ctx"
    done
    LC_ALL=C grep -qxF -- "$f" "$ctx" || printf '%s\n' "$f" >> "$ctx"
  done
  if [ -s "$ctx" ]; then
    local -a files=()
    while IFS= read -r p; do files+=("$p"); done < "$ctx"
    parse_notes "${files[@]}" > "$WORK/rows.tsv"
    check_rows "$rep" < "$WORK/rows.tsv" > "$WORK/checks.tsv"
    while IFS="$TAB" read -r kind f l m; do
      case "$kind" in
        D) printf '%s:%s: %s\n' "$f" "$l" "$m" >> "$defects" ;;
        M) p="$(replace_all "$m" "{TARGET}" '0\.0\.0')"
           printf '' | LC_ALL=C grep -E -- "$p" >/dev/null 2>&1
           [ $? -eq 2 ] && printf '%s:%s: match: %s is not a valid extended regular expression\n' "$f" "$l" "$m" >> "$defects" ;;
      esac
    done < "$WORK/checks.tsv"
  fi
  if [ -s "$defects" ]; then cat "$defects"; return 4; fi
  while IFS= read -r f; do
    n="$(LC_ALL=C awk -F'\t' -v f="$f" '$1 == "B" && $2 == f { c++ } END { print c + 0 }' "$WORK/rows.tsv")"
    if [ "$n" = 1 ]; then say "$f: ok (1 step)"; else say "$f: ok ($n steps)"; fi
  done < "$rep"
  return 0
}

# notes_files <dir> -> "<mode><TAB><blob><TAB><path>" for each notes file committed at the HEAD
# of <dir> (upgrade.md and <X.Y.Z>.md, path relative to <dir>)
notes_files() {
  cgit -C "$1" -c core.quotePath=false ls-tree -r HEAD -- "$NOTES_REL/" 2>/dev/null | tr -d '\r' |
    LC_ALL=C awk -v rel="$NOTES_REL" '{ t = index($0, "\t"); if (t == 0) next; split(substr($0, 1, t - 1), m, " "); p = substr($0, t + 1)
      if (p !~ ("^" rel "/(upgrade|[0-9]+[.][0-9]+[.][0-9]+)[.]md$")) next
      print m[1] "\t" m[3] "\t" p }'
}
map_paths() {  # <from> <to> < text: every <from> becomes <to> (literal strings)
  MIG_FROM="$1" MIG_TO="$2" LC_ALL=C awk '{ f = ENVIRON["MIG_FROM"]; t = ENVIRON["MIG_TO"]; s = $0; out = ""
    while ((i = index(s, f)) > 0) { out = out substr(s, 1, i - 1) t; s = substr(s, i + length(f)) }
    print out s }'
}

# load_set <set: repo|dev> <dir>: validates the notes committed at the HEAD of <dir>, read from
# their blobs (never the working tree), and appends that set's steps (repo: scope repo; dev:
# scope developer) to $TABLE. Returns 0 loaded, 1 the notes differ from HEAD (developer notes)
# or cannot be read, 4 invalid notes (messages on stderr). Rows:
#   M<TAB>set<TAB>id<TAB>origin(generic|version)<TAB>version<TAB>file<TAB>line
#   K<TAB>set<TAB>id<TAB>key<TAB>value
load_set() {
  local set="$1" dir="$2" rel mode blob want rc tmpd shown
  local -a files=()
  tmpd="$WORK/notes-$set"; rm -rf "$tmpd"; mkdir -p "$tmpd" || return 1
  shown="$dir/$NOTES_REL"
  while IFS="$TAB" read -r mode blob rel; do
    [ -n "$rel" ] || continue
    # Only regular files: a committed symlink would point outside HEAD.
    case "$mode" in
      100644|100755) ;;
      *) warn "$rel at the HEAD of $dir is not a regular file (mode $mode: a symlink?): refusing to read steps from it"; return 1 ;;
    esac
    cgit -C "$dir" cat-file blob "$blob" > "$tmpd/${rel##*/}" || { warn "cannot read $rel at the HEAD of $dir"; return 1; }
    files+=("$tmpd/${rel##*/}")
  done <<EOF
$(notes_files "$dir")
EOF
  [ ${#files[@]} -gt 0 ] || return 0
  if [ "$set" = dev ] && ! cgit -C "$dir" diff --quiet --no-ext-diff --no-textconv HEAD -- "$NOTES_REL/"; then
    warn "the notes in $shown/ differ from HEAD: refusing to read steps from them"
    warn "  (restore them with: git -C \"$dir\" checkout HEAD -- $NOTES_REL/)"
    return 1
  fi
  LINT_SCAN_DIR=false lint_files "${files[@]}" > "$WORK/lint.out"; rc=$?
  if [ "$rc" -ne 0 ]; then
    map_paths "$tmpd" "$shown" < "$WORK/lint.out" >&2
    warn "invalid migration notes in $shown/ (at HEAD): nothing runs from them"
    return 4
  fi
  want=developer; [ "$set" = repo ] && want=repo
  parse_notes "${files[@]}" | LC_ALL=C awk -v set="$set" -v want="$want" "$AWK_LIB"'
    BEGIN { FS = "\t" }
    $1 == "B" { b = $4; nb++; order[nb] = b; bf[b] = $2; bl[b] = $3; next }
    $1 == "S" { b = $4; n[b]++; k[b, n[b]] = $5; v[b, n[b]] = $6; if ($5 == "id") id[b] = $6; if ($5 == "scope") sc[b] = $6; next }
    END {
      for (i = 1; i <= nb; i++) {
        b = order[i]; if (sc[b] != want) continue
        bn = base(bf[b]); origin = (bn == "upgrade.md") ? "generic" : "version"; ver = bn; sub(/\.md$/, "", ver)
        if (origin == "generic") ver = ""
        print "M\t" set "\t" id[b] "\t" origin "\t" ver "\t" bf[b] "\t" bl[b]
        for (j = 1; j <= n[b]; j++) print "K\t" set "\t" id[b] "\t" k[b, j] "\t" v[b, j]
      }
    }' | map_paths "$tmpd" "$shown" >> "$TABLE"
  return 0
}

field() {  # <id> <key> -> the value, empty when absent
  LC_ALL=C awk -F'\t' -v id="$1" -v k="$2" '$1 == "K" && $3 == id && $4 == k { print $5; exit }' "$TABLE"
}
meta() {  # <id> <column: set|origin|version|file|line> -> the value; exit 1 when the id is unknown
  LC_ALL=C awk -F'\t' -v id="$1" -v c="$2" '
    BEGIN { col["set"] = 2; col["origin"] = 4; col["version"] = 5; col["file"] = 6; col["line"] = 7 }
    $1 == "M" && $3 == id { print $(col[c]); f = 1; exit } END { exit !f }' "$TABLE"
}

# --- Small helpers ---------------------------------------------------------------------------
has_ctrl() {  # <string>: 0 when it holds a control character (a newline or a tab included)
  case "$1" in *$'\n'*) return 0 ;; esac
  printf '%s' "$1" | LC_ALL=C grep -q '[[:cntrl:]]'
}
# cgit: git on the release clone, whose own configuration is not trusted: no fsmonitor hook runs,
# no untracked cache is believed and the stat cache is checked in full (an edit that keeps the
# size and the mtime still shows). Notes blobs are read with cat-file, which runs no filter.
cgit() { git -c core.fsmonitor=false -c core.untrackedCache=false -c core.checkStat=default -c core.trustctime=true -c core.ignoreStat=false "$@"; }
replace_all() {  # <string> <literal needle> <literal replacement>: no pattern or & semantics
  local s="$1" n="$2" r="$3" out=""
  while :; do
    case "$s" in
      *"$n"*) out="$out${s%%"$n"*}$r"; s="${s#*"$n"}" ;;
      *) break ;;
    esac
  done
  printf '%s' "$out$s"
}
subst_cmd() {  # a command value: {SRC} and {ROOT} become environment references, {TARGET} a literal
  local s
  s="$(replace_all "$1" "{SRC}" '${SUMELA_MIGRATE_SRC}')"
  s="$(replace_all "$s" "{ROOT}" '${SUMELA_MIGRATE_ROOT}')"
  replace_all "$s" "{TARGET}" "$STEP_TARGET"
}
subst_ps() {  # a PowerShell command value, as the PowerShell runner runs it
  local s
  s="$(replace_all "$1" "{SRC}" '${env:SUMELA_MIGRATE_SRC}')"
  s="$(replace_all "$s" "{ROOT}" '${env:SUMELA_MIGRATE_ROOT}')"
  replace_all "$s" "{TARGET}" "$STEP_TARGET"
}
subst_expect() {  # an expect value: inside match:, {TARGET} is matched literally (its dots escaped)
  case "$1" in
    match:*) replace_all "$1" "{TARGET}" "$(replace_all "$STEP_TARGET" "." '\.')" ;;
    *) replace_all "$1" "{TARGET}" "$STEP_TARGET" ;;
  esac
}
subst_text() {  # a display value (title, agent): literal paths, for the reader
  local s
  s="$(replace_all "$1" "{SRC}" "$STEP_SRC")"
  s="$(replace_all "$s" "{ROOT}" "$STEP_ROOT")"
  replace_all "$s" "{TARGET}" "$STEP_TARGET"
}
valid_version() { printf '%s' "$1" | LC_ALL=C grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$'; }
vcmp() {  # <a> <b> -> -1, 0 or 1 (an -rc.N suffix is ignored: an RC selects its release's notes)
  LC_ALL=C awk -v a="$1" -v b="$2" "$AWK_LIB"'BEGIN { x = vkey(a); y = vkey(b); print (x < y) ? -1 : ((x > y) ? 1 : 0) }'
}
read_version() {  # <install root> -> its .sumela/VERSION, trimmed
  [ -f "$1/.sumela/VERSION" ] || return 1
  tr -d ' \t\r\n' < "$1/.sumela/VERSION"
}
join_root() { if [ -n "$2" ]; then printf '%s/%s' "${1%/}" "$2"; else printf '%s' "$1"; fi; }
# native_path <path>: on Windows, an absolute POSIX path in the form a native program reads,
# C:/x: cygpath -m when it exists (it knows the mount table: /tmp, /usr, the cygdrive prefix),
# else /x/rest maps to X:/rest. Any other path (C:/x, a relative one), and every path elsewhere,
# is returned as it is. Git Bash converts a POSIX path argument for a native program such as
# git, but not one that holds ' ` * ? [ or ]: git then receives /c/... and cannot open it. So
# every path the runner hands git, records (both twins read the state) or hands a step is native
# on Windows, the form git itself prints.
native_path() {
  local p="$1" d
  if [ "$ON_WINDOWS" != true ]; then printf '%s' "$p"; return 0; fi
  case "$p" in /*) ;; *) printf '%s' "$p"; return 0 ;; esac
  if command -v cygpath >/dev/null 2>&1 && d="$(cygpath -m "$p")" && [ -n "$d" ]; then printf '%s' "$d"; return 0; fi
  case "$p" in
    /[A-Za-z]|/[A-Za-z]/*) d="$(printf '%s' "${p:1:1}" | LC_ALL=C tr 'a-z' 'A-Z')"; p="${p:2}"; printf '%s:%s' "$d" "${p:-/}" ;;
    *) printf '%s' "$p" ;;
  esac
}
utc_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
# strip_userinfo <url>: never store or print a credential. http(s) URLs lose their whole
# userinfo (it is often a token); other scheme URLs keep the user name and lose the password.
strip_userinfo() {
  printf '%s' "$1" | LC_ALL=C awk '{ u = $0
    if (match(u, /^[A-Za-z][A-Za-z0-9+.-]*:\/\//)) {
      s = substr(u, 1, RLENGTH); r = substr(u, RLENGTH + 1); a = r; sub(/\/.*/, "", a); rest = substr(r, length(a) + 1)
      if (index(a, "@")) {
        ui = a; sub(/@[^@]*$/, "", ui); h = a; sub(/^.*@/, "", h)
        if (tolower(s) ~ /^https?:/) a = h; else { sub(/:.*/, "", ui); a = ui "@" h }
      }
      u = s a rest
    }
    print u }'
}
# local_url_path <url>: exit 0 with the path of a URL that names a local repository (a plain
# path, or a file:// URL, where file:///C:/x gives C:/x), backslashes as slashes; exit 1 for a
# remote URL (another scheme, or an scp-style host:path).
local_url_path() {
  printf '%s' "$1" | LC_ALL=C awk '{ u = $0
    if (match(u, /^[A-Za-z][A-Za-z0-9+.-]*:\/\//)) {
      if (tolower(substr(u, 1, RLENGTH)) != "file://") exit 1
      u = substr(u, RLENGTH + 1)
      if (u ~ /^\/[A-Za-z]:([\/\\]|$)/) u = substr(u, 2)
    } else if (u ~ /^[^\/]+:/ && u !~ /^[A-Za-z]:/) exit 1
    gsub(/\\/, "/", u)
    printf "%s", u }'
}
# url_key <url>: a comparable form of a repository URL: no scheme, no user, the host in lower
# case, an scp-style host:path as host/path, no trailing slash or .git. On Windows a local path
# is compared in its native form, the one git for Windows records as a clone's origin: /c/x,
# c:\x, C:/x, file:///c/x and file:///C:/x are all C:/x (native_path; the drive letter in upper
# case). Nothing else is folded: any other difference still refuses.
url_key() {
  local u="$1" p
  if [ "$ON_WINDOWS" = true ] && p="$(local_url_path "$u")"; then
    u="$(native_path "$p")"
    case "$u" in [abcdefghijklmnopqrstuvwxyz]:*) u="$(printf '%s' "${u%%:*}" | LC_ALL=C tr 'a-z' 'A-Z'):${u#*:}" ;; esac
  fi
  printf '%s' "$u" | LC_ALL=C awk '{ u = $0
    if (match(u, /^[A-Za-z][A-Za-z0-9+.-]*:\/\//)) { u = substr(u, RLENGTH + 1); a = u; sub(/\/.*/, "", a); rest = substr(u, length(a) + 1); sub(/^.*@/, "", a); u = tolower(a) rest }
    else if (u ~ /^[^\/]+:/ && u !~ /^[A-Za-z]:/) { a = u; sub(/:.*/, "", a); rest = substr(u, length(a) + 2); sub(/^.*@/, "", a); u = tolower(a) "/" rest }
    sub(/\/+$/, "", u); sub(/\.git$/, "", u); sub(/\/+$/, "", u)
    print u }'
}
upstream_url() {  # this project's upstream: .sumela/upstream.conf's first line, else the default
  local f="$LOCAL_ROOT/.sumela/upstream.conf" u=""
  # Only the ends are trimmed: a local path may hold spaces (a URL holds none).
  if [ -f "$f" ]; then u="$(LC_ALL=C grep -vE '^[[:space:]]*(#|$)' "$f" | head -1 | tr -d '\r' | LC_ALL=C sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"; fi
  printf '%s' "${u:-$DEFAULT_UPSTREAM}"
}

# --- Where things are --------------------------------------------------------------------------
find_install_root() {
  local d="$PWD" p
  while [ ! -d "$d/.sumela" ]; do p="$(dirname "$d")"; [ "$p" = "$d" ] && return 1; d="$p"; done
  printf '%s\n' "$d"
}
locate() {  # sets LOCAL_ROOT, PREFIX, MAIN_ROOT, STATE_FILE, COMMON
  local top bare
  LOCAL_ROOT="$(find_install_root)" || die "no .sumela/ above $PWD: run this inside a SumelaOS project's checkout"
  LOCAL_ROOT="$(native_path "$LOCAL_ROOT")"
  # git's own message (not redirected) says why it failed; the probe tells a directory git cannot
  # enter from a repository it does not find or refuses.
  if ! COMMON="$(git -C "$LOCAL_ROOT" rev-parse --path-format=absolute --git-common-dir)"; then
    git -C "$LOCAL_ROOT" version >/dev/null 2>&1 ||
      die "git cannot enter $LOCAL_ROOT (git's message is above): the directory is missing, unreadable, or named in a form git cannot open"
    die "$LOCAL_ROOT is not inside a git work tree, or git refuses the repository there (git's message is above)"
  fi
  COMMON="${COMMON%$'\r'}"
  # git before 2.31 does not fail on --path-format: it prints the option back, then a relative path.
  case "$COMMON" in
    *$'\n'*|'') die "git 2.31 or later is required: git rev-parse --path-format=absolute printed '$(printf '%s' "$COMMON" | head -1 | tr -d '\r')' ($(git version 2>&1 | tr -d '\r'))" ;;
    /*|[A-Za-z]:/*) ;;
    *) die "git 2.31 or later is required: git rev-parse --path-format=absolute printed '$COMMON' ($(git version 2>&1 | tr -d '\r'))" ;;
  esac
  PREFIX="$(git -C "$LOCAL_ROOT" rev-parse --show-prefix)" || die "git cannot read $LOCAL_ROOT"
  PREFIX="${PREFIX%$'\r'}"; PREFIX="${PREFIX%/}"
  top="$(git -C "$LOCAL_ROOT" worktree list --porcelain | LC_ALL=C awk '{ sub(/\r$/, "") } NR == 1 && /^worktree / { print substr($0, 10) } NR > 1 && /^$/ { exit } /^bare$/ { print "BARE" }')"
  bare="$(printf '%s\n' "$top" | sed -n '2p')"; top="$(printf '%s\n' "$top" | sed -n '1p')"
  MAIN_ROOT="$LOCAL_ROOT"
  if [ -n "$top" ] && [ "$bare" != BARE ] && [ -d "$(join_root "$top" "$PREFIX")/.sumela" ]; then MAIN_ROOT="$(join_root "$top" "$PREFIX")"; fi
  STATE_FILE="$MAIN_ROOT/.sumela/.upgrade/migrate.state"
}

# --- State (key=value lines in the main checkout) ----------------------------------------------
STATE_KEYS="from target tag commit clone url prefix base branch worktree procedural"
state_get() {  # <key> -> value (the last line wins); exit 1 when absent
  [ -f "$STATE_FILE" ] || return 1
  LC_ALL=C awk -v k="$1" '{ sub(/\r$/, "") } (p = index($0, "=")) > 1 && substr($0, 1, p - 1) == k { v = substr($0, p + 1); f = 1 } END { if (f) print v; exit !f }' "$STATE_FILE"
}
# state_write <key=value>...: the given pairs replace those keys; every other key is kept. The
# file is rewritten through a temporary file and a rename, then re-read.
state_write() {
  local dir tmp k v pair given
  # One key=value per line: a value with a control character (a newline) could forge a key.
  for pair in "$@"; do has_ctrl "$pair" && die "refusing to record ${pair%%=*}: its value holds a control character (a newline?)"; done
  dir="$(dirname "$STATE_FILE")"
  if [ ! -d "$dir" ]; then
    mkdir -p "$dir" || die "cannot create $dir"
  fi
  # A runtime directory carries its own ignore file, so a v0.19 .gitignore never commits it [RU-M8].
  if [ ! -f "$dir/.gitignore" ]; then
    { printf '*\n' > "$dir/.gitignore.tmp.$$" && mv -f "$dir/.gitignore.tmp.$$" "$dir/.gitignore"; } || die "cannot write $dir/.gitignore"
  fi
  tmp="$dir/.migrate.state.tmp.$$"
  {
    for k in $STATE_KEYS; do
      given=false
      for pair in "$@"; do if [ "${pair%%=*}" = "$k" ]; then given=true; v="${pair#*=}"; fi; done
      if [ "$given" = true ]; then printf '%s=%s\n' "$k" "$v"
      elif v="$(state_get "$k")"; then printf '%s=%s\n' "$k" "$v"
      fi
    done
  } > "$tmp" && mv -f "$tmp" "$STATE_FILE" || { rm -f "$tmp"; die "cannot write $STATE_FILE"; }
  for pair in "$@"; do
    [ "$(state_get "${pair%%=*}")" = "${pair#*=}" ] || die "$STATE_FILE does not hold ${pair%%=*} after the write"
  done
}
state_drop() {  # <key>...: removes those keys
  local k tmp
  [ -f "$STATE_FILE" ] || return 0
  tmp="$(dirname "$STATE_FILE")/.migrate.state.tmp.$$"
  cp "$STATE_FILE" "$tmp" || die "cannot rewrite $STATE_FILE"
  for k in "$@"; do
    LC_ALL=C awk -v k="$k" '{ l = $0; sub(/\r$/, "", l) } !((p = index(l, "=")) > 1 && substr(l, 1, p - 1) == k) { print l }' "$tmp" > "$tmp.2" && mv -f "$tmp.2" "$tmp" ||
      { rm -f "$tmp" "$tmp.2"; die "cannot rewrite $STATE_FILE"; }
  done
  mv -f "$tmp" "$STATE_FILE" || die "cannot rewrite $STATE_FILE"
}
retire_state() {  # <why>: the upgrade is complete; its per-developer state goes
  rm -f "$STATE_FILE" || die "cannot remove $STATE_FILE"
  say "the upgrade to v$TARGET is complete ($1): removed $STATE_FILE"
}
main_at_target() {  # the main checkout's VERSION has reached the target (the upgrade is merged there)
  local v
  v="$(read_version "$MAIN_ROOT")" || return 1
  valid_version "$v" || return 1
  [ "$(vcmp "$v" "$TARGET")" != -1 ]
}

# --- The release clone -------------------------------------------------------------------------
# clone_tag <clone> <target> -> the annotated release tag at HEAD (v<target> preferred over an
# RC); exit 1 when there is none.
clone_tag() {
  local d="$1" t="$2" head tag pick=""
  head="$(cgit -C "$d" rev-parse -q --verify "HEAD^{commit}")" || return 1
  head="${head%$'\r'}"
  while IFS= read -r tag; do
    tag="${tag%$'\r'}"
    case "$tag" in
      "v$t") ;;
      "v$t-rc."*) printf '%s' "${tag#"v$t-rc."}" | LC_ALL=C grep -Eq '^[0-9]+$' || continue ;;
      *) continue ;;
    esac
    [ "$(cgit -C "$d" cat-file -t "refs/tags/$tag" 2>/dev/null | tr -d '\r')" = tag ] || continue
    [ "$(cgit -C "$d" rev-parse -q --verify "refs/tags/$tag^{commit}" | tr -d '\r')" = "$head" ] || continue
    if [ "$tag" = "v$t" ] || [ -z "$pick" ]; then pick="$tag"; fi
  done <<EOF
$(cgit -C "$d" tag --points-at HEAD 2>/dev/null)
EOF
  [ -n "$pick" ] && printf '%s\n' "$pick"
}
# shown_url <url>: a URL as it may be printed: without credentials, or "no origin"
shown_url() { if [ -n "$1" ]; then strip_userinfo "$1"; else printf 'no origin'; fi; }
# check_clone <clone> <source|state>: refuses (dies) unless the clone is a clean, tagged checkout
# of the trusted origin. source (plan --source): the origin must be this project's upstream, or
# the URL the user confirmed (--trust-origin), and that URL itself must name HEAD as the tag
# (git ls-remote, run outside the clone so its configuration cannot redirect it). state: the
# origin and HEAD must be the ones plan recorded (offline). Every git call on the clone is cgit.
# Sets CLONE_TOP, CLONE_TARGET, CLONE_TAG, CLONE_HEAD, CLONE_URL (credentials stripped).
check_clone() {
  local d="$1" mode="$2" v dirty hidden origin up trusted peeled rec
  has_ctrl "$d" && die "refused: the release clone's path holds a control character (a newline?): clone it to a plain path"
  d="$(native_path "$d")"
  [ -d "$d" ] || die "release clone $d does not exist"
  CLONE_TOP="$(cgit -C "$d" rev-parse --show-toplevel 2>/dev/null)" || die "$d is not a git checkout of the release"
  CLONE_TOP="${CLONE_TOP%$'\r'}"
  has_ctrl "$CLONE_TOP" && die "refused: the release clone's path holds a control character (a newline?): clone it to a plain path"
  [ -f "$CLONE_TOP/.sumela/VERSION" ] || die "$CLONE_TOP is not a SumelaOS release clone (.sumela/VERSION missing)"
  v="$(read_version "$CLONE_TOP")"
  valid_version "$v" || die "$CLONE_TOP/.sumela/VERSION holds '$v', not a release version"
  CLONE_TARGET="$v"
  if [ "$(cgit -C "$CLONE_TOP" rev-parse --path-format=absolute --git-common-dir | tr -d '\r')" = "$COMMON" ]; then
    die "the release clone is this repository: run the runner from your project's checkout, with --source <clone>"
  fi
  CLONE_HEAD="$(cgit -C "$CLONE_TOP" rev-parse -q --verify "HEAD^{commit}" | tr -d '\r')"
  [ -n "$CLONE_HEAD" ] || die "$CLONE_TOP has no commit checked out"
  # Every file the steps may run comes from the tag: nothing modified, staged or untracked, and
  # no entry hidden from git status (assume-unchanged, skip-worktree).
  dirty="$(cgit -C "$CLONE_TOP" status --porcelain --untracked-files=normal --ignore-submodules=none)" ||
    die "git cannot read the status of $CLONE_TOP"
  [ -z "$dirty" ] || die "refused: the release clone $CLONE_TOP has local changes (git -C <clone> status): $(printf '%s\n' "$dirty" | head -3 | tr '\n' ' ')"
  hidden="$(cgit -C "$CLONE_TOP" ls-files -v | LC_ALL=C grep -E '^[a-zSM] ' | head -3 | tr '\n' ' ')"
  [ -z "$hidden" ] || die "refused: the release clone $CLONE_TOP hides local changes (assume-unchanged or skip-worktree entries): $hidden"
  if CLONE_TAG="$(clone_tag "$CLONE_TOP" "$v")"; then :
  elif [ "$ALLOW_UNTAGGED" = true ]; then
    CLONE_TAG=""; warn "--allow-untagged: $CLONE_TOP is not at an annotated v$v tag (maintainer tests only)"
  else
    die "refused: $CLONE_TOP is not at an annotated release tag v$v or v$v-rc.<n> (git -C <clone> checkout v$v; git -C <clone> cat-file -t v$v must print tag)"
  fi
  origin="$(cgit -C "$CLONE_TOP" config --get remote.origin.url 2>/dev/null | tr -d '\r')" || origin=""
  if [ "$mode" = source ]; then
    up="$(upstream_url)"
    if [ -n "$origin" ] && [ "$(url_key "$origin")" = "$(url_key "$up")" ]; then
      trusted="$up"
    elif [ -n "$origin" ] && [ -n "$TRUST_ORIGIN" ] && [ "$(url_key "$origin")" = "$(url_key "$TRUST_ORIGIN")" ]; then
      trusted="$TRUST_ORIGIN"
      warn "--trust-origin: the clone comes from $(shown_url "$origin"), which the user confirmed (this project's upstream is $(shown_url "$up"))"
    elif [ -n "$TRUST_ORIGIN" ]; then
      die "refused: the release clone comes from $(shown_url "$origin"), not from $(shown_url "$TRUST_ORIGIN") as --trust-origin says"
    else
      die "refused: the release clone comes from $(shown_url "$origin"), not from this project's upstream $(shown_url "$up") (.sumela/upstream.conf, else $DEFAULT_UPSTREAM): clone the upstream, or pass --trust-origin <url> once the user confirms that source"
    fi
    if [ -n "$CLONE_TAG" ]; then
      # Asked of the trusted URL itself, without credentials (git would print them in its own
      # errors), from outside every repository: the clone's url.<x>.insteadOf cannot redirect it.
      # A local path goes to git in its native form (native_path).
      peeled="$(cd "$WORK" && GIT_CEILING_DIRECTORIES="$(dirname "$WORK")" GIT_ALLOW_PROTOCOL="${GIT_ALLOW_PROTOCOL:-https:ssh:git}" \
        git ls-remote -- "$(native_path "$(strip_userinfo "$trusted")")" "refs/tags/$CLONE_TAG^{}" | tr -d '\r')" ||
        die "refused: cannot ask $(shown_url "$trusted") for $CLONE_TAG (git ls-remote failed; the check needs the network)"
      peeled="${peeled%%[[:space:]]*}"
      [ "$peeled" = "$CLONE_HEAD" ] || die "refused: $(shown_url "$trusted") says $CLONE_TAG is ${peeled:-absent}, but the clone's HEAD is $CLONE_HEAD"
    fi
  else
    rec="$(state_get url || true)"
    [ "$(url_key "$origin")" = "$(url_key "$rec")" ] || die "refused: the release clone's origin is now $(shown_url "$origin"), not $(shown_url "$rec") as plan --source recorded"
    rec="$(state_get commit || true)"
    [ -z "$rec" ] || [ "$rec" = "$CLONE_HEAD" ] || die "refused: the release clone's HEAD is $CLONE_HEAD, not $rec as plan --source recorded"
  fi
  CLONE_URL="$(strip_userinfo "$origin")"
}
reclone() {  # <path>: the recorded clone is missing; clone the recorded tag again into it
  local d="$1" url tag
  url="$(state_get url)" || url=""
  [ -n "$url" ] || url="$(upstream_url)"
  tag="$(state_get tag)" || tag=""; [ -n "$tag" ] || tag="v$(state_get target)"
  say "the release clone $d is missing: cloning $(strip_userinfo "$url") at $tag again"
  GIT_ALLOW_PROTOCOL="${GIT_ALLOW_PROTOCOL:-https:ssh:git}" git clone --branch "$tag" -- "$(native_path "$url")" "$(native_path "$d")" ||
    die "cannot clone $(strip_userinfo "$url") at $tag into $d"
}

# --- Procedural steps (ledger: none) -----------------------------------------------------------------
# They leave no tracked ledger entry; this developer's state records them as <name>:<status> words.
proc_list() { if [ -f "$STATE_FILE" ]; then state_get procedural 2>/dev/null || true; fi; }
proc_status() { local e; for e in $(proc_list); do [ "${e%%:*}" = "$1" ] && printf '%s' "${e#*:}"; done; return 0; }
proc_set() {  # <name> <status|-> : replaces (or with -, removes) the entry
  local e out=""
  for e in $(proc_list); do [ "${e%%:*}" = "$1" ] || out="$out $e"; done
  [ "$2" = - ] || out="$out $1:$2"
  state_write "procedural=${out# }"
}

# --- Selection -----------------------------------------------------------------------------------
# recorded_list <scope> -> "<name><TAB><status>" for each recorded entry: repo -> the ledger files
# in {ROOT} and the procedural entries; developer -> each id's newest log line, unless it is
# rolled-back.
recorded_list() {
  local f st
  if [ "$1" = repo ]; then
    for f in "$RUN_ROOT/.sumela/migrations-applied"/*; do
      [ -f "$f" ] || continue
      st="$(LC_ALL=C sed -n 's/^status: //p' "$f" | tr -d '\r' | head -1)"
      printf '%s\t%s\n' "${f##*/}" "${st:-done}"
    done
    for f in $(proc_list); do printf '%s\t%s\n' "${f%%:*}" "${f#*:}"; done
  elif [ -f "$DEV_LOG" ]; then
    LC_ALL=C awk -F'\t' '{ sub(/\r$/, "") } NF >= 2 { s[$1] = $2 } END { for (i in s) if (s[i] != "rolled-back") print i "\t" s[i] }' "$DEV_LOG"
  fi
  return 0
}
# select_steps <scope> -> "P<TAB>id" rows for the pending steps, in run order, then "D<TAB>id"
# for the declined ones, then "X<TAB>id<TAB>reason<TAB>status" rows (recorded, moot,
# out-of-range, unlisted) for the rest of the scope.
select_steps() {
  local set=dev; [ "$1" = repo ] && set=repo
  recorded_list "$1" > "$WORK/recorded.list"
  MIG_REC="$WORK/recorded.list" LC_ALL=C awk -v set="$set" -v from="${FROM:-0.0.0}" -v target="${TARGET:-0.0.0}" \
      -v installed="${INSTALLED:-0.0.0}" -v withsrc="$WITH_SOURCE" "$AWK_LIB"'
    BEGIN {
      FS = "\t"
      while ((getline line < ENVIRON["MIG_REC"]) > 0) { sub(/\r$/, "", line); t = index(line, "\t"); if (t > 1) rec[substr(line, 1, t - 1)] = substr(line, t + 1) }
      np = split("pre-update update post-update finalize quiet-window first-session", ph, " ")
      for (i = 1; i <= np; i++) rank[ph[i]] = i
    }
    $1 == "M" && $2 == set { n++; ids[n] = $3; origin[$3] = $4; ver[$3] = $5; next }
    $1 == "K" && $2 == set { kv[$3, $4] = $5; next }
    END {
      for (i = 1; i <= n; i++) {
        id = ids[i]; v = (origin[id] == "generic") ? target : ver[id]; u = kv[id, "until"]
        top = (set == "repo") ? target : installed
        if (u != "" && vkey(u) <= vkey(top)) { why[id] = "moot"; continue }
        name = (set == "repo" && origin[id] == "generic") ? id "@" target : id
        st = (name in rec) ? rec[name] : ""
        key[id] = sprintf("%d|%s|%s", rank[kv[id, "when"]], vkey(v), id)
        if (st == "declined") { nd++; dec[nd] = id; continue }          # unfinished work, whatever the range
        if (st != "") { why[id] = "recorded"; stat[id] = st; continue }
        if (set == "repo") {
          if (origin[id] == "version" && !(vkey(from) < vkey(v) && vkey(v) <= vkey(target))) { why[id] = "out-of-range"; continue }
          if (kv[id, "ledger"] == "none" && withsrc != "1") { why[id] = "unlisted"; continue }
        } else if (vkey(v) > vkey(installed)) { why[id] = "out-of-range"; continue }
        m++; pend[m] = id; isp[id] = 1
      }
      for (out = 0; out < m; out++) {
        best = ""
        for (i = 1; i <= m; i++) {
          id = pend[i]; if (done[id]) continue
          ok = 1; c = split(kv[id, "requires"], rq, /[ ,]+/)
          for (j = 1; j <= c; j++) if (rq[j] != "" && (rq[j] in isp) && !done[rq[j]]) { ok = 0; break }
          if (ok && (best == "" || key[id] < key[best])) best = id
        }
        if (best == "") { print "CYCLE"; exit 4 }
        done[best] = 1; print "P\t" best
      }
      for (i = 1; i <= nd; i++) for (j = i + 1; j <= nd; j++) if (key[dec[j]] < key[dec[i]]) { x = dec[i]; dec[i] = dec[j]; dec[j] = x }
      for (i = 1; i <= nd; i++) print "D\t" dec[i]
      for (i = 1; i <= n; i++) if (ids[i] in why) print "X\t" ids[i] "\t" why[ids[i]] "\t" stat[ids[i]]
    }' "$TABLE" || die "the requires of the pending steps form a cycle"
}
count_rows() { LC_ALL=C awk -F'\t' -v k="$1" '$1 == k { c++ } END { print c + 0 }' "$2"; }
ids_of() { LC_ALL=C awk -F'\t' -v k="$1" '$1 == k { printf "%s%s", s, $2; s = " " }' "$2"; }

# --- Context: what a command needs ---------------------------------------------------------------
WITH_SOURCE=0
FROM="" TARGET="" INSTALLED="" SRC="" RUN_ROOT="" DEV_LOG="" HAVE_REPO=false REPO_NOTE=""
REPO_LOADED=false WT_OK=false WT_GONE="" REPO_DONE=""

# setup_dev: the developer scope reads the notes committed at this checkout's HEAD.
# Returns 0, or load_set's 1 or 4 (messages on stderr).
setup_dev() {
  local d
  INSTALLED="$(read_version "$LOCAL_ROOT")" || { warn "$LOCAL_ROOT/.sumela/VERSION is missing"; return 1; }
  valid_version "$INSTALLED" || { warn "$LOCAL_ROOT/.sumela/VERSION holds '$INSTALLED', not a version"; return 1; }
  d="$(sumela_state_dir --root "$LOCAL_ROOT")" || { warn "no per-developer state directory (scripts/lib/sumela-state.sh said why above)"; return 1; }
  DEV_LOG="$d/migrations.log"
  load_set dev "$LOCAL_ROOT"
}

# setup_repo [offline]: the repo scope reads the state and its verified release clone (cloned
# again when missing, unless offline). Returns 1 with REPO_NOTE when there is no upgrade in
# progress, when it is complete (REPO_DONE says why), or (offline) when its clone is unusable.
setup_repo() {
  local offline="${1:-}" clone wt top
  if [ -n "$SOURCE" ]; then            # plan --source: cmd_plan checked the clone and wrote the state
    WITH_SOURCE=1
    TARGET="$CLONE_TARGET"; SRC="$CLONE_TOP"; FROM="$(state_get from)"
  else
    [ -f "$STATE_FILE" ] || { REPO_NOTE="no upgrade in progress (start one with: plan --source <release clone>)"; return 1; }
    TARGET="$(state_get target)" || die "$STATE_FILE has no target: run plan --source <clone> again"
    valid_version "$TARGET" || die "$STATE_FILE holds target '$TARGET', not a version: run plan --source <clone> again"
    FROM="$(state_get from)" || die "$STATE_FILE has no from: run plan --source <clone> again"
    if main_at_target; then
      REPO_DONE="the main checkout is at v$(read_version "$MAIN_ROOT")"
      REPO_NOTE="the upgrade to v$TARGET is complete ($REPO_DONE)"; return 1
    fi
    clone="$(state_get clone)" || die "$STATE_FILE has no clone: run plan --source <clone> again"
    if [ ! -d "$clone" ]; then
      if [ "$offline" = offline ]; then
        REPO_NOTE="an upgrade to v$TARGET is recorded, but its release clone $clone is missing (plan clones it again)"
        return 1
      fi
      reclone "$clone"
    fi
    if [ "$offline" = offline ] && ! ( check_clone "$clone" state ) 2> "$WORK/clone.err"; then
      REPO_NOTE="an upgrade to v$TARGET is recorded, but its release clone $clone is unusable: $(tr '\n' ' ' < "$WORK/clone.err")"
      return 1
    fi
    check_clone "$clone" state
    [ "$CLONE_TARGET" = "$TARGET" ] || die "the release clone $clone now says v$CLONE_TARGET, the state says v$TARGET: run plan --source <clone>"
    SRC="$CLONE_TOP"
  fi
  RUN_ROOT="$MAIN_ROOT"
  if wt="$(state_get worktree)" && [ -n "$wt" ]; then
    top="$(join_root "$wt" "$PREFIX")"
    if [ -d "$top/.sumela" ]; then RUN_ROOT="$top"; WT_OK=true
    else WT_GONE="$wt"; REPO_NOTE="the recorded upgrade worktree $wt no longer exists: repo steps neither run nor roll back without it"
    fi
  fi
  if [ "$REPO_LOADED" != true ]; then
    load_set repo "$SRC"
    case $? in 0) ;; 4) [ "$offline" = offline ] && { REPO_NOTE="the release clone's notes are invalid (see above)"; return 1; }; exit 4 ;; *) exit 1 ;; esac
    REPO_LOADED=true
  fi
  HAVE_REPO=true
  return 0
}

# plan_repo_state: plan --source writes or refreshes the state, once the clone and its notes have
# been verified. Returns 0, or 2 when the install is already at the release.
plan_repo_state() {
  local old_target old_commit wt v
  if [ -f "$STATE_FILE" ]; then
    old_target="$(state_get target || true)"; old_commit="$(state_get commit || true)"
    wt="$(state_get worktree || true)"
    if [ "$old_target" = "$CLONE_TARGET" ] && { [ -z "$old_commit" ] || [ "$old_commit" = "$CLONE_HEAD" ]; }; then
      if [ "$(state_get clone || true)" != "$(native_path "$CLONE_TOP")" ] || [ "$(state_get tag || true)" != "$CLONE_TAG" ]; then
        say "the upgrade to v$CLONE_TARGET continues from $CLONE_TOP${CLONE_TAG:+ ($CLONE_TAG)}"
        state_write "clone=$(native_path "$CLONE_TOP")" "tag=$CLONE_TAG" "commit=$CLONE_HEAD" "url=$CLONE_URL"
      fi
      return 0
    fi
    TARGET="$old_target"
    if valid_version "$old_target" && main_at_target; then
      retire_state "the main checkout is at v$(read_version "$MAIN_ROOT")"
    elif [ -n "$wt" ] && [ -d "$wt" ]; then
      die "an upgrade to v$old_target is in progress in $wt ($STATE_FILE): finish it (plan), or abandon it (rollback upgrade-01 --confirmed-by-user removes its worktree and branch); once its pull request is merged, update the main checkout and run plan --source again"
    else
      say "replacing the state of the earlier upgrade to v$old_target (its worktree is gone)"
      rm -f "$STATE_FILE"
    fi
  fi
  TARGET="$CLONE_TARGET"
  v="$(read_version "$LOCAL_ROOT")" || die "$LOCAL_ROOT/.sumela/VERSION is missing"
  valid_version "$v" || die "$LOCAL_ROOT/.sumela/VERSION holds '$v', not a version"
  case "$(vcmp "$v" "$CLONE_TARGET")" in
    0) say "this install is already at v$v: no repo steps (a teammate runs the developer steps: plan --scope developer)"
       return 2 ;;
    1) die "the release clone (v$CLONE_TARGET) is older than this install (v$v): refusing (a downgrade is update.sh --rollback-to)" ;;
  esac
  state_write "from=$v" "target=$CLONE_TARGET" "tag=$CLONE_TAG" "commit=$CLONE_HEAD" "clone=$(native_path "$CLONE_TOP")" "url=$CLONE_URL"
  say "recorded the upgrade v$v -> v$CLONE_TARGET in $STATE_FILE"
}

# --- Resolving one step --------------------------------------------------------------------------
# {TARGET} is the release being installed for a repo step, the installed version for a developer step.
STEP_ID="" STEP_SCOPE="" STEP_SRC="" STEP_ROOT="" STEP_STATE="" STEP_TARGET=""
resolve_step() {  # <id>: loads what the step needs and sets the STEP_* variables
  local id="$1" row devrc=0
  [ -n "$id" ] || die "$CMD needs a step id"
  # A generic step is always a repo step. Any other id is looked up among the developer steps
  # installed here first, so a developer step never needs the release clone; a failure there
  # only matters when the id is not a repo step either.
  case "$id" in
    upgrade-*) ;;
    *) setup_dev 2> "$WORK/dev.err"; devrc=$? ;;
  esac
  if [ "$devrc" -eq 0 ] && [ "$(meta "$id" set 2>/dev/null)" = dev ]; then
    STEP_SCOPE=developer; STEP_SRC=""; STEP_ROOT="$LOCAL_ROOT"; STEP_TARGET="$INSTALLED"
  elif setup_repo && [ "$(meta "$id" set 2>/dev/null)" = repo ]; then
    STEP_SCOPE=repo; STEP_SRC="$SRC"; STEP_ROOT="$RUN_ROOT"; STEP_TARGET="$TARGET"
  else
    [ -s "$WORK/dev.err" ] && cat "$WORK/dev.err" >&2
    [ "$devrc" -ne 0 ] && exit "$devrc"
    if [ -n "$REPO_DONE" ]; then die "$REPO_NOTE: its repo steps neither run nor roll back any more (after the merge, git revert -m 1 <merge> undoes them)"; fi
    if [ "$HAVE_REPO" = true ]; then die "unknown step $id: not in the release clone's notes, nor a developer step installed at $LOCAL_ROOT"; fi
    die "unknown step $id: not a developer step installed at $LOCAL_ROOT, and $REPO_NOTE"
  fi
  STEP_ID="$id"
  select_steps "$STEP_SCOPE" > "$WORK/sel.tsv"
  row="$(LC_ALL=C awk -F'\t' -v id="$id" '$2 == id { print ($1 == "P") ? "pending" : (($1 == "D") ? "declined" : $3); exit }' "$WORK/sel.tsv")"
  STEP_STATE="${row:-unknown}"
}
ledger_name() { if [ "$(meta "$1" origin)" = generic ]; then printf '%s@%s' "$1" "$TARGET"; else printf '%s' "$1"; fi; }
ledger_status() {  # <id> -> the recorded status, empty when none
  local f
  if [ "$STEP_SCOPE" = repo ] && [ "$(field "$1" ledger)" = none ]; then
    proc_status "$(ledger_name "$1")"
  elif [ "$STEP_SCOPE" = repo ]; then
    f="$RUN_ROOT/.sumela/migrations-applied/$(ledger_name "$1")"
    [ -f "$f" ] && LC_ALL=C sed -n 's/^status: //p' "$f" | tr -d '\r' | head -1
  elif [ -f "$DEV_LOG" ]; then
    LC_ALL=C awk -F'\t' -v id="$1" '{ sub(/\r$/, "") } $1 == id { s = $2 } END { if (s != "") print s }' "$DEV_LOG"
  fi
  return 0
}
explain_state() {  # human text for STEP_STATE
  local v
  case "$STEP_STATE" in
    pending) printf 'pending' ;;
    declined) printf 'declined (run it when ready)' ;;
    recorded) printf 'recorded: %s' "$(ledger_status "$STEP_ID")" ;;
    moot) if [ "$STEP_SCOPE" = repo ]; then printf 'moot (until %s; the release is v%s)' "$(field "$STEP_ID" until)" "$TARGET"
          else printf 'moot (until %s; this install is at v%s)' "$(field "$STEP_ID" until)" "$INSTALLED"; fi ;;
    out-of-range)
      v="$(meta "$STEP_ID" version)"
      if [ "$STEP_SCOPE" = repo ]; then printf 'not selected (v%s is not in (v%s, v%s])' "$v" "$FROM" "$TARGET"
      else printf 'not selected (v%s is above the installed v%s)' "$v" "$INSTALLED"; fi ;;
    unlisted) printf 'listed only with --source (ledger: none)' ;;
    *) printf '%s' "$STEP_STATE" ;;
  esac
}
# unmet_requires: the step's requires that are not recorded done, as "<id> (<why>)" words. A
# required step outside this upgrade (moot, or of a version it does not span) counts as met.
unmet_requires() {
  local q row out="" st
  for q in $(field "$STEP_ID" requires | tr ',' ' '); do
    row="$(LC_ALL=C awk -F'\t' -v id="$q" '$2 == id { print $1 "\t" $3 "\t" $4; exit }' "$WORK/sel.tsv")"
    case "$row" in
      P*) out="$out $q (not done yet)" ;;
      D*) out="$out $q (declined)" ;;
      X"$TAB"recorded*) st="${row##*"$TAB"}"; case "$st" in done|"done (pre-satisfied)") ;; *) out="$out $q ($st)" ;; esac ;;
      X"$TAB"unlisted*) [ "$(proc_status "$(ledger_name "$q")")" = done ] || out="$out $q (not done yet)" ;;
    esac
  done
  printf '%s' "${out# }"
}
# need_worktree: repo steps run, record and roll back in the upgrade worktree, never in the main
# checkout, and never after their worktree is gone (after the merge: git revert -m 1 <merge>).
need_worktree() {
  [ "$STEP_SCOPE" = repo ] || return 0
  [ "$WT_OK" = true ] && return 0
  if [ -n "$WT_GONE" ]; then
    die "the recorded upgrade worktree $WT_GONE no longer exists: repo steps neither run, record nor roll back without it (after the merge, git revert -m 1 <merge> undoes the repo steps; to start again, create a worktree and set worktree=<path>)"
  fi
  die "$STEP_ID runs in the upgrade worktree, which upgrade-01 creates: follow upgrade-01's agent: line (set worktree=<path>) first"
}

# --- Running commands ----------------------------------------------------------------------------
in_step_env() { SUMELA_MIGRATE_SRC="$STEP_SRC" SUMELA_MIGRATE_ROOT="$STEP_ROOT" "$@"; }
print_env() { printf '  (SUMELA_MIGRATE_SRC=%s SUMELA_MIGRATE_ROOT=%s)\n' "$STEP_SRC" "$STEP_ROOT"; }
# run_line <command>: runs it from {ROOT}; output is never filtered. The step's own shell enters
# {ROOT}: no process of the runner sits in it meanwhile (Windows cannot remove a directory a
# process is in, and upgrade-01's rollback removes {ROOT}).
run_line() {
  in_step_env "${BASH:-bash}" -c 'cd "$SUMELA_MIGRATE_ROOT" || exit 1
'"$1"
}
VERIFY_OUT="" VERIFY_RC=0
# verify_quiet <id>: sets VERIFY_OUT (stdout and stderr, CRs dropped); 0 holds, 3 failed, 4 bad expect
verify_quiet() {
  local cmd exp all
  cmd="$(subst_cmd "$(field "$1" verify)")"; exp="$(subst_expect "$(field "$1" expect)")"
  all="$(run_line "$cmd" 2>&1; printf '\n%s' "$?")"
  VERIFY_RC="${all##*$'\n'}"
  VERIFY_OUT="$(printf '%s' "${all%$'\n'*}" | tr -d '\r')"
  [ "$VERIFY_RC" -eq 0 ] || return 3
  case "$exp" in
    exit0) return 0 ;;
    non-empty) [ -n "$VERIFY_OUT" ] && return 0 ;;
    empty) [ -z "$VERIFY_OUT" ] && return 0 ;;
    equals:*) [ "$VERIFY_OUT" = "${exp#equals:}" ] && return 0 ;;
    match:*) printf '%s\n' "$VERIFY_OUT" | LC_ALL=C grep -Eq -- "${exp#match:}" && return 0 ;;
    *) return 4 ;;
  esac
  return 3
}
# verify_step <id>: prints the command, its output and the verdict; 0, 3 or 4
verify_step() {
  local rc exp
  exp="$(subst_expect "$(field "$1" expect)")"
  say "verify $1 in $STEP_ROOT"
  printf '  $ %s\n' "$(subst_cmd "$(field "$1" verify)")"
  verify_quiet "$1"; rc=$?
  [ -n "$VERIFY_OUT" ] && printf '%s\n' "$VERIFY_OUT"
  case "$rc" in
    0) say "verify $1: ok (expect $exp)" ;;
    4) warn "verify $1: expect '$exp' is not a valid form" ;;
    *) if [ "${VERIFY_RC:-1}" -ne 0 ]; then warn "verify $1: FAILED (the verify command exited $VERIFY_RC)"
       else warn "verify $1: FAILED (expected $exp; the output is above)"; fi ;;
  esac
  return "$rc"
}

# --- Ledgers -------------------------------------------------------------------------------------
# write_ledger <id> <status>: repo -> {ROOT}/.sumela/migrations-applied/<name> plus provenance;
# developer -> one log line. Each write is re-read.
write_ledger() {
  local id="$1" status="$2" name dir f at
  at="$(utc_now)"
  if [ "$STEP_SCOPE" = repo ]; then
    if [ "$(field "$id" ledger)" = none ]; then
      # A procedural step leaves no tracked entry; this developer's state remembers it.
      proc_set "$(ledger_name "$id")" "$status"
      [ "$(ledger_status "$id")" = "$status" ] || die "$STATE_FILE does not hold $id $status after the write"
      say "recorded $id $status in $STATE_FILE (ledger: none: no tracked entry)"
      return 0
    fi
    name="$(ledger_name "$id")"; dir="$RUN_ROOT/.sumela/migrations-applied"; f="$dir/$name"
    mkdir -p "$dir" || die "cannot create $dir"
    printf 'status: %s\nat: %s\nversion: %s\n' "$status" "$at" "$TARGET" > "$f.tmp.$$" && mv -f "$f.tmp.$$" "$f" ||
      { rm -f "$f.tmp.$$"; die "cannot write $f"; }
    [ "$(ledger_status "$id")" = "$status" ] || die "$f does not hold status $status after the write"
    sumela_record_add_files --record "$RUN_ROOT/.sumela/.last-update.json" ".sumela/migrations-applied/$name" ||
      die "recorded $f, but the provenance record $RUN_ROOT/.sumela/.last-update.json was not updated (see above)"
    say "recorded $id $status in $f (added to the provenance record)"
  else
    printf '%s\t%s\t%s\n' "$id" "$status" "$at" | sumela_state_write --root "$LOCAL_ROOT" --append migrations.log ||
      die "cannot append to $DEV_LOG"
    [ "$(ledger_status "$id")" = "$status" ] || die "$DEV_LOG does not hold $id $status after the write"
    say "recorded $id $status in $DEV_LOG"
  fi
}

# --- Commands ------------------------------------------------------------------------------------
print_pending() {  # <scope> <sel file>: the pending lines, then the declined ones
  local id kind line
  if [ "$1" = repo ]; then STEP_SRC="$SRC"; STEP_ROOT="$RUN_ROOT"; STEP_TARGET="$TARGET"
  else STEP_SRC=""; STEP_ROOT="$LOCAL_ROOT"; STEP_TARGET="$INSTALLED"; fi
  while IFS="$TAB" read -r kind id _; do
    [ "$kind" = P ] || continue
    printf '    %s  %s  consent=%s  %s\n' "$id" "$(field "$id" when)" "$(field "$id" consent)" "$(subst_text "$(field "$id" title)")"
  done < "$2"
  line="$(ids_of D "$2")"
  [ -n "$line" ] && echo "  declined (still to do; run <id> when ready): $line"
  return 0
}

cmd_plan() {
  local want_repo=true want_dev=true repo_n=0 dev_n=0 id rc first="" line kind
  [ "$SCOPE" = developer ] && want_repo=false
  [ "$SCOPE" = repo ] && want_dev=false
  say "plan for $LOCAL_ROOT"
  if [ "$want_repo" = true ] && [ -n "$SOURCE" ]; then
    check_clone "$SOURCE" source
    # The clone's notes must pass the lint before anything is recorded.
    load_set repo "$CLONE_TOP"; rc=$?
    case "$rc" in 0) REPO_LOADED=true ;; *) exit "$rc" ;; esac
    plan_repo_state; rc=$?
    [ "$rc" -eq 2 ] && want_repo=false
  fi
  if [ "$want_repo" = true ]; then
    if setup_repo; then
      select_steps repo > "$WORK/sel-repo.tsv"
      repo_n="$(count_rows P "$WORK/sel-repo.tsv")"
      echo "Repo steps: v$FROM -> v$TARGET from $SRC${CLONE_TAG:+ ($CLONE_TAG)}"
      echo "  state: $STATE_FILE"
      echo "  root:  $RUN_ROOT$([ "$WT_OK" = true ] || printf ' (the main checkout: only upgrade-01 runs here)')"
      [ -n "$REPO_NOTE" ] && echo "  note:  $REPO_NOTE"
      echo "  pending ($repo_n, in order):"
      print_pending repo "$WORK/sel-repo.tsv"
      line="$(LC_ALL=C awk -F'\t' '$1 == "X" && $3 == "recorded" { printf "%s%s", sep, $2; sep = " " }' "$WORK/sel-repo.tsv")"
      [ -n "$line" ] && echo "  recorded: $line"
      first="$(LC_ALL=C awk -F'\t' '$1 == "P" { print $2; exit }' "$WORK/sel-repo.tsv")"
      line="$(LC_ALL=C awk -F'\t' '$1 == "X" && $3 == "unlisted" { printf "%s%s", sep, $2; sep = " " }' "$WORK/sel-repo.tsv")"
      [ -n "$line" ] && echo "  listed with --source only (ledger: none): $line"
      # The state outlives the last step until the merge reaches the main checkout: the repo
      # rollbacks need it before the merge.
      if [ "$repo_n" -eq 0 ] && [ -z "$line" ] && [ -z "$(ids_of D "$WORK/sel-repo.tsv")" ]; then
        if [ "$WT_OK" = true ]; then
          echo "  every repo step is recorded: merge the upgrade pull request, then update the main checkout (until then, $STATE_FILE stays for the rollbacks)"
        else
          retire_state "every repo step is recorded and the upgrade worktree is gone"
        fi
      fi
    else
      [ -n "$REPO_DONE" ] && retire_state "$REPO_DONE"
      echo "Repo steps: $REPO_NOTE"
    fi
  fi
  if [ "$want_dev" = true ]; then
    setup_dev; rc=$?
    if [ "$rc" -ne 0 ]; then
      echo "Developer steps: not read (see above)"
      printf 'pending_repo=%s pending_developer=?\n' "$repo_n"
      exit "$rc"
    fi
    select_steps developer > "$WORK/sel-dev.tsv"
    # Developer steps whose read-only verify already passes are recorded done (pre-satisfied).
    while IFS="$TAB" read -r kind id _; do
      [ "$kind" = P ] || continue
      # The line reaches awk through the environment: awk -v would process its backslashes.
      MIG_S="$(field "$id" verify)" LC_ALL=C awk "$AWK_LIB"'BEGIN { exit !readonly_cmd(ENVIRON["MIG_S"]) }' || continue
      STEP_ID="$id"; STEP_SCOPE=developer; STEP_SRC=""; STEP_ROOT="$LOCAL_ROOT"; STEP_TARGET="$INSTALLED"
      if verify_quiet "$id"; then
        echo "  $id: its read-only verify already passes:"
        [ -n "$VERIFY_OUT" ] && printf '%s\n' "$VERIFY_OUT" | sed 's/^/    | /'
        write_ledger "$id" "done (pre-satisfied)"
      fi
    done < "$WORK/sel-dev.tsv"
    select_steps developer > "$WORK/sel-dev.tsv"
    dev_n="$(count_rows P "$WORK/sel-dev.tsv")"
    echo "Developer steps (installed v$INSTALLED, notes at the HEAD of $LOCAL_ROOT):"
    echo "  ledger: $DEV_LOG"
    echo "  pending ($dev_n, in order):"
    print_pending developer "$WORK/sel-dev.tsv"
    [ -n "$first" ] || first="$(LC_ALL=C awk -F'\t' '$1 == "P" { print $2; exit }' "$WORK/sel-dev.tsv")"
  fi
  [ -n "$first" ] && echo "next: show $first"
  printf 'pending_repo=%s pending_developer=%s\n' "$repo_n" "$dev_n"
}

# declined repo ledgers in the main checkout, without a release clone: a generic step's entry
# counts for the installed release only; a version step's entry until it is redone.
declined_ledgers() {
  local f n=0 v
  v="$(read_version "$MAIN_ROOT" || true)"
  for f in "$MAIN_ROOT/.sumela/migrations-applied"/*; do
    [ -f "$f" ] || continue
    case "${f##*/}" in *@*) [ "${f##*@}" = "$v" ] || continue ;; esac
    [ "$(LC_ALL=C sed -n 's/^status: //p' "$f" | tr -d '\r' | head -1)" = declined ] && n=$((n + 1))
  done
  printf '%s' "$n"
}
cmd_status() {
  local repo_n=0 dev_n=0 repo_d=0 dev_d=0
  if [ "$SCOPE" != developer ]; then
    if setup_repo offline; then
      select_steps repo > "$WORK/sel-repo.tsv"
      repo_n="$(count_rows P "$WORK/sel-repo.tsv")"; repo_d="$(count_rows D "$WORK/sel-repo.tsv")"
    else
      [ -f "$STATE_FILE" ] && [ -z "$REPO_DONE" ] && warn "$REPO_NOTE"
      repo_d="$(declined_ledgers)"
    fi
  fi
  if [ "$SCOPE" != repo ]; then
    setup_dev || exit $?
    select_steps developer > "$WORK/sel-dev.tsv"
    dev_n="$(count_rows P "$WORK/sel-dev.tsv")"; dev_d="$(count_rows D "$WORK/sel-dev.tsv")"
  fi
  case "$SCOPE" in
    repo) printf 'pending_repo=%s\n' "$repo_n"; [ "$repo_d" -eq 0 ] || printf 'declined_repo=%s\n' "$repo_d" ;;
    developer) printf 'pending_developer=%s\n' "$dev_n"; [ "$dev_d" -eq 0 ] || printf 'declined_developer=%s\n' "$dev_d" ;;
    *) printf 'pending_repo=%s pending_developer=%s\n' "$repo_n" "$dev_n"
       [ "$repo_d" -eq 0 ] && [ "$dev_d" -eq 0 ] || printf 'declined_repo=%s declined_developer=%s\n' "$repo_d" "$dev_d" ;;
  esac
}

# refuse_tracking <checkout> <branch>: the upgrade branch may track only its own remote branch
# (after git push -u). A branch that tracks the base would let a push land there.
refuse_tracking() {
  local up
  up="$(git -C "$1" config --get "branch.$2.merge" 2>/dev/null | tr -d '\r')"
  [ -z "$up" ] || [ "$up" = "refs/heads/$2" ] ||
    die "the upgrade branch $2 tracks $up: a push could land there. Remove its upstream (git branch --unset-upstream $2), or create the worktree with git worktree add --no-track"
}
cmd_set() {
  local pair k v top common gitdir br t pairs=() derived_branch="" new_from=""
  [ "$NARGS" -gt 0 ] || die "set needs <key>=<value> (keys: prefix, base, branch, worktree)"
  [ -f "$STATE_FILE" ] || die "no upgrade in progress: run plan --source <release clone> first"
  t="$(state_get target)" || die "$STATE_FILE has no target"
  for pair in "${ARGS[@]}"; do
    case "$pair" in *=*) ;; *) die "set takes <key>=<value>, not '$pair'" ;; esac
    k="${pair%%=*}"; v="${pair#*=}"
    has_ctrl "$v" && die "a value is one line of plain characters (this one holds a control character)"
    case "$k" in
      prefix)
        if ! git check-ref-format --branch "${v}upgrade-$t" >/dev/null 2>&1; then die "prefix '$v' does not make a valid branch name (${v}upgrade-$t)"; fi ;;
      base)
        git -C "$MAIN_ROOT" rev-parse -q --verify "$v^{commit}" >/dev/null || die "base '$v' is not a commit in this repository (git fetch first?)" ;;
      branch)
        git check-ref-format --branch "$v" >/dev/null 2>&1 || die "branch '$v' is not a valid branch name"
        refuse_tracking "$MAIN_ROOT" "$v" ;;
      worktree)
        v="$(native_path "$v")"
        [ -d "$v" ] || die "worktree $v does not exist (create it with git worktree add first)"
        top="$(git -C "$v" rev-parse --show-toplevel 2>/dev/null | tr -d '\r')" || die "$v is not a git checkout"
        common="$(git -C "$top" rev-parse --path-format=absolute --git-common-dir | tr -d '\r')"
        gitdir="$(git -C "$top" rev-parse --path-format=absolute --git-dir | tr -d '\r')"
        [ "$common" = "$COMMON" ] || die "$v is a checkout of another repository, not a worktree of this one"
        [ "$gitdir" != "$common" ] || die "$v is the main checkout: the upgrade runs in a new linked worktree (git worktree add --no-track -b <branch> <path> <base>)"
        [ -d "$(join_root "$top" "$PREFIX")/.sumela" ] || die "$v has no $(join_root . "$PREFIX")/.sumela/ install"
        v="$(native_path "$top")"
        br="$(git -C "$top" rev-parse --abbrev-ref HEAD 2>/dev/null | tr -d '\r')"
        if [ -n "$br" ] && [ "$br" != HEAD ]; then refuse_tracking "$top" "$br"; derived_branch="$br"; fi
        new_from="$(read_version "$(join_root "$top" "$PREFIX")" || true)" ;;
      from|target|tag|commit|clone|url) die "$k comes from plan --source; set records only confirmed values (prefix, base, branch, worktree)" ;;
      *) die "unknown key '$k' (keys: prefix, base, branch, worktree)" ;;
    esac
    pairs+=("$k=$v")
  done
  case " ${pairs[*]} " in *" branch="*) ;; *) [ -n "$derived_branch" ] && pairs+=("branch=$derived_branch") ;; esac
  # The worktree is cut from the base: its VERSION is the version the upgrade starts from.
  if [ -n "$new_from" ] && valid_version "$new_from" && [ "$new_from" != "$(state_get from)" ]; then
    case "$(vcmp "$new_from" "$t")" in
      -1) pairs+=("from=$new_from"); say "the worktree is at v$new_from: the upgrade now starts from v$new_from" ;;
      *) ls "$(join_root "$top" "$PREFIX")/.sumela/migrations-applied/"*"@$t" >/dev/null 2>&1 ||
           warn "the worktree is already at v$new_from (>= v$t): merge the base instead of upgrading (upgrade-02 refuses)" ;;
    esac
  fi
  state_write "${pairs[@]}"
  for pair in "${pairs[@]}"; do say "recorded ${pair%%=*}=${pair#*=}"; done
}

cmd_show() {
  local id="$1" k v line
  resolve_step "$id"
  echo "step: $id ($STEP_SCOPE, $(meta "$id" file):$(meta "$id" line))"
  echo "status: $(explain_state)"
  echo "root: $STEP_ROOT$([ "$STEP_SCOPE" = repo ] && [ "$WT_OK" != true ] && printf ' (no upgrade worktree yet: only upgrade-01 and verify work here)')"
  print_env
  LC_ALL=C awk -F'\t' -v id="$id" '$1 == "K" && $3 == id { print $4 "\t" $5 }' "$TABLE" > "$WORK/show.tsv"
  while IFS="$TAB" read -r k v; do
    case "$k" in
      title|agent) printf '%s: %s\n' "$k" "$(subst_text "$v")" ;;
      expect) printf '%s: %s\n' "$k" "$(subst_expect "$v")" ;;
      rollback.ps1) printf '%s: %s%s\n' "$k" "$(subst_ps "$v")" "$([ "$STEP_SCOPE" = repo ] && printf '   (before the merge only)')" ;;
      rollback) printf '%s: %s%s\n' "$k" "$(subst_cmd "$v")" "$([ "$STEP_SCOPE" = repo ] && printf '   (before the merge only)')" ;;
      *.ps1) printf '%s: %s\n' "$k" "$(subst_ps "$v")" ;;
      *) printf '%s: %s\n' "$k" "$(subst_cmd "$v")" ;;
    esac
  done < "$WORK/show.tsv"
  line="$(unmet_requires)"
  [ -n "$line" ] && echo "waiting for: $line"
  return 0
}

refuse_unselectable() {  # run/record/rollback only touch steps of the current selection
  case "$STEP_STATE" in
    pending|declined|recorded|unlisted) return 0 ;;
    *) die "$STEP_ID is $(explain_state): nothing to do" ;;
  esac
}

cmd_run() {
  local id="$1" cmd st req rc
  resolve_step "$id"
  refuse_unselectable
  st="$(ledger_status "$id")"
  case "$st" in
    ''|rolled-back) ;;
    declined) say "$id was recorded declined: running it now" ;;
    *) die "$id is already recorded ($st): nothing to run" ;;
  esac
  req="$(unmet_requires)"
  [ -z "$req" ] || die "$id requires these steps to be recorded done first: $req"
  cmd="$(field "$id" run)"
  # Only upgrade-01, which creates the worktree, is followed from the main checkout: every other
  # repo step, an agent: line included, names {ROOT}, which must be the upgrade worktree.
  if [ "$cmd" != "-" ] || [ "$id" != upgrade-01 ]; then need_worktree; fi
  # Fail closed: anything but none or confirm needs the typed confirmation, run: - steps too.
  case "$(field "$id" consent)" in
    none|confirm) ;;
    *) warn "$id needs explicit consent (consent: $(field "$id" consent)): the user types the confirmation, then: run $id --confirmed-by-user"
       [ "$CONFIRMED" = true ] || exit 2 ;;
  esac
  if [ "$cmd" = "-" ]; then
    say "$id is performed by the agent (run: -): nothing was executed. Follow its agent: line, then: verify $id"
    printf 'agent: %s\n' "$(subst_text "$(field "$id" agent)")"
    return 0
  fi
  cmd="$(subst_cmd "$cmd")"
  say "run $id in $STEP_ROOT (consent: $(field "$id" consent))"
  printf '  $ %s\n' "$cmd"
  print_env
  run_line "$cmd"; rc=$?
  if [ "$rc" -ne 0 ]; then warn "run $id: the command exited $rc"; exit 1; fi
  say "run $id: the command exited 0. Next: verify $id"
}

cmd_verify() {
  resolve_step "$1"
  verify_step "$1"
}

cmd_record() {
  local id="$1" status="${2:-}" rc req
  case "$status" in done|declined|not-applicable) ;; *) die "record needs done, declined or not-applicable" ;; esac
  resolve_step "$id"
  refuse_unselectable
  need_worktree
  if [ "$status" = done ]; then
    req="$(unmet_requires)"
    [ -z "$req" ] || die "$id cannot be done before these steps are recorded done: $req"
    verify_step "$id"; rc=$?
    if [ "$rc" -ne 0 ]; then warn "not recorded: $id is done only when its verify passes"; exit "$rc"; fi
  fi
  write_ledger "$id" "$status"
}

cmd_rollback() {
  local id="$1" cmd rc name rel f saved="" staged=false proc="" wt
  resolve_step "$id"
  refuse_unselectable
  if [ "$CONFIRMED" != true ]; then
    warn "rollback changes the checkout: the user confirms, then: rollback $id --confirmed-by-user"
    exit 2
  fi
  cmd="$(field "$id" rollback)"
  [ -n "$cmd" ] || die "$id has no rollback line: nothing to undo"
  need_worktree
  # The ledger entry goes first: the rollback line may need a clean worktree. It comes back if
  # the line fails.
  if [ "$STEP_SCOPE" = repo ] && [ "$(field "$id" ledger)" = none ]; then
    proc="$(ledger_status "$id")"
    [ -n "$proc" ] && proc_set "$(ledger_name "$id")" -
  elif [ "$STEP_SCOPE" = repo ]; then
    rel=".sumela/migrations-applied/$(ledger_name "$id")"; f="$RUN_ROOT/$rel"
    if [ -f "$f" ]; then
      saved="$WORK/ledger.saved"; cp "$f" "$saved" || die "cannot keep a copy of $f"
      if git -C "$RUN_ROOT" ls-files --error-unmatch -- "$rel" >/dev/null 2>&1 && ! git -C "$RUN_ROOT" cat-file -e "HEAD:./$rel" 2>/dev/null; then
        staged=true; git -C "$RUN_ROOT" rm -q --cached -- "$rel" || die "cannot unstage $rel"
      fi
      rm -f "$f" || die "cannot remove $f"
    fi
  fi
  cmd="$(subst_cmd "$cmd")"
  say "rollback $id in $STEP_ROOT"
  printf '  $ %s\n' "$cmd"
  print_env
  run_line "$cmd"; rc=$?
  if [ "$rc" -ne 0 ]; then
    if [ -n "$proc" ]; then proc_set "$(ledger_name "$id")" "$proc"; fi
    if [ -n "$saved" ] && [ -d "$(dirname "$f")" ]; then
      cp "$saved" "$f" && { [ "$staged" = false ] || git -C "$RUN_ROOT" add -- "$rel"; } && say "restored the ledger entry $f"
    fi
    warn "rollback $id: the command exited $rc"; exit 1
  fi
  if [ "$STEP_SCOPE" = repo ]; then
    say "$id is pending again"
    wt="$(state_get worktree || true)"
    if [ -n "$wt" ] && [ ! -d "$(join_root "$wt" "$PREFIX")/.sumela" ]; then
      state_drop worktree branch
      say "the rollback removed the upgrade worktree $wt: cleared it from $STATE_FILE"
    fi
  elif [ -n "$(ledger_status "$id")" ]; then
    write_ledger "$id" rolled-back
  fi
  say "rollback $id: done"
}

cmd_lint() {
  local f
  if [ "$NARGS" -eq 0 ]; then
    for f in "$SCRIPT_DIR/sumela-migrations"/*.md; do [ -f "$f" ] && ARGS+=("$f"); done
    NARGS=${#ARGS[@]}
    [ "$NARGS" -gt 0 ] || die "no notes files in $SCRIPT_DIR/sumela-migrations/"
  fi
  lint_files "${ARGS[@]}"
}

# --- Dispatch ------------------------------------------------------------------------------------
case "$CMD" in
  ''|help) usage; [ -n "$CMD" ]; exit $? ;;
  lint) cmd_lint; exit $? ;;
  plan|status|set|show|run|verify|record|rollback) ;;
  *) warn "unknown command: $CMD"; usage >&2; exit 1 ;;
esac
for lib in sumela-state.sh sumela-provenance.sh; do
  [ -f "$SCRIPT_DIR/lib/$lib" ] || die "missing $SCRIPT_DIR/lib/$lib"
  # shellcheck disable=SC1090
  . "$SCRIPT_DIR/lib/$lib"
done
command -v git >/dev/null 2>&1 || die "git is required"
locate
case "$CMD" in
  plan) [ "$NARGS" -eq 0 ] || die "plan takes no arguments"; cmd_plan ;;
  status) [ "$NARGS" -eq 0 ] || die "status takes no arguments"; cmd_status ;;
  set) cmd_set ;;
  show) [ "$NARGS" -eq 1 ] || die "show needs one step id"; cmd_show "$(arg 0)" ;;
  run) [ "$NARGS" -eq 1 ] || die "run needs one step id"; cmd_run "$(arg 0)" ;;
  verify) [ "$NARGS" -eq 1 ] || die "verify needs one step id"; cmd_verify "$(arg 0)" ;;
  record) [ "$NARGS" -eq 2 ] || die "record needs <id> done|declined|not-applicable"; cmd_record "$(arg 0)" "$(arg 1)" ;;
  rollback) [ "$NARGS" -eq 1 ] || die "rollback needs one step id"; cmd_rollback "$(arg 0)" ;;
esac
