# shellcheck shell=bash
# sumela-provenance.sh — the provenance record, .sumela/.last-update.json (v0.20.0+).
#
# The self-modification guard (requesting-code-review/self-modification-guard.md) trusts ONE
# array of this record: "files", content the developer did not write — vendored by the updater,
# or written by a framework tool (registry sync, migration ledgers). Merged and theirs-over-fork
# paths are NEVER in "files", so their diffs are reviewed as authored. The other keys serve the
# updater and status.
#
# Layout v2. Both shells write exactly these bytes: LF, UTF-8 without BOM, every array sorted by
# bytes with each path once, a path in at most one of files/merged/kept/theirs_over_fork/removed.
#   {
#     "updater_schema": 2,
#     "version": "0.20.0",
#     "base_version": "0.19.0",
#     "upstream_commit": "<hex, or empty>",
#     "updated_at": "2026-10-14T12:00:00Z",
#     "pending_rerun": false,
#     "partial_upgrade": false,
#     "files": [
#       "<path>",
#       "<path>"
#     ],
#     "merged": ["<path>"],
#     "kept": [{"path": "<path>", "why": "fork"}],
#     "theirs_over_fork": [],
#     "removed": []
#   }
# "files" is the only multi-line array; the others are one line each, so a path in another array
# can never leak into "files" on a later pass. "kept" reasons: fork, conflict:local,
# removed-upstream, declined, updater-floor. "files" is read only as an array of strings: any
# other shape vouches for nothing.
#
# Two more one-line members say what a later write may carry into "files" (see below). An
# unfinished run's write puts them after "removed"; add_files replaces them, or appends them.
#     "carry_head": "<the HEAD commit the entries were recorded at; empty on an unborn branch>",
#     "carry": ["<blob> <path>"]
# <blob> is `git hash-object --no-filters <path>` when the entry was recorded, "-" when the path
# was not a regular file then. A finished run's write leaves both out.
#
# <record> defaults to <install root>/.sumela/.last-update.json, the install root being the
# nearest ancestor of the working directory that holds .sumela/. Pass it whenever you write for
# another checkout (for example an upgrade worktree). git runs in the record's install root,
# the directory above its .sumela/.
#
#   sumela_record_path [<install-root>]
#       Prints the record path. Exit 1 when there is no install root.
#   sumela_record_get <key> [<record>]
#       Prints one value: a string unquoted, a number or boolean as written, an array one element
#       per line ("kept": <path><TAB><why>). "files" is read as sumela_record_files reads it.
#       Exit 0; 1 record or key absent; 2 bad key; 3 record unreadable (nothing printed).
#   sumela_record_files [<record>]
#       Prints the "files" array only, one path per line. Always exit 0: no record, an
#       unreadable one, or a "files" that is not an array of strings (both named on stderr)
#       vouches for nothing.
#   sumela_record_add_files [--record <record>] <path>...
#       Call it right after a framework tool wrote the paths. Adds them to "files" (deduplicated)
#       and to "carry" with their content, keeping every other key and value as it is: a
#       pre-0.20 (v1) record stays v1, so it never starts vouching. With no record, writes a
#       minimal one ("files" and the carry members) that vouches for nothing until the updater
#       writes the run's record. When git cannot read the install, the paths still go into
#       "files", "carry" is left as it was, and stderr says why the next write will not carry
#       them. Exit 0 written and re-read (or already there); 1 write failed; 2 path refused;
#       3 record unreadable, or its "files" is not an array of strings (left unchanged).
#   sumela_record_write <version> complete|partial [--pending-rerun] [--base-version <v>]
#         [--upstream-commit <hex>] [--files <list>] [--merged <list>] [--kept <list>]
#         [--theirs-over-fork <list>] [--removed <list>] [--record <record>]
#       The updater's write. Each <list> is newline-separated; a --kept row is <path><TAB><why>.
#       "partial" sets partial_upgrade, --pending-rerun sets pending_rerun; such an unfinished
#       run's record lists its own "files" in "carry", for the write that completes the run.
#       The updater passes --upstream-commit, its release's commit, on every complete write.
#       Exit 0 written and re-read; 1 write failed; 2 input refused (the record is left
#       unchanged). A path that is not carried because git failed or because it changed after it
#       was recorded is named on stderr.
#
# What sumela_record_write keeps from the record it replaces [RU-M4] (a path this write
# classifies anew always takes its new class):
#   - "files": each "carry" entry, only while HEAD is still "carry_head" and the path is still a
#     regular file, uncommitted against HEAD (modified, staged or untracked), with the content
#     that was recorded. That keeps what this run's tools wrote (registry sync and the
#     pre-update migration ledgers add theirs before the updater writes) and a partial or
#     two-pass run's files when the run completes. Nothing else is carried: not "files" as such,
#     not a path an earlier run vendored or a tool wrote and the developer then committed (HEAD
#     moved), not a path edited after it was recorded (its content changed), not a pre-0.20
#     record's files. A file written once must never vouch for a later hand edit.
#   - merged, kept, theirs_over_fork, removed, and base_version when not given: from an
#     unfinished run's record only.
#   - upstream_commit when not given: from an unfinished run's record of this write's version
#     only (it is that version's release commit); otherwise it is left empty.
#
# Refused: a path that is empty or holds '"', '\' or a control character; a version outside
# [0-9A-Za-z][0-9A-Za-z.+-]*; an upstream commit that is not lowercase hex; a version, base
# version or upstream commit holding a line break; a "why" outside [a-z][a-z0-9:-]*; one path
# given two classifications in the same write.

