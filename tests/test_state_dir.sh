#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# tests/test_state_dir.sh — the per-developer state directory (R1-03).
#
# scripts/lib/sumela-state.{sh,ps1} give every developer ONE directory per install:
# ${XDG_STATE_HOME:-~/.local/state}/sumela/<key> (%LOCALAPPDATA%\sumela\<key> on Windows),
# shared by the main checkout and all of its linked worktrees. <key> is the first 16 hex
# characters of sha256("<main checkout>/<install prefix>"), the install prefix taken from the
# INSTALL ROOT, never from the working directory [RU-M6]. The token report computes the same key
# in Python, so the three implementations must agree to the byte; this suite holds bash, the
# PowerShell twin and an independent Python reference to one formula.
#
# Every case builds its own throwaway repositories; nothing outside $WORK is touched (the state
# base is redirected into $WORK). pwsh and python3 are used when present; a missing interpreter
# prints SKIP for the checks that need it.
#
# Run from anywhere:  bash tests/test_state_dir.sh
# Exit 0 = all assertions passed, 1 = a failure (printed above).
# -----------------------------------------------------------------------------
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB="$REPO_ROOT/scripts/lib/sumela-state.sh"
PSLIB="$REPO_ROOT/scripts/lib/sumela-state.ps1"
[ -f "$LIB" ] || { echo "FAIL: $LIB missing"; exit 1; }
# shellcheck source=../scripts/lib/sumela-state.sh
. "$LIB"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
WORK="$(cd "$WORK" && pwd -P)"

PASS=0 FAIL=0
ok()   { echo "  PASS  $1"; PASS=$((PASS + 1)); }
bad()  { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); }
skip() { echo "  SKIP  $1"; }
# same <label> <expected> <got>
same() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }
# has <label> <text> <wanted substring>
has() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 (wanted '$3' in '$2')" ;; esac; }

case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) ON_WINDOWS=true ;; *) ON_WINDOWS=false ;; esac
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_PREFIX
export XDG_STATE_HOME="$WORK/state"
if [ "$ON_WINDOWS" = true ]; then
  mkdir -p "$WORK/localappdata"; LOCALAPPDATA="$(cygpath -w "$WORK/localappdata")"; export LOCALAPPDATA
  BASE="$WORK/localappdata/sumela"
else
  BASE="$XDG_STATE_HOME/sumela"
fi
PWSH="$(command -v pwsh 2>/dev/null || true)"
PY="$(command -v python3 2>/dev/null || true)"

# mkrepo <dir> [<install-subdir>...]: a repository with one commit; .sumela/ at each install
# subdir ("." = the top), and a nested src/deep under each install.
mkrepo() {
  local d="$1" i; shift
  mkdir -p "$d" && git -C "$d" init -q -b main
  git -C "$d" config user.email t@example.com; git -C "$d" config user.name Test
  [ $# -gt 0 ] || set -- .
  for i in "$@"; do
    mkdir -p "$d/$i/.sumela" "$d/$i/src/deep"
    echo 0.20.0 > "$d/$i/.sumela/VERSION"; echo x > "$d/$i/src/deep/f.txt"
  done
  git -C "$d" add -A && git -C "$d" commit -qm init
}
# formula_key <install-root>: the contract, written out independently of the library
formula_key() {
  local common prefix
  common="$(git -C "$1" rev-parse --path-format=absolute --git-common-dir)"
  prefix="$(git -C "$1" rev-parse --show-prefix)"
  printf '%s/%s' "${common%/.git}" "${prefix%/}" | sumela_sha256 | cut -c1-16
}
# key_of <dir> [args...]: the key the bash library prints when run from <dir>
key_of() { local d; d="$(cd "$1" && shift && sumela_state_dir "$@")" && basename "$d"; }
dir_of() { (cd "$1" && shift && sumela_state_dir "$@"); }
mode_of() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }

MAIN="$WORK/main"; mkrepo "$MAIN"
git -C "$MAIN" worktree add -q -b topic "$WORK/wt" >/dev/null 2>&1
MONO="$WORK/mono"; mkrepo "$MONO" svc/a svc/b
UNI="$WORK/ö ş dir"; mkrepo "$UNI"

