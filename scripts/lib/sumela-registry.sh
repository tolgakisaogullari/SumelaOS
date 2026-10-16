# shellcheck shell=bash
# sumela-registry.sh — skill descriptions in .sumela/SKILL_REGISTRY.md and in SKILL.md frontmatter
# (v0.20.0+).
#
# A registry <description> is the dispatcher's routing surface: the agent matches the user's task
# against it. The skill's frontmatter description is what IDE-native loaders and
# scripts/reconcile-registry.py read. The two must be byte-identical. This library reads both,
# rewrites the <description> of one registry entry, and registers a memory plugin. Its callers:
# scripts/sumela-registry-parity.sh (the parity CLI), scripts/setup.sh and scripts/setup-memory.sh
# (through sumela_registry_register_plugin). scripts/lib/sumela-registry.ps1 is the PowerShell
# twin: it reads the same grammar and writes the same bytes.
#
# The canonical comparison: the frontmatter `description:` line minus one pair of outer quotes,
# against the registry <description> content, byte for byte. Nothing is unescaped (a `\"` stays
# as written), exactly as reconcile-registry.py copies a description into a new entry.
#
# The registry grammar. Lines end in LF; a trailing CR is ignored when a line is matched and kept
# when it is rewritten, so a CRLF checkout stays CRLF. A block starts at a line matching
# ^<skill[ >] and ends at the next line matching ^</skill> (a <skill line inside an open block is
# part of that block). Inside a block, <name>, <path> and <description> are whole lines,
# ^<tag>...</tag>$. A "loose" line is any other line of the block, but its first and its closing
# one, that a lenient reader could still take for structure: once its blanks are trimmed it starts
# with <name>, <path>, <description>, one of their closing tags, </skill> or <skill (an indented
# tag, a tag with text after it, or the start of a block whose </skill> was lost). An entry is
# usable when its block holds exactly one <path> line, one <description> line and no loose line
# (a <path> line holding a TAB counts as loose); a writer touches nothing else. Outside the blocks,
# a line that starts with <skill once trimmed, but not as ^<skill[ >], is a block no reader here
# sees: sumela_registry_rows reports it. Every rewrite keeps every other byte, a missing final
# newline included. It goes through <registry>.sumela-tmp.<pid> (gitignored through
# scripts/lib/sumela-gitignore.list), whose line count is checked before the rename.
#
#   sumela_fm_description <SKILL.md>
#       Prints the top-level `description:` of the file's YAML frontmatter, one pair of outer
#       quotes removed and trailing blanks dropped (YAML drops them too). A UTF-8 BOM and CRs are
#       ignored. Exit 0 printed; 1 no frontmatter, or no description: line in it; 3 UNPARSEABLE,
#       the value is not one line: a block scalar (| or >), a quoted value that does not close on
#       its line, an empty value, or an indented continuation line after it.
#   sumela_registry_rows <registry>
#       One row per block, and per block start no reader here sees, in file order, TAB-separated:
#         B <desc-line> <descs> <paths> <loose> <block-line> <name> <path> <desc>
#         L <line>
#       A B row is a block. <descs> and <paths> count its <description> and <path> lines, <loose>
#       its loose lines, <block-line> is the number of its first line and <desc-line> that of its
#       first <description> line (0 when none). <name>, <path> and <desc> are the content of the
#       first such line, "" when none; TABs in <name> and <path> become spaces, and <desc> is
#       everything after the eighth TAB. An L row is a line outside the blocks that starts with
#       <skill once trimmed, but not as ^<skill[ >]. Exit 0; 1 the registry is not a file.
#   sumela_registry_description <registry> <skill-path>
#       Prints the <description> of the first usable entry for <skill-path>. Exit 0; 1 none.
#   sumela_registry_set_description <registry> <skill-path> <description>
#       Rewrites the <description> line of every block whose one <path> line is <skill-path>, then
#       re-reads it. Exit 0 written (or already so); 1 no usable entry for the path, a block for
#       it is not usable (the registry is left unchanged), or the write failed or did not re-read;
#       4 refused: the description holds </description>, </skill> or a line break.
#   sumela_registry_add_entry <registry> <name> <skill-path> <description>
#       Inserts a lazy <skill> block before the first </available_skills> line, with that line's
#       line ending, and re-reads it. The caller checks that the skill is not registered yet.
#       Exit 0 written; 1 no </available_skills> line, or the write failed or did not re-read;
#       4 refused: the description as above, or an empty name or path, or one holding < > or a
#       line break.
#   sumela_registry_register_plugin <install-root> <plugin>
#       The one plugin writer (scripts/setup.sh and scripts/setup-memory.sh call it): registers
#       .sumela/memory-plugins/<plugin>/SKILL.md with its frontmatter description, verbatim, then
#       records the write (sumela_registry_record). Exit 0 registered and recorded; 1 the write
#       failed or did not re-read, or the registry has no </available_skills> line; 2 the
#       plugin's SKILL.md is not a file; 3 its frontmatter has no one-line, non-empty
#       description; 4 refused (as sumela_registry_add_entry); 5 already registered (the registry
#       holds <name><plugin></name>); 6 no registry; 7 registered, but the provenance record was
#       not updated (the reason is on stderr).
#   sumela_registry_record <install-root>
#       Adds .sumela/SKILL_REGISTRY.md to the provenance record's "files"
#       (scripts/lib/sumela-provenance.sh, which this library loads): every registry write by a
#       framework tool is recorded, so the self-modification guard knows the developer did not
#       write it. Exit as sumela_record_add_files; 1 when that library is missing.