_sumela_rec_git() {  # <dir> <git args>... : git for <dir>'s repository, not one a hook's GIT_* names
  ( unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_PREFIX; git -C "$@" )
}

_sumela_rec_root() {  # [<root>] -> the install root: <root> as given, else the nearest ancestor holding .sumela/
  local root="${1:-}" parent
  if [ -z "$root" ]; then
    root="$PWD"
    while [ ! -d "$root/.sumela" ]; do
      parent="$(dirname "$root")"
      [ "$parent" = "$root" ] && break
      root="$parent"
    done
  fi
  [ -d "$root/.sumela" ] || return 1
  printf '%s\n' "$root"
}

# shellcheck disable=SC2120  # an optional argument: most callers use the default
sumela_record_path() {  # [<install-root>] -> <install root>/.sumela/.last-update.json
  local root
  root="$(_sumela_rec_root "${1:-}")" || return 1
  printf '%s/.sumela/.last-update.json\n' "$root"
}

_sumela_rec_awklib() {  # awk functions shared by the readers and writers below
  cat <<'AWK'
# arr(raw, out, kind): split a one-line JSON array into out[1..n]. kind "s": strings;
# kind "o": {"path": ..., "why": ...} objects, as "<path>\t<why>". Returns n, or -1 for any
# other shape. Elements hold no '"' (refused on write), so splitting on '"' is exact.
function arr(raw, out, kind,    q, n, m, j) {
  if (raw == "[]") return 0
  n = split(raw, q, "\"")
  m = 0
  if (kind == "s") {
    if (n < 3 || n % 2 == 0 || q[1] != "[") return -1
    for (j = 2; j < n; j += 2) {
      if (q[j + 1] != ((j + 1 == n) ? "]" : ", ")) return -1
      out[++m] = q[j]
    }
    return m
  }
  if (n < 9 || (n - 1) % 8 != 0 || q[1] != "[{") return -1
  for (j = 1; j < n; j += 8) {
    if (q[j + 1] != "path" || q[j + 2] != ": " || q[j + 4] != ", " || q[j + 5] != "why" || q[j + 6] != ": ") return -1
    if (q[j + 8] != ((j + 8 == n) ? "}]" : "}, {")) return -1
    out[++m] = q[j + 3] "\t" q[j + 7]
  }
  return m
}
function strarr(a, n,    s, j) {
  s = "["
  for (j = 1; j <= n; j++) s = s ((j > 1) ? ", " : "") "\"" a[j] "\""
  return s "]"
}
AWK
}

_sumela_rec_parse() {  # <record> -> rows "k<TAB>key<TAB>raw" | "b<TAB>key" | "e<TAB>key<TAB>element", in order; exit 3 unreadable
  LC_ALL=C awk '
    function fail(msg) { if (!failed) printf "sumela-provenance: %s: line %d: %s\n", FILENAME, FNR, msg > "/dev/stderr"; failed = 1; exit 3 }
    {
      l = $0
      if (FNR == 1 && substr(l, 1, 3) == "\357\273\277") l = substr(l, 4)     # a BOM (v0.19 on Windows PowerShell 5.1)
      sub(/\r$/, "", l)
      if (l ~ /^[ \t]*$/) next                       # v0.19 PowerShell wrote a blank line in an empty "files"
      if (l ~ /[[:cntrl:]]/) fail("control character")
      if (st == 0) { if (l == "{") { st = 1; next }; fail("expected {") }
      if (st == 3) fail("text after the closing }")
      if (st == 2) {
        if (l ~ /^  \],?$/) { st = 1; next }
        if (l ~ /^    "[^"\\]*",?$/) { v = l; sub(/^    "/, "", v); sub(/",?$/, "", v); print "e\t" key "\t" v; next }
        fail("not an array element")
      }
      if (l == "}") { st = 3; next }
      if (l !~ /^  "[a-z_][a-z0-9_]*": /) fail("not a member line")
      key = substr(l, 4); key = substr(key, 1, index(key, "\"") - 1)
      if (key in seen) fail("duplicate key " key)
      seen[key] = 1
      raw = substr(l, length(key) + 7)
      if (raw == "[") { print "b\t" key; st = 2; next }
      sub(/,$/, "", raw)
      if (raw == "") fail("empty value")
      print "k\t" key "\t" raw
    }
    END { if (failed) exit 3; if (st != 3) { printf "sumela-provenance: %s: no closing }\n", FILENAME > "/dev/stderr"; exit 3 } }
  ' "$1"
}