echo "== t_main_and_worktree_share_dir"
k_main="$(key_of "$MAIN")"; k_wt="$(key_of "$WORK/wt")"
same "the main checkout's key follows the formula" "$(formula_key "$MAIN")" "$k_main"
same "a linked worktree gets the main checkout's key" "$k_main" "$k_wt"
same "the directory is <base>/sumela/<key>" "$BASE/$k_main" "$(dir_of "$WORK/wt")"
case "$k_main" in [0-9a-f]*) if [ "${#k_main}" -eq 16 ] && [ -z "$(printf '%s' "$k_main" | tr -d '0-9a-f')" ]; then ok "the key is 16 lowercase hex characters"; else bad "the key is 16 lowercase hex characters (got '$k_main')"; fi ;; *) bad "the key is 16 lowercase hex characters (got '$k_main')" ;; esac

echo "== t_monorepo_prefix_distinct"
k_a="$(key_of "$MONO/svc/a")"; k_b="$(key_of "$MONO/svc/b")"
if [ -n "$k_a" ] && [ -n "$k_b" ] && [ "$k_a" != "$k_b" ]; then ok "two installs in one repository get two directories"; else bad "two installs in one repository get two directories ($k_a / $k_b)"; fi
same "an install in a subdirectory hashes <main>/<prefix>" "$(formula_key "$MONO/svc/a")" "$k_a"
expect_a="$(printf '%s/%s' "$(git -C "$MONO" rev-parse --path-format=absolute --git-common-dir | sed 's#/\.git$##')" "svc/a" | sumela_sha256 | cut -c1-16)"
same "the prefix is the install's own (svc/a), with no trailing slash" "$expect_a" "$k_a"

echo "== t_subdirectory_cwd_same_key"
same "a session in a subdirectory of the install" "$k_main" "$(key_of "$MAIN/src/deep")"
same "a session in a subdirectory of a linked worktree" "$k_main" "$(key_of "$WORK/wt/src/deep")"
same "a session deep inside a monorepo install keeps the install's prefix" "$k_a" "$(key_of "$MONO/svc/a/src/deep")"
same "--root names the install from anywhere" "$k_main" "$(key_of / --root "$MAIN")"
same "--root may name a linked worktree" "$k_main" "$(key_of / --root "$WORK/wt")"

echo "== t_mode_0700_files_0600"
if [ "$ON_WINDOWS" = true ]; then
  skip "POSIX modes (Windows: %LOCALAPPDATA% is per-user)"