# This file's directory, captured at source time (BASH_SOURCE[0] is this file only here).
_sumela_reg_libdir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)" || _sumela_reg_libdir=""
if [ -f "${_sumela_reg_libdir:-.}/sumela-provenance.sh" ]; then
  # shellcheck source=sumela-provenance.sh
  . "$_sumela_reg_libdir/sumela-provenance.sh"
fi

_sumela_reg_awklib() {  # awk functions shared by the reader and the writers
  cat <<'AWK'
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
# loose(k): 1 when a block line (CR dropped) that is not a tag line looks like structure.
function loose(k,    t) {
  t = trim(k)
  return t ~ /^<\/?(name|path|description)>/ || t ~ /^<\/skill>/ || t ~ /^<skill[ \t>]/ || t == "<skill"
}
AWK
}

_sumela_reg_lines() {  # <file> -> its number of LF bytes
  local n
  n="$(wc -l < "$1")" || return 1
  printf '%s\n' "$((n))"
}

sumela_fm_description() {  # <SKILL.md> -> frontmatter description, one pair of outer quotes removed
  [ -f "$1" ] || return 1
  LC_ALL=C awk -v q="'" '
    # closes(v, c): 1 when the quoted value v, opened by quote c, closes at its last byte. Inside
    # double quotes a backslash escapes, so the closing quote needs an even run of backslashes
    # before it; inside single quotes a quote is escaped by doubling, so the closing run of quotes
    # is odd.
    function closes(v, c,    i, n) {
      if (length(v) < 2 || substr(v, length(v), 1) != c) return 0
      n = 0
      if (c == "\"") {
        for (i = length(v) - 1; i > 1 && substr(v, i, 1) == "\\"; i--) n++
        return n % 2 == 0
      }
      for (i = length(v); i > 1 && substr(v, i, 1) == q; i--) n++
      return n % 2 == 1
    }
    { l = $0; sub(/\r$/, "", l); if (NR == 1 && substr(l, 1, 3) == "\357\273\277") l = substr(l, 4) }
    NR == 1 { if (l != "---") { none = 1; exit }; next }
    l == "---" { exit }
    st == 1 { if (l ~ /^[ \t]*$/) next; if (l ~ /^[ \t]/) bad = 1; exit }
    /^description:/ {
      v = l; sub(/^description:[ \t]*/, "", v); sub(/[ \t]+$/, "", v)
      c = substr(v, 1, 1)
      if (v == "" || c == "|" || c == ">") bad = 1
      else if (c == "\"" || c == q) { if (closes(v, c)) v = substr(v, 2, length(v) - 2); else bad = 1 }
      st = 1; next
    }
    END { if (none || !st) exit 1; if (bad) exit 3; print v }' "$1"
}

sumela_registry_rows() {  # <registry> -> B and L rows (see the header)
  [ -f "$1" ] || return 1
  LC_ALL=C awk "$(_sumela_reg_awklib)"'
    function flush(ended,    i, k, np, nd, nn, nlo, dl, ds, nm, pt) {
      np = 0; nd = 0; nn = 0; nlo = 0; dl = 0; ds = ""; nm = ""; pt = ""
      for (i = 1; i <= n; i++) {
        k = b[i]; sub(/\r$/, "", k)
        if (k ~ /^<name>.*<\/name>$/) { if (nn++ == 0) nm = substr(k, 7, length(k) - 13) }
        else if (k ~ /^<path>.*<\/path>$/) { if (np++ == 0) pt = substr(k, 7, length(k) - 13); if (k ~ /\t/) nlo++ }
        else if (k ~ /^<description>.*<\/description>$/) { if (nd++ == 0) { dl = ln[i]; ds = substr(k, 14, length(k) - 27) } }
        else if (i > 1 && !(ended && i == n) && loose(k)) nlo++
      }
      gsub(/\t/, " ", nm); gsub(/\t/, " ", pt)
      printf "B\t%d\t%d\t%d\t%d\t%d\t%s\t%s\t%s\n", dl, nd, np, nlo, ln[1], nm, pt, ds
      n = 0
    }
    /^<skill[ >]/ { inb = 1 }
    inb { b[++n] = $0; ln[n] = NR; if ($0 ~ /^<\/skill>/) { flush(1); inb = 0 }; next }
    { k = $0; sub(/\r$/, "", k); t = trim(k); if (t ~ /^<skill[ \t>]/ || t == "<skill") printf "L\t%d\n", NR }
    END { if (inb) flush(0) }' "$1"
}