_sumela_rec_values() {  # <key> [<shape>] < rows -> the value(s) of <key>; exit 1 absent, 4 another shape (nothing printed)
  # <shape>: empty prints any value as sumela_record_get does; "s" only an array of strings
  # (multi-line or one-line); "o" only an array of kept objects; "str" only a string, unquoted;
  # "raw" only a number or boolean, as written. An array that is neither strings nor kept
  # objects prints nothing in any shape: an unexpected shape never turns into a path.
  LC_ALL=C awk -F '\t' -v want="$1" -v shape="${2:-}" "$(_sumela_rec_awklib)"'
    $2 != want { next }
    $1 == "b" { found = 1; if (shape != "" && shape != "s") bad = 1; next }
    $1 == "e" { if (!bad && length($3)) print $3; next }
    $1 == "k" {
      found = 1; raw = $3
      if (raw ~ /^"[^"\\]*"$/) {
        if (shape == "" || shape == "str") print substr(raw, 2, length(raw) - 2); else bad = 1
        next
      }
      if (substr(raw, 1, 1) == "[") {
        n = -1
        if (shape == "" || shape == "s") n = arr(raw, out, "s")
        if (n < 0 && (shape == "" || shape == "o")) n = arr(raw, out, "o")
        if (n < 0) { if (shape != "") bad = 1; next }
        for (i = 1; i <= n; i++) if (length(out[i])) print out[i]
        next
      }
      if (shape == "" || shape == "raw") print raw; else bad = 1
    }
    END { if (!found) exit 1; if (bad) exit 4; exit 0 }'
}

sumela_record_get() {  # <key> [<record>]
  local key="${1:-}" rec="${2:-}" rows
  # Checked in the C locale: under a UTF-8 locale bash's [a-z] also matches letters such as "é".
  if ! k="$key" LC_ALL=C awk 'BEGIN { exit !(ENVIRON["k"] ~ /^[a-z0-9_]+$/) }'; then
    echo "sumela_record_get: invalid key '$key'" >&2; return 2
  fi
  [ -n "$rec" ] || rec="$(sumela_record_path)" || return 1
  [ -f "$rec" ] || return 1
  if [ "$key" = files ]; then                     # the guard's array: never anything but strings
    rows="$(_sumela_rec_parse "$rec")" || return 3
    printf '%s\n' "$rows" | _sumela_rec_values files >/dev/null || return 1
    sumela_record_files "$rec"
    return 0
  fi
  rows="$(_sumela_rec_parse "$rec")" || return 3
  printf '%s\n' "$rows" | _sumela_rec_values "$key"
}

sumela_record_files() {  # [<record>] -> the "files" array only: the one array the self-modification guard trusts
  local rec="${1:-}" rows rc
  [ -n "$rec" ] || rec="$(sumela_record_path)" || return 0
  [ -f "$rec" ] || return 0
  rows="$(_sumela_rec_parse "$rec")" || return 0
  rc=0; printf '%s\n' "$rows" | _sumela_rec_values files s || rc=$?
  if [ "$rc" -eq 4 ]; then echo "sumela-provenance: $rec: \"files\" is not an array of strings; it vouches for nothing" >&2; fi
  return 0
}

_sumela_rec_check() {  # < rows "<kind><TAB><value>" -> exit 2 naming the first refused value
  # A TAB inside a value shows up as a third field; it is refused like any control character.
  LC_ALL=C awk -F '\t' '
    function no(msg) { printf "sumela-provenance: refused %s: \"%s\"\n", msg, substr($0, length($1) + 2) > "/dev/stderr"; bad = 1; exit 2 }
    NF > 2           { no($1 " (holds a TAB)") }
    $1 == "path"     { if ($2 == "" || $2 ~ /[[:cntrl:]"\\]/) no("path (empty, or holds a quote, a backslash or a control character)"); next }
    $1 == "version"  { if ($2 !~ /^[0-9A-Za-z][0-9A-Za-z.+-]*$/) no("version"); next }
    $1 == "base"     { if ($2 != "" && $2 !~ /^[0-9A-Za-z][0-9A-Za-z.+-]*$/) no("base version"); next }
    $1 == "commit"   { if ($2 !~ /^[0-9a-f]*$/) no("upstream commit (lowercase hex)"); next }
    $1 == "why"      { if ($2 !~ /^[a-z][a-z0-9:-]*$/) no("kept reason"); next }
    { no("row") }
    END { if (bad) exit 2 }'
}

_sumela_rec_commit() {  # <rendered> <record>: a temp file beside the record, then a rename
  local tmp="$2.sumela-tmp.$$"
  if cp "$1" "$tmp" && mv -f "$tmp" "$2"; then return 0; fi
  rm -f "$tmp"
  echo "sumela-provenance: cannot write $2" >&2
  return 1
}

# --- git's view of the install, for the carry -----------------------------------------------
# Each helper takes the install root and a scratch directory. On a git failure it exits 1 with
# git's stderr in <tmpdir>/git.err; _sumela_rec_errline turns that into one line for a message.

_sumela_rec_errline() {  # <file> -> its first non-blank line, CR dropped
  LC_ALL=C awk '{ sub(/\r$/, "") } /[^ \t]/ { print; found = 1; exit } END { if (!found) print "git gave no reason" }' "$1"
}

_sumela_rec_head() {  # <root> <tmpdir> -> HEAD's commit, or an empty line on an unborn branch
  local out rc
  : > "$2/git.err"
  out="$(_sumela_rec_git "$1" rev-parse --verify -q HEAD 2>"$2/git.err")"; rc=$?
  out="${out%$'\r'}"
  case "$rc" in
    0) case "$out" in ''|*[!0-9a-f]*) echo "git rev-parse printed an unexpected HEAD: $out" > "$2/git.err"; return 1 ;; esac ;;
    1) if [ -n "$out" ] || [ -s "$2/git.err" ]; then return 1; fi ;;    # --verify -q: an unborn branch, silently
    *) return 1 ;;
  esac
  printf '%s\n' "$out"
}