else
  d="$( (umask 022; cd "$MAIN" && sumela_state_dir --create) )"
  same "--create makes the directory 0700 under a 022 umask" 700 "$(mode_of "$d")"
  chmod 755 "$d"; (cd "$MAIN" && sumela_state_dir --create >/dev/null)
  same "--create tightens an existing 0755 directory to 0700" 700 "$(mode_of "$d")"
  (umask 022; cd "$MAIN" && printf 'one\n' | sumela_state_write note.txt)
  same "sumela_state_write creates its file 0600" 600 "$(mode_of "$d/note.txt")"
  (umask 022; cd "$WORK/wt" && printf 'two\n' | sumela_state_write note.txt)
  same "a replace from a worktree writes the shared file" "two" "$(cat "$d/note.txt")"
  same "…and keeps it 0600" 600 "$(mode_of "$d/note.txt")"
  (umask 022; cd "$MAIN" && printf 'a\n' | sumela_state_write --append log && printf 'b\n' | sumela_state_write --append log)
  same "--append appends" "$(printf 'a\nb')" "$(cat "$d/log")"
  same "--append creates its file 0600" 600 "$(mode_of "$d/log")"
  left=""; for f in "$d"/.*sumela-tmp* "$d"/*sumela-tmp*; do [ -e "$f" ] && left="$f"; done
  if [ -n "$left" ]; then bad "no temporary file is left behind ($left)"; else ok "no temporary file is left behind"; fi
fi
for n in ../x a/b . .. '' 'a b'; do
  (cd "$MAIN" && printf 'x' | sumela_state_write "$n" 2>/dev/null); rc=$?
  same "an invalid name is refused (exit 2): '$n'" 2 "$rc"
done
# Under a UTF-8 locale bash's [A-Za-z] also matches "ö"; the check must stay byte-based, as in
# the PowerShell twin, so a name means the same in both shells.
UTF8_LOCALE="$(locale -a 2>/dev/null | LC_ALL=C grep -E '^(en_US|de_DE|tr_TR)\.(UTF-8|utf8)$' | head -1)"
if [ -n "$UTF8_LOCALE" ]; then
  # A child shell started under the locale: a temporary LC_ALL= on a function call does not
  # make bash re-read its locale.
  (cd "$MAIN" && printf 'x' | LC_ALL="$UTF8_LOCALE" bash -c '. "$1"; sumela_state_write "ö.txt"' _ "$LIB" 2>/dev/null); rc=$?
  same "a non-ASCII name is refused under $UTF8_LOCALE too (exit 2)" 2 "$rc"
else
  skip "non-ASCII name under a UTF-8 locale: none installed"
fi

echo "== t_bash_ps_python_same_key"
for case_dir in "$MAIN" "$WORK/wt/src/deep" "$MONO/svc/a/src/deep" "$UNI/src"; do
  label="${case_dir#"$WORK"/}"
  k_bash="$(key_of "$case_dir")"
  if [ -n "$PWSH" ]; then
    ps_dir="$(cd "$case_dir" && t_lib="$PSLIB" "$PWSH" -NoProfile -NonInteractive -Command '. $env:t_lib; Get-SumelaStateDir' 2>&1)"
    if [ "$ON_WINDOWS" = true ]; then ps_dir="$(cygpath -u "$ps_dir")"; fi
    same "PowerShell prints bash's directory ($label)" "$(dir_of "$case_dir")" "$ps_dir"
  else
    skip "PowerShell key ($label): pwsh unavailable"
  fi
  if [ -n "$PY" ]; then
    root="$(cd "$case_dir" && _sumela_state_root)"
    k_py="$("$PY" -I - "$root" <<'PY'
import hashlib, os, subprocess, sys
root = sys.argv[1]
env = {k: v for k, v in os.environ.items()
       if k not in ("GIT_DIR", "GIT_WORK_TREE", "GIT_COMMON_DIR", "GIT_INDEX_FILE", "GIT_PREFIX")}
def git(*args):
    out = subprocess.run(["git", "-C", root, *args], capture_output=True, check=True, env=env).stdout
    return out.decode("utf-8").rstrip("\r\n")
common = git("rev-parse", "--path-format=absolute", "--git-common-dir")
prefix = git("rev-parse", "--show-prefix")
if common.endswith("/.git"):
    common = common[:-len("/.git")]
if prefix.endswith("/"):
    prefix = prefix[:-1]
print(hashlib.sha256((common + "/" + prefix).encode("utf-8")).hexdigest()[:16])
PY
)"
    same "a Python reference computes bash's key ($label)" "$k_bash" "$k_py"
  else
    skip "Python key ($label): python3 unavailable"
  fi
done

echo "== t_no_install_root_fails"
mkdir -p "$WORK/plain/sub"
out="$(cd "$WORK/plain/sub" && sumela_state_dir 2>/dev/null)"; rc=$?
same "no .sumela/ above the working directory: exit 1" 1 "$rc"
same "…and nothing printed" "" "$out"
(cd / && sumela_state_dir --root "$WORK/plain" >/dev/null 2>&1); same "--root without .sumela/: exit 1" 1 "$?"
mkdir -p "$WORK/nogit/.sumela"
(cd "$WORK/nogit" && sumela_state_dir >/dev/null 2>&1); same "an install outside any git work tree: exit 1" 1 "$?"
err="$(cd "$WORK/nogit" && sumela_state_dir 2>&1 >/dev/null)"
has "…and stderr says git cannot read the repository" "$err" "sumela_state_dir: git cannot read the repository at $WORK/nogit"
same "…after git's own message (two lines or more)" yes "$([ "$(printf '%s\n' "$err" | wc -l | tr -d ' ')" -ge 2 ] && echo yes)"
same "no install root is not reported: callers probe for one" "" "$(cd "$WORK/plain/sub" && sumela_state_dir 2>&1 >/dev/null)"
(cd "$MAIN" && sumela_state_dir --bogus >/dev/null 2>&1); same "an unknown argument: exit 2" 2 "$?"

echo "== t_git_refusal_reported"
# git refuses a repository another user owns ("dubious ownership", common on shares and in CI
# containers): the state directory must say why it has no answer, never exit 1 silently.
refuse() { GIT_TEST_ASSUME_DIFFERENT_OWNER=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 "$@"; }
if (cd "$MAIN" && refuse git rev-parse --git-dir >/dev/null 2>&1); then
  skip "this git does not refuse a repository owned by another user (git 2.35.2 or later does)"
else
  out="$(cd "$MAIN" && refuse sumela_state_dir 2> "$WORK/refuse.err")"; rc=$?
  same "a repository git refuses: exit 1, nothing printed" "1:" "$rc:$out"
  err="$(cat "$WORK/refuse.err")"
  has "…stderr says git cannot read the repository" "$err" "sumela_state_dir: git cannot read the repository at $MAIN"
  same "…after git's own message (two lines or more)" yes "$([ "$(printf '%s\n' "$err" | wc -l | tr -d ' ')" -ge 2 ] && echo yes)"
  (cd "$MAIN" && printf x | refuse sumela_state_write r.txt 2> "$WORK/refuse.err"); rc=$?
  same "sumela_state_write: exit 1" 1 "$rc"
  has "…naming the reason" "$(cat "$WORK/refuse.err")" "git cannot read the repository"
fi

echo "== t_base_directory_rules"
if [ "$ON_WINDOWS" = true ]; then
  skip "XDG rules (Windows uses LOCALAPPDATA)"
else
  got="$(cd "$MAIN" && XDG_STATE_HOME="$WORK/x2" sumela_state_dir)"
  same "XDG_STATE_HOME is honoured" "$WORK/x2/sumela/$k_main" "$got"
  got="$(cd "$MAIN" && env -u XDG_STATE_HOME HOME="$WORK/home" bash -c '. "$1"; sumela_state_dir' _ "$LIB")"
  same "without XDG_STATE_HOME: \$HOME/.local/state" "$WORK/home/.local/state/sumela/$k_main" "$got"
  got="$(cd "$MAIN" && XDG_STATE_HOME="relative/dir" HOME="$WORK/home" sumela_state_dir)"
  same "a relative XDG_STATE_HOME is ignored (it would follow the working directory)" "$WORK/home/.local/state/sumela/$k_main" "$got"
fi

echo "== t_hook_environment_ignored"
# A git hook exports GIT_DIR (and sometimes GIT_WORK_TREE). With GIT_DIR set and no work tree,
# git takes the working directory as the top, so --show-prefix of a monorepo install would be
# empty; the library clears the hook variables for its own git calls.
got="$(cd "$MONO" && GIT_DIR="$MONO/.git" sumela_state_dir --root "$MONO/svc/a" 2>/dev/null)"
same "GIT_DIR from a hook does not change a monorepo install's key" "$k_a" "$(basename "${got:-none}")"
got="$(cd "$WORK/wt" && GIT_DIR="$MAIN/.git/worktrees/wt" GIT_WORK_TREE="$WORK/wt" sumela_state_dir 2>/dev/null)"
same "a worktree hook's GIT_DIR/GIT_WORK_TREE do not change the key" "$k_main" "$(basename "${got:-none}")"

echo "== t_errexit_callers"
# Callers may run under set -euo pipefail: a failing test inside the library must never end
# the caller's shell, and a missing install is reported by the exit status.
out="$(cd "$MAIN" && bash -euo pipefail -c '. "$1"; d="$(sumela_state_dir --create)"
  printf x | sumela_state_write n.txt; sumela_state_write --append n.log < /dev/null; echo "ok:${d##*/}"' _ "$LIB" 2>&1)"
same "the library works for a caller under set -euo pipefail" "ok:$k_main" "$out"
out="$(cd "$WORK/plain" && bash -euo pipefail -c '. "$1"; if d="$(sumela_state_dir)"; then echo "dir:$d"; else echo "none:$?"; fi' _ "$LIB" 2>&1)"
same "…and reports a missing install by its exit status" "none:1" "$out"

echo "== t_old_git_output_refused"
# git < 2.31 does not know --path-format and echoes it back as a second line; that must never
# become a key (a different key would split one developer's state in two).
out="$(cd "$MAIN" && git() { if [ "${3:-}" = rev-parse ] && [ "${4:-}" = --path-format=absolute ]; then printf '%s\n%s\n' --path-format=absolute .git; else command git "$@"; fi; }
       sumela_state_dir 2> "$WORK/oldgit.err")"; rc=$?
same "a two-line --git-common-dir answer: exit 1" 1 "$rc"
same "…and nothing printed" "" "$out"
has "…and stderr names the git it needs" "$(cat "$WORK/oldgit.err")" "git 2.31 or later is required"

echo
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