sumela_registry_description() {  # <registry> <skill-path> -> the <description> of its first usable entry
  local row i
  row="$(sumela_registry_rows "$1" | SUMELA_PATH="$2" LC_ALL=C awk -F '\t' \
    '$1 == "B" && $3 == 1 && $4 == 1 && $5 == 0 && $8 == ENVIRON["SUMELA_PATH"] { print; exit }')"
  [ -n "$row" ] || return 1
  for i in 1 2 3 4 5 6 7 8; do row="${row#*	}"; done
  printf '%s\n' "$row"
}

_sumela_reg_commit() {  # <tmp> <registry> <who> <lines added>: rename the rendered temp file over the registry
  local want got
  want="$(( $(_sumela_reg_lines "$2") + $4 ))"; got="$(_sumela_reg_lines "$1")"
  if [ "$got" != "$want" ] && { [ "$4" = 0 ] || [ "$got" != "$((want + 1))" ]; }; then
    rm -f "$1"
    echo "$3: the rendered registry has $got lines where $want were expected; $2 left unchanged" >&2
    return 1
  fi
  if cmp -s "$1" "$2"; then rm -f "$1"; return 0; fi         # already so: no rewrite
  if mv -f "$1" "$2"; then return 0; fi
  rm -f "$1"
  echo "$3: cannot replace $2" >&2
  return 1
}

sumela_registry_set_description() {  # <registry> <skill-path> <description>: rewrites ONE entry, every other byte kept
  local reg="$1" tmp="$1.sumela-tmp.$$" nl=1 rc=0
  case "$3" in *"</description>"*|*"</skill>"*|*$'\n'*|*$'\r'*) return 4 ;; esac
  [ -f "$reg" ] || { echo "sumela_registry_set_description: $reg not found" >&2; return 1; }
  [ -n "$(tail -c 1 "$reg")" ] && nl=0                       # no final newline: keep it that way
  SUMELA_PATH="$2" SUMELA_DESC="$3" LC_ALL=C awk -v nl="$nl" "$(_sumela_reg_awklib)"'
    BEGIN { want = "<path>" ENVIRON["SUMELA_PATH"] "</path>"; desc = ENVIRON["SUMELA_DESC"] }
    function out(s) { if (held) printf "%s\n", last; last = s; held = 1 }
    function flush(ended,    i, k, cr, np, nd, nlo, hit) {
      np = 0; nd = 0; nlo = 0; hit = 0
      for (i = 1; i <= n; i++) {
        k = b[i]; sub(/\r$/, "", k)
        if (k ~ /^<name>.*<\/name>$/) continue
        if (k ~ /^<path>.*<\/path>$/) { np++; if (k ~ /\t/) nlo++; if (k == want) hit = 1; continue }
        if (k ~ /^<description>.*<\/description>$/) { nd++; continue }
        if (i > 1 && !(ended && i == n) && loose(k)) nlo++
      }
      if (hit && (np != 1 || nd != 1 || nlo > 0)) { hit = 0; bad = 1 }
      for (i = 1; i <= n; i++) {
        k = b[i]; cr = (k ~ /\r$/) ? "\r" : ""; sub(/\r$/, "", k)
        if (hit && k ~ /^<description>.*<\/description>$/) { out("<description>" desc "</description>" cr); done++ }
        else out(b[i])
      }
      n = 0
    }
    /^<skill[ >]/ { inb = 1 }
    inb { b[++n] = $0; if ($0 ~ /^<\/skill>/) { flush(1); inb = 0 }; next }
    { out($0) }
    END { if (inb) flush(0); if (held) printf "%s%s", last, (nl ? "\n" : ""); if (bad) exit 5; if (!done) exit 6 }' "$reg" > "$tmp" || rc=$?
  case "$rc" in
    0) ;;
    5) rm -f "$tmp"; echo "sumela_registry_set_description: a block for $2 does not hold exactly one <path> and one <description> line, or holds a loose tag line; $reg left unchanged" >&2; return 1 ;;
    6) rm -f "$tmp"; echo "sumela_registry_set_description: no entry for $2 in $reg" >&2; return 1 ;;
    *) rm -f "$tmp"; echo "sumela_registry_set_description: cannot write $tmp" >&2; return 1 ;;
  esac
  _sumela_reg_commit "$tmp" "$reg" sumela_registry_set_description 0 || return 1
  if [ "$(sumela_registry_description "$reg" "$2")" != "$3" ]; then
    echo "sumela_registry_set_description: $reg does not hold the new description of $2 after the write" >&2
    return 1
  fi
}