_sumela_rec_dirty() {  # <root> <tmpdir> <list-file> -> the listed paths that are present and uncommitted against HEAD
  local root="$1" t="$2" list="$3" prefix p
  : > "$t/git.err"
  [ -s "$list" ] || return 0
  prefix="$(_sumela_rec_git "$root" rev-parse --show-prefix 2>"$t/git.err")" || return 1
  prefix="${prefix%$'\r'}"
  # The pathspecs are the paths' top-level names, a handful however long the list: a command
  # line of hundreds of paths would pass Windows' 32K limit.
  set --
  while IFS= read -r p; do if [ -n "$p" ]; then set -- "$@" "$p"; fi; done <<EOF
$(LC_ALL=C awk -F/ 'length($1) { print $1 }' "$list" | LC_ALL=C sort -u)
EOF
  [ $# -gt 0 ] || return 0
  # -z: no quoting of unusual names. A line break inside a listed name becomes \001, so a name
  # can never pose as another entry. Porcelain paths are relative to the repository top: the
  # install prefix is cut, and only paths that were asked about are printed.
  _sumela_rec_git "$root" --no-optional-locks --literal-pathspecs status --porcelain=v1 -z \
      --no-renames --untracked-files=all -- "$@" > "$t/status" 2>"$t/git.err" || return 1
  tr '\n\000' '\001\n' < "$t/status" |
    pre="$prefix" LC_ALL=C awk 'FNR == NR { want[$0] = 1; next }
      { p = substr($0, 4); pre = ENVIRON["pre"]
        if (pre != "" && substr(p, 1, length(pre)) == pre) p = substr(p, length(pre) + 1)
        if ((p in want) && !(p in done)) { done[p] = 1; print p } }' "$list" - |
    while IFS= read -r p; do if [ -f "$root/$p" ]; then printf '%s\n' "$p"; fi; done
  return 0
}

_sumela_rec_blobs() {  # <root> <tmpdir> <list-file> -> "<path><TAB><blob>" per listed path, "-" when it is not a regular file
  local root="$1" t="$2" list="$3" p n=0
  : > "$t/git.err"; : > "$t/hash.paths"; : > "$t/hash.out"
  # On the command line, in chunks well under Windows' 32K limit: --stdin-paths would resolve
  # the paths from the repository top, not from a monorepo install's root.
  set --
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if [ ! -f "$root/$p" ]; then printf '%s\t-\n' "$p"; continue; fi
    printf '%s\n' "$p" >> "$t/hash.paths"
    set -- "$@" "$p"; n=$((n + ${#p} + 1))
    if [ "$n" -ge 8000 ]; then
      _sumela_rec_git "$root" hash-object --no-filters -- "$@" >> "$t/hash.out" 2>"$t/git.err" || return 1
      set --; n=0
    fi
  done < "$list"
  if [ $# -gt 0 ]; then
    _sumela_rec_git "$root" hash-object --no-filters -- "$@" >> "$t/hash.out" 2>"$t/git.err" || return 1
  fi
  [ -s "$t/hash.paths" ] || return 0
  # One blob per path, in order; anything else is an answer we cannot trust. (The file name goes
  # through the environment: awk -v would interpret backslashes in it.)
  if ! out="$t/hash.out" LC_ALL=C awk 'BEGIN { out = ENVIRON["out"] }
      { if ((getline b < out) <= 0) { bad = 1; exit }; sub(/\r$/, "", b)
        if (b !~ /^[0-9a-f]+$/) { bad = 1; exit }; print $0 "\t" b }
      END { if (!bad && (getline b < out) > 0) bad = 1; exit bad }' "$t/hash.paths"; then
    echo "git hash-object printed an unexpected answer" > "$t/git.err"; return 1
  fi
}

_sumela_rec_carry_entries() {  # <caller> <rows-file> -> "<path><TAB><blob>" per valid "carry" entry, in the record's order
  { _sumela_rec_values carry s < "$2" || true; } | LC_ALL=C awk -v who="$1" '{
      b = ""; p = ""
      if (match($0, /^([0-9a-f]+|-) /)) { b = substr($0, 1, RLENGTH - 1); p = substr($0, RLENGTH + 1) }
      if (b == "" || p == "" || p ~ /[[:cntrl:]"\\]/ || (p in seen)) {
        printf "%s: dropped an invalid carry entry: %s\n", who, $0 > "/dev/stderr"; next
      }
      seen[p] = 1; print p "\t" b }'
}

sumela_record_add_files() {  # [--record <record>] <path>... -> add to "files" and to "carry" (see the header)
  local rec="" p t rc
  while [ $# -gt 0 ]; do
    case "$1" in
      --record)
        [ $# -ge 2 ] || { echo "sumela_record_add_files: --record needs a file" >&2; return 2; }
        rec="$2"; shift 2 ;;
      --) shift; break ;;
      *) break ;;
    esac
  done
  [ $# -gt 0 ] || { echo "sumela_record_add_files: no path given" >&2; return 2; }
  for p in "$@"; do
    case "$p" in *$'\n'*|*$'\r'*) echo "sumela-provenance: refused path (a line break)" >&2; return 2 ;; esac
  done
  printf 'path\t%s\n' "$@" | _sumela_rec_check || return 2
  if [ -z "$rec" ]; then
    rec="$(sumela_record_path)" || { echo "sumela_record_add_files: no install root (.sumela/) above $PWD; pass --record" >&2; return 1; }
  fi
  t="$(mktemp -d)" || return 1
  printf '%s\n' "$@" | LC_ALL=C sort -u > "$t/new"
  rc=0; _sumela_rec_add_in "$t" "$rec" || rc=$?
  rm -rf "$t"
  return "$rc"
}

_sumela_rec_add_in() {  # <tmpdir> <record>
  local t="$1" rec="$2" root head="" old_head git_ok=false p rc
  if [ -f "$rec" ]; then
    _sumela_rec_parse "$rec" > "$t/rows" || { echo "sumela_record_add_files: $rec is unreadable; left unchanged" >&2; return 3; }
    rc=0; _sumela_rec_values files s < "$t/rows" > "$t/files.old" || rc=$?
    if [ "$rc" -ne 0 ]; then
      echo "sumela_record_add_files: $rec has no \"files\" array of strings; left unchanged" >&2; return 3
    fi
  else
    : > "$t/rows"; : > "$t/files.old"
  fi
  LC_ALL=C sort -u "$t/files.old" "$t/new" > "$t/files"
  # The carry entries: this HEAD, and the content the tool just wrote. Entries recorded at
  # another HEAD belong to a finished run and are dropped; a path added again takes its new blob.
  root="$(dirname "$(dirname "$rec")")"
  : > "$t/carry"
  if head="$(_sumela_rec_head "$root" "$t")" && _sumela_rec_blobs "$root" "$t" "$t/new" > "$t/new.blobs"; then
    git_ok=true
    : > "$t/carry.old"
    if old_head="$(_sumela_rec_values carry_head str < "$t/rows")" && [ "$old_head" = "$head" ]; then
      _sumela_rec_carry_entries sumela_record_add_files "$t/rows" > "$t/carry.old"
    fi
    LC_ALL=C awk -F '\t' 'FILENAME == ARGV[1] { n[$1] = $2; next } !($1 in n) { print } END { for (p in n) print p "\t" n[p] }' \
      "$t/new.blobs" "$t/carry.old" | LC_ALL=C sort > "$t/carry"
  else
    echo "sumela_record_add_files: cannot read the git state of $root ($(_sumela_rec_errline "$t/git.err")); the path(s) are in \"files\", but the next write will not carry them" >&2
  fi
  # Re-render member by member in the record's own order: unknown keys and values are kept as
  # written, "files" gets the new list; with git's answer, "carry_head" and "carry" are replaced
  # (or appended last, in that order).
  hd="$head" gitok="$git_ok" LC_ALL=C awk "$(_sumela_rec_awklib)"'
    FILENAME == ARGV[1] {
      split($0, f, "\t")
      if (f[1] == "k") { nm++; mk[nm] = f[2]; mt[nm] = "k"; mv[nm] = f[3]; idx[f[2]] = nm }
      else if (f[1] == "b") { nm++; mk[nm] = f[2]; mt[nm] = "b"; ne[nm] = 0; idx[f[2]] = nm }
      else if (f[1] == "e") { i = idx[f[2]]; ne[i]++; me[i, ne[i]] = f[3] }
      next
    }
    FILENAME == ARGV[2] { nf++; fl[nf] = $0; next }
    FILENAME == ARGV[3] { split($0, f, "\t"); nc++; cl[nc] = f[2] " " f[1]; next }
    END {
      git = (ENVIRON["gitok"] == "true")
      if (!("files" in idx)) { nm++; mk[nm] = "files"; idx["files"] = nm }
      if (git && !("carry_head" in idx)) { nm++; mk[nm] = "carry_head"; idx["carry_head"] = nm }
      if (git && !("carry" in idx)) { nm++; mk[nm] = "carry"; idx["carry"] = nm }
      print "{"
      for (i = 1; i <= nm; i++) {
        c = (i < nm) ? "," : ""
        if (mk[i] == "files") {
          print "  \"files\": ["
          for (j = 1; j <= nf; j++) printf "    \"%s\"%s\n", fl[j], ((j < nf) ? "," : "")
          print "  ]" c
        } else if (git && mk[i] == "carry_head") {
          printf "  \"carry_head\": \"%s\"%s\n", ENVIRON["hd"], c
        } else if (git && mk[i] == "carry") {
          printf "  \"carry\": %s%s\n", strarr(cl, nc), c
        } else if (mt[i] == "b") {
          print "  \"" mk[i] "\": ["
          for (j = 1; j <= ne[i]; j++) printf "    \"%s\"%s\n", me[i, j], ((j < ne[i]) ? "," : "")
          print "  ]" c
        } else {
          printf "  \"%s\": %s%s\n", mk[i], mv[i], c
        }
      }
      print "}"
    }' "$t/rows" "$t/files" "$t/carry" > "$t/out" || return 1
  if [ -f "$rec" ] && cmp -s "$t/out" "$rec"; then return 0; fi      # already recorded: no rewrite
  _sumela_rec_commit "$t/out" "$rec" || return 1
  # Re-read the artifact: every requested path in "files" and, with git's answer, the carry as
  # rendered.
  sumela_record_files "$rec" > "$t/check"
  while IFS= read -r p; do
    LC_ALL=C grep -qxF -- "$p" "$t/check" || { echo "sumela_record_add_files: $p is missing from $rec after the write" >&2; return 1; }
  done < "$t/new"
  if [ "$git_ok" = true ]; then
    if _sumela_rec_parse "$rec" > "$t/rows.check" && _sumela_rec_carry_entries sumela_record_add_files "$t/rows.check" > "$t/carry.check" &&
       cmp -s "$t/carry" "$t/carry.check" && [ "$(_sumela_rec_values carry_head str < "$t/rows.check")" = "$head" ]; then :; else
      echo "sumela_record_add_files: $rec does not hold the carry entries just written" >&2; return 1
    fi
  fi
  return 0
}

sumela_record_write() {  # <version> complete|partial [options] -> the updater's write (see the header)
  local ver="${1:-}" state="${2:-}"
  local rec="" pend=false bv="" bv_set=false uc="" uc_set=false
  local l_files="" l_merged="" l_kept="" l_theirs="" l_removed="" t rc
  [ $# -ge 2 ] || { echo "usage: sumela_record_write <version> complete|partial [options]" >&2; return 2; }
  shift 2
  case "$state" in complete|partial) ;; *) echo "sumela_record_write: state must be complete or partial, not '$state'" >&2; return 2 ;; esac
  while [ $# -gt 0 ]; do
    case "$1" in
      --pending-rerun) pend=true; shift; continue ;;
      --base-version|--upstream-commit|--files|--merged|--kept|--theirs-over-fork|--removed|--record)
        [ $# -ge 2 ] || { echo "sumela_record_write: $1 needs a value" >&2; return 2; } ;;
      *) echo "sumela_record_write: unknown option: $1" >&2; return 2 ;;
    esac
    case "$1" in
      --base-version) bv="$2"; bv_set=true ;;
      --upstream-commit) uc="$2"; uc_set=true ;;
      --files) l_files="$2" ;;
      --merged) l_merged="$2" ;;
      --kept) l_kept="$2" ;;
      --theirs-over-fork) l_theirs="$2" ;;
      --removed) l_removed="$2" ;;
      --record) rec="$2" ;;
    esac
    shift 2
  done
  if [ -z "$rec" ]; then
    rec="$(sumela_record_path)" || { echo "sumela_record_write: no install root (.sumela/) above $PWD; pass --record" >&2; return 1; }
  fi
  t="$(mktemp -d)" || return 1
  rc=0; _sumela_rec_write_in "$t" || rc=$?
  rm -rf "$t"
  return "$rc"
}

