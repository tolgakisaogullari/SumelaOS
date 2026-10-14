# shellcheck shell=bash
# sumela-state.sh — the per-developer state directory (v0.20.0+).
#
# One directory per developer per install, shared by the main checkout and every linked
# worktree, never under ~/.claude, never tracked. Tools keep per-developer state there: the
# developer migration ledger, the token-report baselines, notices already shown.
#
#   sumela_state_dir [--create] [--root <install-root>]
#       Prints ${XDG_STATE_HOME:-$HOME/.local/state}/sumela/<key>. On Windows (Git Bash) it
#       prints $(cygpath -u "$LOCALAPPDATA")/sumela/<key>: the directory PowerShell's
#       Get-SumelaStateDir prints as %LOCALAPPDATA%\sumela\<key>. A relative XDG_STATE_HOME is
#       ignored, as the XDG Base Directory specification requires: it would make the directory
#       depend on the working directory. --create makes the directory, mode 0700.
#       Exit 0 printed; 1 no install root, not a git work tree, git refuses the repository (for
#       example "dubious ownership"), git older than 2.31, no sha256 tool, or no base directory;
#       2 usage. Every exit 1 but a missing install root is explained on stderr (git's own message
#       first, when git failed): callers may probe for an install silently.
#   sumela_state_write [--root <install-root>] [--append] <name>     (content on stdin)
#       Writes <state dir>/<name>, mode 0600 inside the 0700 directory. A replace goes through
#       a temporary file in the same directory and a rename; --append appends. <name> is
#       [A-Za-z0-9._-]+ and not "." or "..". Exit 0 written; 1 failed; 2 usage or bad name.
#   sumela_sha256                                                    (stdin -> lowercase hex)
#
# The key (it must agree across bash, PowerShell and Python, so it is exact):
#   <key> = the first 16 hex characters of sha256("<main checkout>/<install prefix>"), where
#   - <main checkout> is `git rev-parse --path-format=absolute --git-common-dir` minus a
#     trailing "/.git", exactly as git prints it (forward slashes on every platform);
#   - <install prefix> is `git rev-parse --show-prefix` run FROM THE INSTALL ROOT, minus its
#     trailing "/". The install root is --root, else the nearest ancestor of the working
#     directory that holds .sumela/. Never the working directory's own prefix: a session in a
#     subdirectory, or in a linked worktree, gets the main checkout's directory [RU-M6].
#   - The string is hashed as UTF-8 bytes, with no newline.
#   Both git calls run with GIT_DIR, GIT_WORK_TREE, GIT_COMMON_DIR, GIT_INDEX_FILE and
#   GIT_PREFIX cleared: a git hook exports them, and they would point git at the hook's
#   repository layout instead of the install root's.
#   scripts/lib/sumela-state.ps1 computes the same key, and so does the token report (Python);
#   tests/test_state_dir.{sh,ps1} hold the three to it.

sumela_sha256() {  # stdin -> lowercase hex sha256 (sha256sum, shasum or openssl, whichever exists)
  if command -v sha256sum >/dev/null 2>&1; then sha256sum
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256
  else openssl dgst -sha256 -r
  fi | cut -d' ' -f1
}

_sumela_state_git() {  # <dir> <git args>... : git for <dir>'s repository, not one a hook's GIT_* names
  ( unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_PREFIX; git -C "$@" )
}

_sumela_state_root() {  # [<root>] -> the install root: <root> as given, else the nearest ancestor holding .sumela/
  local root="${1:-}" parent
  if [ -z "$root" ]; then
    root="$PWD"
    while [ ! -d "$root/.sumela" ]; do
      parent="$(dirname "$root")"
      [ "$parent" = "$root" ] && break        # "/" and "//" (a UNC root in Git Bash) are fixed points
      root="$parent"
    done
  fi
  [ -d "$root/.sumela" ] || return 1
  printf '%s\n' "$root"
}