sumela_registry_add_entry() {  # <registry> <name> <skill-path> <description>: a new lazy entry before </available_skills>
  local reg="$1" tmp="$1.sumela-tmp.$$" nl=1 rc=0
  case "$4" in *"</description>"*|*"</skill>"*|*$'\n'*|*$'\r'*) return 4 ;; esac
  [ -n "$2" ] && [ -n "$3" ] || return 4
  case "$2$3" in *"<"*|*">"*|*$'\n'*|*$'\r'*) return 4 ;; esac
  [ -f "$reg" ] || { echo "sumela_registry_add_entry: $reg not found" >&2; return 1; }
  [ -n "$(tail -c 1 "$reg")" ] && nl=0
  # The name travels as _SUMELA_NAME: SUMELA_PATH and SUMELA_DESC are this library's only public
  # plumbing names (tests/test_env_tables.sh lists them).
  _SUMELA_NAME="$2" SUMELA_PATH="$3" SUMELA_DESC="$4" LC_ALL=C awk -v nl="$nl" '
    function out(s) { if (held) printf "%s\n", last; last = s; held = 1 }
    { k = $0; sub(/\r$/, "", k); t = k; gsub(/^[ \t]+|[ \t]+$/, "", t) }
    !done && t == "</available_skills>" {
      cr = ($0 ~ /\r$/) ? "\r" : ""
      if (held && prev !~ /^[ \t]*$/) out(cr)
      out("<skill activation=\"lazy\">" cr)
      out("<name>" ENVIRON["_SUMELA_NAME"] "</name>" cr)
      out("<description>" ENVIRON["SUMELA_DESC"] "</description>" cr)
      out("<path>" ENVIRON["SUMELA_PATH"] "</path>" cr)
      out("</skill>" cr)
      out(cr)
      done = 1
    }
    { out($0); prev = k }
    END { if (held) printf "%s%s", last, (nl ? "\n" : ""); if (!done) exit 6 }' "$reg" > "$tmp" || rc=$?
  case "$rc" in
    0) ;;
    6) rm -f "$tmp"; echo "sumela_registry_add_entry: no </available_skills> line in $reg; left unchanged" >&2; return 1 ;;
    *) rm -f "$tmp"; echo "sumela_registry_add_entry: cannot write $tmp" >&2; return 1 ;;
  esac
  _sumela_reg_commit "$tmp" "$reg" sumela_registry_add_entry 6 || return 1     # six lines, or seven with a blank before
  if [ "$(sumela_registry_description "$reg" "$3")" != "$4" ]; then
    echo "sumela_registry_add_entry: $reg does not hold the new entry for $3 after the write" >&2
    return 1
  fi
}

sumela_registry_record() {  # <install-root>: .sumela/SKILL_REGISTRY.md into the provenance record's "files"
  if ! command -v sumela_record_add_files >/dev/null 2>&1; then
    echo "sumela-registry: ${_sumela_reg_libdir:-scripts/lib}/sumela-provenance.sh is missing; the registry write in $1 is not recorded" >&2
    return 1
  fi
  sumela_record_add_files --record "$1/.sumela/.last-update.json" .sumela/SKILL_REGISTRY.md
}

sumela_registry_register_plugin() {  # <install-root> <plugin>: the one plugin writer (see the header)
  local root="$1" p="$2" reg skill desc
  reg="$root/.sumela/SKILL_REGISTRY.md"
  skill=".sumela/memory-plugins/$p/SKILL.md"
  [ -f "$reg" ] || return 6
  if LC_ALL=C grep -qF -- "<name>$p</name>" "$reg"; then return 5; fi
  [ -f "$root/$skill" ] || return 2
  desc="$(sumela_fm_description "$root/$skill")" || return 3
  [ -n "$desc" ] || return 3
  sumela_registry_add_entry "$reg" "$p" "$skill" "$desc" || return $?
  sumela_registry_record "$root" || return 7
}