_sumela_rec_write_in() {  # <tmpdir>; reads the caller's locals (bash scope is dynamic)
  local t="$1" open=false unfinished=false root a line p w head="" head_ok=false gitmsg="" old_head withcarry=false n
  # 1. This write's rows, "<array><TAB><path>[<TAB><why>]". A trailing CR per line is dropped.
  #    A line break inside a scalar would split its checked row in two: refused first.
  for a in "version:$ver" "base version:$bv" "upstream commit:$uc"; do
    case "${a#*:}" in *$'\n'*|*$'\r'*) echo "sumela-provenance: refused ${a%%:*} (a line break)" >&2; return 2 ;; esac
  done
  : > "$t/new"
  for a in files merged theirs_over_fork removed; do
    case "$a" in
      files) line="$l_files" ;; merged) line="$l_merged" ;;
      theirs_over_fork) line="$l_theirs" ;; removed) line="$l_removed" ;;
    esac
    printf '%s\n' "$line" | while IFS= read -r p; do
      p="${p%$'\r'}"; if [ -n "$p" ]; then printf '%s\t%s\n' "$a" "$p"; fi
    done >> "$t/new"
  done
  printf '%s\n' "$l_kept" | while IFS= read -r line; do
    line="${line%$'\r'}"; [ -n "$line" ] || continue
    case "$line" in *"	"*) ;; *) printf 'kept\t%s\t\n' "$line"; continue ;; esac
    p="${line%%	*}"; w="${line#*	}"
    printf 'kept\t%s\t%s\n' "$p" "$w"
  done >> "$t/new"
  {
    printf 'version\t%s\n' "$ver"
    printf 'base\t%s\n' "$bv"
    printf 'commit\t%s\n' "$uc"
    # Everything after the class is checked: a TAB inside a path is refused, never truncated.
    LC_ALL=C awk -F '\t' '
      $1 != "kept" { print "path\t" substr($0, length($1) + 2); next }
      NF != 3      { print "path\t" substr($0, 6); next }
      { print "path\t" $2; print "why\t" $3 }' "$t/new"
  } | _sumela_rec_check || return 2
  if [ "$state" = partial ] || [ "$pend" = true ]; then unfinished=true; fi

  # 2. What the replaced record lends this write [RU-M4].
  : > "$t/rows"
  if [ -f "$rec" ]; then
    if ! _sumela_rec_parse "$rec" > "$t/rows"; then
      echo "sumela_record_write: $rec is unreadable; replacing it, nothing carried" >&2
      : > "$t/rows"
    fi
  fi
  if [ "$(_sumela_rec_values pending_rerun raw < "$t/rows")" = true ] || [ "$(_sumela_rec_values partial_upgrade raw < "$t/rows")" = true ]; then
    open=true
  fi
  : > "$t/carry"
  if [ "$open" = true ]; then
    for a in theirs_over_fork merged kept removed; do            # precedence: a path keeps its first class
      if [ "$a" = kept ]; then
        { _sumela_rec_values kept o < "$t/rows" || true; } | while IFS= read -r line; do printf 'kept\t%s\n' "$line"; done >> "$t/carry"
      else
        { _sumela_rec_values "$a" s < "$t/rows" || true; } | while IFS= read -r line; do printf '%s\t%s\n' "$a" "$line"; done >> "$t/carry"
      fi
    done
    [ "$bv_set" = true ] || bv="$(_sumela_rec_values base_version str < "$t/rows" || true)"
    # upstream_commit is the release commit of the record's version: kept for that version only.
    if [ "$uc_set" != true ] && [ "$(_sumela_rec_values version str < "$t/rows")" = "$ver" ]; then
      uc="$(_sumela_rec_values upstream_commit str < "$t/rows" || true)"
    fi
  fi
  # "files": the carry entries recorded at this HEAD whose content is still what was recorded.
  root="$(dirname "$(dirname "$rec")")"
  _sumela_rec_carry_entries sumela_record_write "$t/rows" > "$t/cand"
  if [ -s "$t/cand" ] || [ "$unfinished" = true ]; then
    if head="$(_sumela_rec_head "$root" "$t")"; then head_ok=true; else gitmsg="$(_sumela_rec_errline "$t/git.err")"; fi
  fi
  if [ -s "$t/cand" ]; then
    n="$(LC_ALL=C awk 'END { print NR }' "$t/cand")"
    if [ "$head_ok" != true ]; then
      echo "sumela_record_write: cannot read the git state of $root ($gitmsg); $n earlier path(s) not carried" >&2
    elif old_head="$(_sumela_rec_values carry_head str < "$t/rows")" && [ "$old_head" = "$head" ]; then
      cut -f1 "$t/cand" > "$t/cand.paths"
      if _sumela_rec_dirty "$root" "$t" "$t/cand.paths" > "$t/cand.dirty" &&
         _sumela_rec_blobs "$root" "$t" "$t/cand.dirty" > "$t/cand.now"; then
        LC_ALL=C awk -F '\t' 'FILENAME == ARGV[1] { was[$1] = $2; next }
          $2 != "-" && was[$1] == $2 { print "files\t" $1; next }
          { printf "sumela_record_write: %s changed after it was recorded; not carried (its diff is reviewed as authored)\n", $1 > "/dev/stderr" }' \
          "$t/cand" "$t/cand.now" >> "$t/carry"
      else
        echo "sumela_record_write: cannot list the uncommitted paths in $root ($(_sumela_rec_errline "$t/git.err")); $n earlier path(s) not carried" >&2
      fi
    fi    # recorded at another HEAD: a finished run's paths, never carried
  fi
  # Carried values came from an earlier writer: re-check them like new ones, and drop (saying so)
  # any that would not be written today.
  LC_ALL=C awk -F '\t' '{
      bad = ($2 == "" || $2 ~ /[[:cntrl:]"\\]/ || NF != (($1 == "kept") ? 3 : 2))
      if ($1 == "kept" && $3 !~ /^[a-z][a-z0-9:-]*$/) bad = 1
      if (bad) printf "sumela_record_write: dropped an invalid carried %s row: %s\n", $1, $2 > "/dev/stderr"; else print }' \
    "$t/carry" > "$t/carry.ok"
  if [ "$bv_set" != true ] && ! printf 'base\t%s\n' "$bv" | _sumela_rec_check; then
    echo "sumela_record_write: dropped the carried base_version" >&2; bv=""
  fi
  if [ "$uc_set" != true ] && ! printf 'commit\t%s\n' "$uc" | _sumela_rec_check; then
    echo "sumela_record_write: dropped the carried upstream_commit" >&2; uc=""
  fi

  # 3. One class per path: this write's rows (a path given twice is refused), then the carried
  #    rows in precedence order wherever the path is still unclassified.
  LC_ALL=C awk -F '\t' '
    FILENAME == ARGV[1] {
      w = ($1 == "kept") ? $3 : ""
      if ($2 in cls) {
        if (cls[$2] != $1 || why[$2] != w) {
          printf "sumela_record_write: %s is given two classes (%s and %s)\n", $2, cls[$2], $1 > "/dev/stderr"
          bad = 1; exit 2
        }
        next
      }
      cls[$2] = $1; why[$2] = w; ord[++n] = $2; next
    }
    {
      if ($2 in cls) next
      cls[$2] = $1; why[$2] = ($1 == "kept") ? $3 : ""; ord[++n] = $2
    }
    END {
      if (bad) exit 2
      for (i = 1; i <= n; i++) { p = ord[i]; if (cls[p] == "kept") print "kept\t" p "\t" why[p]; else print cls[p] "\t" p }
    }' "$t/new" "$t/carry.ok" > "$t/merged" || return 2
  LC_ALL=C sort "$t/merged" > "$t/final"

  # 4. An unfinished run lists its files in "carry", for the write that completes it.
  : > "$t/final.carry"
  if [ "$unfinished" = true ]; then
    LC_ALL=C awk -F '\t' '$1 == "files" { print $2 }' "$t/final" > "$t/final.files"
    if [ "$head_ok" = true ] && _sumela_rec_blobs "$root" "$t" "$t/final.files" > "$t/final.blobs"; then
      LC_ALL=C sort "$t/final.blobs" > "$t/final.carry"; withcarry=true
    else
      [ "$head_ok" = true ] && gitmsg="$(_sumela_rec_errline "$t/git.err")"
      echo "sumela_record_write: cannot read the git state of $root ($gitmsg); the write that completes this run will not carry its files" >&2
    fi
  fi

  # 5. Render the canonical v2 layout.
  ver="$ver" bv="$bv" uc="$uc" pend="$pend" part="$([ "$state" = partial ] && echo true || echo false)" \
  hd="$head" withcarry="$withcarry" ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)" LC_ALL=C awk -F '\t' '
    FILENAME == ARGV[1] {
      if ($1 == "files") { nf++; F[nf] = $2; next }
      if ($1 == "kept")  { nk++; K[nk] = "{\"path\": \"" $2 "\", \"why\": \"" $3 "\"}"; next }
      c[$1]++; L[$1, c[$1]] = $2; next
    }
    { nr++; R[nr] = "\"" $2 " " $1 "\"" }
    function jsonarr(a,    j, s, n) {
      n = c[a] + 0; s = "["
      for (j = 1; j <= n; j++) s = s ((j > 1) ? ", " : "") "\"" L[a, j] "\""
      return s "]"
    }
    END {
      wc = (ENVIRON["withcarry"] == "true")
      print "{"
      print "  \"updater_schema\": 2,"
      printf "  \"version\": \"%s\",\n", ENVIRON["ver"]
      printf "  \"base_version\": \"%s\",\n", ENVIRON["bv"]
      printf "  \"upstream_commit\": \"%s\",\n", ENVIRON["uc"]
      printf "  \"updated_at\": \"%s\",\n", ENVIRON["ts"]
      printf "  \"pending_rerun\": %s,\n", ENVIRON["pend"]
      printf "  \"partial_upgrade\": %s,\n", ENVIRON["part"]
      print "  \"files\": ["
      for (j = 1; j <= nf; j++) printf "    \"%s\"%s\n", F[j], ((j < nf) ? "," : "")
      print "  ],"
      printf "  \"merged\": %s,\n", jsonarr("merged")
      s = "["; for (j = 1; j <= nk; j++) s = s ((j > 1) ? ", " : "") K[j]; s = s "]"
      printf "  \"kept\": %s,\n", s
      printf "  \"theirs_over_fork\": %s,\n", jsonarr("theirs_over_fork")
      printf "  \"removed\": %s%s\n", jsonarr("removed"), (wc ? "," : "")
      if (wc) {
        printf "  \"carry_head\": \"%s\",\n", ENVIRON["hd"]
        s = "["; for (j = 1; j <= nr; j++) s = s ((j > 1) ? ", " : "") R[j]; s = s "]"
        printf "  \"carry\": %s\n", s
      }
      print "}"
    }' "$t/final" "$t/final.carry" > "$t/out" || return 1
  _sumela_rec_commit "$t/out" "$rec" || return 1

  # 6. Re-read the artifact: the version, the exact "files" list and, for an unfinished run, the
  #    carry as rendered.
  LC_ALL=C awk -F '\t' '$1 == "files" { print $2 }' "$t/final" > "$t/want"
  sumela_record_files "$rec" > "$t/got"
  if [ "$(sumela_record_get version "$rec")" != "$ver" ] || ! cmp -s "$t/want" "$t/got"; then
    echo "sumela_record_write: $rec does not hold what was written" >&2
    return 1
  fi
  if [ "$withcarry" = true ]; then
    if _sumela_rec_parse "$rec" > "$t/rows.check" && _sumela_rec_carry_entries sumela_record_write "$t/rows.check" > "$t/carry.check" &&
       cmp -s "$t/final.carry" "$t/carry.check" && [ "$(_sumela_rec_values carry_head str < "$t/rows.check")" = "$head" ]; then :; else
      echo "sumela_record_write: $rec does not hold the carry entries written" >&2; return 1
    fi
  fi
  return 0
}