sumela_state_dir() {  # [--create] [--root <install-root>] -> one directory per developer per install (main + its worktrees)
  local create=false root="" common prefix base key d
  while [ $# -gt 0 ]; do
    case "$1" in
      --create) create=true ;;
      --root)
        [ $# -ge 2 ] || { echo "sumela_state_dir: --root needs a directory" >&2; return 2; }
        root="$2"; shift ;;
      *) echo "sumela_state_dir: unknown argument: $1" >&2; return 2 ;;
    esac
    shift
  done
  root="$(_sumela_state_root "$root")" || return 1
  # git's stderr is not redirected: its reason (and, for "dubious ownership", its fix) is shown.
  if ! common="$(_sumela_state_git "$root" rev-parse --path-format=absolute --git-common-dir)"; then
    echo "sumela_state_dir: git cannot read the repository at $root (git's message is above)" >&2; return 1
  fi
  if ! prefix="$(_sumela_state_git "$root" rev-parse --show-prefix)"; then   # from the INSTALL root [RU-M6]
    echo "sumela_state_dir: git cannot read the repository at $root (git's message is above)" >&2; return 1
  fi
  common="${common%$'\r'}"; prefix="${prefix%$'\r'}"
  # git < 2.31 echoes "--path-format=absolute" back instead of failing: one absolute path or nothing.
  case "$common" in
    *$'\n'*) echo "sumela_state_dir: git printed more than one line for --git-common-dir (git 2.31 or later is required)" >&2; return 1 ;;
    /*|[A-Za-z]:/*) ;;
    *) echo "sumela_state_dir: git printed no absolute path for --git-common-dir ('$common'; git 2.31 or later is required)" >&2; return 1 ;;
  esac
  key="$(printf '%s/%s' "${common%/.git}" "${prefix%/}" | sumela_sha256 | cut -c1-16)" || key=""
  if ! k="$key" LC_ALL=C awk 'BEGIN { k = ENVIRON["k"]; exit !(length(k) == 16 && k ~ /^[0-9a-f]+$/) }'; then
    echo "sumela_state_dir: no sha256 tool (sha256sum, shasum or openssl)" >&2; return 1
  fi
  case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*)
      [ -n "${LOCALAPPDATA:-}" ] || { echo "sumela_state_dir: LOCALAPPDATA is not set" >&2; return 1; }
      base="$(cygpath -u "$LOCALAPPDATA")" || return 1
      base="$base/sumela" ;;
    *)
      base="${XDG_STATE_HOME:-}"
      case "$base" in /*) ;; *) base="" ;; esac
      if [ -z "$base" ]; then
        [ -n "${HOME:-}" ] || { echo "sumela_state_dir: neither XDG_STATE_HOME nor HOME is set" >&2; return 1; }
        base="$HOME/.local/state"
      fi
      base="$base/sumela" ;;
  esac
  d="$base/$key"
  if [ "$create" = true ]; then
    if ( umask 077; mkdir -p "$d" ) && chmod 700 "$d" && [ -d "$d" ]; then :; else
      echo "sumela_state_dir: cannot create $d" >&2; return 1
    fi
  fi
  printf '%s\n' "$d"
}

sumela_state_write() {  # [--root <install-root>] [--append] <name>  (stdin) -> <state dir>/<name>, 0600
  local root="" append=false name="" d tmp
  while [ $# -gt 0 ]; do
    case "$1" in
      --root)
        [ $# -ge 2 ] || { echo "sumela_state_write: --root needs a directory" >&2; return 2; }
        root="$2"; shift ;;
      --append) append=true ;;
      -*) echo "sumela_state_write: unknown option: $1" >&2; return 2 ;;
      *)
        [ -z "$name" ] || { echo "sumela_state_write: one name only" >&2; return 2; }
        name="$1" ;;
    esac
    shift
  done
  # Checked in the C locale: under a UTF-8 locale bash's [A-Za-z] also matches letters such as "ö".
  if ! n="$name" LC_ALL=C awk 'BEGIN { n = ENVIRON["n"]; exit !(n ~ /^[A-Za-z0-9._-]+$/ && n != "." && n != "..") }'; then
    echo "sumela_state_write: invalid name '$name'" >&2; return 2
  fi
  if [ -n "$root" ]; then d="$(sumela_state_dir --create --root "$root")" || return 1
  else d="$(sumela_state_dir --create)" || return 1
  fi
  if [ "$append" = true ]; then
    if ( umask 077; cat >> "$d/$name" ) && chmod 600 "$d/$name"; then :; else
      echo "sumela_state_write: cannot append to $d/$name" >&2; return 1
    fi
  else
    tmp="$d/.$name.sumela-tmp.$$"
    if ( umask 077; cat > "$tmp" ) && chmod 600 "$tmp" && mv -f "$tmp" "$d/$name"; then :; else
      rm -f "$tmp"; echo "sumela_state_write: cannot write $d/$name" >&2; return 1
    fi
  fi
  [ -f "$d/$name" ] || { echo "sumela_state_write: $d/$name is missing after the write" >&2; return 1; }
}
