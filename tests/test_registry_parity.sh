#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# tests/test_registry_parity.sh — skill-description parity between the registry and the skills (R1-07).
#
# A registry <description> is the dispatcher's routing surface; it must equal the skill's
# frontmatter description byte for byte. scripts/sumela-registry-parity.sh checks it and, with
# consent, syncs it; scripts/lib/sumela-registry.sh reads and rewrites; the plugin writers in
# setup.sh and setup-memory.sh copy the frontmatter description verbatim. This suite pins:
#   t_check_detects_drift_exit3               --check and --plan report drift, exit 3, write nothing;
#                                             an orphaned entry is skipped, not drift
#   t_sync_rewrites_only_target_block         --sync rewrites the drifted <description> line and no
#                                             other byte: LF, CRLF (kept), no final newline (kept);
#                                             per-entry answers, with a BOM and CRLF as a Windows
#                                             pipe sends them; no answer declines; --only
#   t_security_routing_drift_is_attention     drift in the four security-routing skills is ATTENTION
#   t_reserved_tag_refused                    a description holding </description> or </skill> is
#                                             never written (the CLI calls it UNPARSEABLE, the lib
#                                             refuses with 4); bad names and line breaks too
#   t_unparseable_is_never_synced             multi-line YAML and a registry entry without one
#                                             <description> line are UNPARSEABLE; the frontmatter
#                                             reader's forms (quotes, escapes, CRLF, BOM, block
#                                             scalars)
#   t_malformed_registry_is_never_a_pass      a block without exactly one strict <path> line
#                                             (indented tags, trailing blanks, a lost </skill>), an
#                                             indented or fully indented registry and <skill text no
#                                             reader parses are UNPARSEABLE rows, never "skipped"
#   t_unsafe_paths_are_unparseable            an absolute path or one with a .. segment is not read
#                                             and fails the check
#   t_writers_keep_bytes                      add_entry keeps CRLF; a rendered registry with the
#                                             wrong line count is never renamed into place
#   t_text_mode_awk_keeps_line_endings        under an awk that reads text mode, as Git for Windows'
#                                             gawk does, sync and add_entry keep CRLF, mixed
#                                             endings and a lone final CR byte for byte
#                                             (BINMODE=3); an awk that drops CRs anyway is refused
#                                             by the CR check, the registry unchanged
#   t_register_plugin                         sumela_registry_register_plugin, the one plugin
#                                             writer: every exit code, the provenance record
#   t_sync_stops_at_failed_write              the run stops at the first failed write, says so, and
#                                             counts that entry as left
#   t_interrupted_sync_leaves_no_temp         an interrupted run removes its temp file
#   t_writers_copy_verbatim                   setup.sh --plugins and setup-memory.sh's register_plugin
#                                             copy the frontmatter description; parity stays 0
#   t_source_repo_parity_zero                 this repository is in parity
#   t_validate_fails_in_source_warns_in_consumer   validate-structure.sh section 2b
#   t_registry_write_recorded_in_provenance   a rewrite adds .sumela/SKILL_REGISTRY.md to the record's
#                                             "files", its carry the blob of the bytes written (CRLF
#                                             kept); check, plan and a declined sync write nothing
#   t_usage_and_errors                        exit 2 for usage, 1 without an install or a registry
#   t_twins_agree                             the PowerShell twin prints the same lines and writes the
#                                             same bytes, for LF, CRLF and mixed line endings and
#                                             the same answer bytes (pwsh, when present; SKIP
#                                             otherwise)
# tests/test_registry_parity.ps1 runs the same cases against the PowerShell twin, including the
# Windows PowerShell 5.1 byte check of the writers (t_ps51_writer_keeps_utf8) [RU-M1].
#
# Every case builds its own throwaway install under $WORK from synthetic skills, except the two that
# need the framework tree (a clone of this repository, with the working tree's changes copied in).
#
# Run from anywhere:  bash tests/test_registry_parity.sh
# Exit 0 = all assertions passed, 1 = a failure (printed above).
# -----------------------------------------------------------------------------
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TOOL="$REPO_ROOT/scripts/sumela-registry-parity.sh"
PSTOOL="$REPO_ROOT/scripts/sumela-registry-parity.ps1"
LIB="$REPO_ROOT/scripts/lib/sumela-registry.sh"
for f in "$TOOL" "$LIB"; do [ -f "$f" ] || { echo "FAIL: $f missing"; exit 1; }; done
# shellcheck source=../scripts/lib/sumela-registry.sh
. "$LIB"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
WORK="$(cd "$WORK" && pwd -P)"
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_PREFIX
export GIT_AUTHOR_DATE='2026-10-14T00:00:00 +0000' GIT_COMMITTER_DATE='2026-10-14T00:00:00 +0000'
export SUMELA_SKIP_MEMORY_SETUP=1

PASS=0 FAIL=0
ok()   { echo "  PASS  $1"; PASS=$((PASS + 1)); }
bad()  { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); }
skip() { echo "  SKIP  $1"; }
same() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1"; printf '      expected: %s\n      got:      %s\n' "$2" "$3"; fi; }
has()  { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1"; printf '      wanted: %s\n      in:     %s\n' "$3" "$2" | head -20 ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1"; printf '      unwanted: %s\n' "$3" ;; *) ok "$1" ;; esac; }
unchanged() { if cmp -s "$2" "$3"; then ok "$1"; else bad "$1 (the file changed)"; diff "$2" "$3" | head -6 | sed 's/^/      /'; fi; }
PWSH="$(command -v pwsh 2>/dev/null || true)"
CR="$(printf '\r')"

# skill <file> <name> <description line value, as written after "description: ">
skill() {
  mkdir -p "$(dirname "$1")"
  printf -- '---\nname: %s\ndescription: %s\n---\n\n# %s\n\nBody text.\n' "$2" "$3" "$2" > "$1"
}
REG_BETA_LINE=16   # the line of beta's <description> in the fixture registry
# mkinstall <dir>: a synthetic install. alpha (non-ASCII), secure-coding-standard and gamma (a
# single-quoted plugin description) are in parity; beta has drifted; "gone" is an orphaned entry.
# A git repository with one commit (fixed dates: two fixtures built the same way share a HEAD);
# the provenance record is gitignored, as in a consumer.
mkinstall() {
  local d="$1"
  mkdir -p "$d/.sumela"
  skill "$d/.sumela/skills/alpha/SKILL.md" alpha '"Use when alpha work starts — ö ş ğ ı İ."'
  skill "$d/.sumela/skills/beta/SKILL.md" beta '"Use when beta work starts (new text)."'
  skill "$d/.sumela/skills/secure-coding-standard/SKILL.md" secure-coding-standard '"Use whenever code is planned, written or reviewed."'
  skill "$d/.sumela/memory-plugins/gamma/SKILL.md" gamma "'Use when gamma memory is needed.'"
  cat > "$d/.sumela/SKILL_REGISTRY.md" <<'EOF'
<skills_system priority="1">
<usage>
A synthetic registry. Match the user's task against each <description>.
</usage>

<available_skills>

<skill activation="eager">
<name>alpha</name>
<description>Use when alpha work starts — ö ş ğ ı İ.</description>
<path>.sumela/skills/alpha/SKILL.md</path>
</skill>

<skill activation="lazy">
<name>beta</name>
<description>Use when beta work starts (old text).</description>
<path>.sumela/skills/beta/SKILL.md</path>
</skill>

<skill activation="lazy">
<name>secure-coding-standard</name>
<description>Use whenever code is planned, written or reviewed.</description>
<path>.sumela/skills/secure-coding-standard/SKILL.md</path>
</skill>

<skill activation="lazy">
<name>gamma</name>
<description>Use when gamma memory is needed.</description>
<path>.sumela/memory-plugins/gamma/SKILL.md</path>
</skill>

<skill activation="lazy">
<name>gone</name>
<description>An orphaned entry whose skill is not on disk.</description>
<path>.sumela/skills/gone/SKILL.md</path>
</skill>

</available_skills>
</skills_system>
EOF
  printf '.sumela/.last-update.json\n' > "$d/.gitignore"
  git -C "$d" init -q -b main && git -C "$d" config user.email t@example.com && git -C "$d" config user.name Test &&
    git -C "$d" config core.autocrlf false && git -C "$d" add -A && git -C "$d" commit -qm init
}
to_crlf() { LC_ALL=C sed "s/\$/$CR/" "$1" > "$1.crlf" && mv "$1.crlf" "$1"; }
commit_all() { git -C "$1" add -A && git -C "$1" commit -qm "${2:-commit}"; }
# run <dir> <args>...: the bash CLI from <dir>; sets OUT (stdout and stderr) and RC
run() { local d="$1"; shift; RC=0; OUT="$(cd "$d" && bash "$TOOL" "$@" 2>&1 </dev/null)" || RC=$?; }
# Byte checks that hold on Git Bash too, whose awk reads text mode unless told BINMODE=3 (and
# whose sed and grep this suite does not trust with a CR): awk with BINMODE=3, tr, od, cmp, tail.
# lines <file> <from> <to>: those lines, bytes as they are (CRs kept)
lines() { LC_ALL=C awk -v BINMODE=3 -v a="$2" -v b="$3" 'NR > b { exit } NR >= a { print }' "$1"; }
# crs <file>, nlines <file>: its number of CR bytes, of LF bytes
crs() { LC_ALL=C tr -cd '\r' < "$1" | wc -c | tr -d ' '; }
nlines() { LC_ALL=C tr -cd '\n' < "$1" | wc -c | tr -d ' '; }
# to_mixed <file>: lines 1-19 end in CRLF (beta's <description> among them), the others in LF,
# and the last one in a lone CR instead (no LF): every ending a line can have, in one file.
to_mixed() {
  LC_ALL=C awk -v BINMODE=3 '
    { if (NR > 1) printf "%s", prev; prev = $0 (NR <= 19 ? "\r\n" : "\n") }
    END { sub(/\r?\n$/, "\r", prev); printf "%s", prev }' "$1" > "$1.mixed" && mv "$1.mixed" "$1"
}

# seed <dir>: a clone of this repository with the working tree's changes copied in (the tests exercise
# the current scripts, not the last commit's).
seed() {
  local dst="$1"
  git -C "$REPO_ROOT" clone --quiet --no-hardlinks . "$dst" || return 1
  ( cd "$REPO_ROOT" && git ls-files -m -o --exclude-standard -- scripts .sumela AGENTS.md.template docs/second-brain/template README.md ) |
    while IFS= read -r f; do
      [ -f "$REPO_ROOT/$f" ] || continue
      mkdir -p "$dst/$(dirname "$f")"; cp "$REPO_ROOT/$f" "$dst/$f"
    done
}
# strip_entry <registry> <name>: removes that <skill> block and the blank line after it, without
# the library under test.
strip_entry() {
  N="$2" LC_ALL=C awk -v BINMODE=3 '/^<skill[ >]/ { inb = 1; n = 0; drop = 0 }
    inb { b[++n] = $0; k = $0; sub(/\r$/, "", k); if (k == "<name>" ENVIRON["N"] "</name>") drop = 1
          if ($0 ~ /^<\/skill>/) { if (!drop) for (i = 1; i <= n; i++) print b[i]; else gap = 1; inb = 0 }; next }
    gap && /^\r?$/ { gap = 0; next }
    { gap = 0; print }' "$1" > "$1.strip" && mv "$1.strip" "$1"
}
# fm_value <SKILL.md>: the description: value with one pair of outer quotes removed, computed here
# with sed, independently of the library.
fm_value() { LC_ALL=C sed -n 's/^description: *//p' "$1" | head -n 1 | LC_ALL=C sed -e 's/\r$//' -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'\$/\1/"; }
reg_value() { N="$2" LC_ALL=C awk '{ k = $0; sub(/\r$/, "", k) } k == "<name>" ENVIRON["N"] "</name>" { f = 1; next }
    f && k ~ /^<description>/ { sub(/^<description>/, "", k); sub(/<\/description>$/, "", k); print k; exit }' "$1"; }

echo "Registry and frontmatter parity (scripts/sumela-registry-parity.sh)"

# ---------------------------------------------------------------------------------------------
echo "== t_check_detects_drift_exit3"
d="$WORK/check"; mkinstall "$d"; cp "$d/.sumela/SKILL_REGISTRY.md" "$WORK/check.orig"
run "$d" --check
same "--check exits 3 on drift" 3 "$RC"
has "the drifted entry is a DRIFT row with its name and path" "$OUT" "DRIFT       beta  .sumela/skills/beta/SKILL.md"
has "the summary counts it; the orphaned entry is skipped, not drift" "$OUT" \
  "sumela-registry-parity: 4 checked, 1 out of parity (1 drift, 0 attention, 0 unparseable), 1 skipped"
has "the fixer is named" "$OUT" "fix: bash scripts/sumela-registry-parity.sh --sync"
hasnt "an entry in parity prints no row (alpha, non-ASCII, byte-identical)" "$OUT" "alpha"
hasnt "the orphaned entry prints no row" "$OUT" "gone"
unchanged "--check writes nothing" "$WORK/check.orig" "$d/.sumela/SKILL_REGISTRY.md"
check_out="$OUT"; run "$d"
same "no flag is --check" "$check_out" "$OUT"
run "$d" --plan
same "--plan exits 3 on drift" 3 "$RC"
has "--plan prints one diff per drifted entry" "$OUT" "--- a/.sumela/SKILL_REGISTRY.md
+++ b/.sumela/SKILL_REGISTRY.md
@@ -$REG_BETA_LINE +$REG_BETA_LINE @@ beta
-<description>Use when beta work starts (old text).</description>
+<description>Use when beta work starts (new text).</description>"
unchanged "--plan writes nothing" "$WORK/check.orig" "$d/.sumela/SKILL_REGISTRY.md"
[ -e "$d/.sumela/.last-update.json" ] && bad "--check and --plan write no provenance record" || ok "--check and --plan write no provenance record"
skill "$d/.sumela/skills/beta/SKILL.md" beta '"Use when beta work starts (old text)."'
run "$d" --check
same "after a hand fix of the frontmatter: exit 0" 0 "$RC"
has "…and nothing is out of parity" "$OUT" "4 checked, 0 out of parity (0 drift, 0 attention, 0 unparseable), 1 skipped"

# ---------------------------------------------------------------------------------------------
echo "== t_sync_rewrites_only_target_block"
NEWBETA="<description>Use when beta work starts (new text).</description>"
for variant in lf crlf nofinal; do
  d="$WORK/sync-$variant"; mkinstall "$d"; reg="$d/.sumela/SKILL_REGISTRY.md"
  case "$variant" in
    crlf) for f in "$reg" "$d"/.sumela/skills/*/SKILL.md "$d"/.sumela/memory-plugins/*/SKILL.md; do to_crlf "$f"; done; commit_all "$d" crlf ;;
    nofinal) printf '%s' "$(cat "$reg")" > "$reg.n" && mv "$reg.n" "$reg"; commit_all "$d" nofinal ;;
  esac
  cp "$reg" "$WORK/sync-$variant.orig"
  run "$d" --sync --yes
  same "$variant: --sync --yes exits 0" 0 "$RC"
  has "$variant: the drifted entry is synced" "$OUT" "synced      beta"
  has "$variant: nothing is left" "$OUT" "4 checked, 1 synced, 0 out of parity (0 drift, 0 attention, 0 unparseable), 1 skipped"
  if cmp -s <(lines "$WORK/sync-$variant.orig" 1 $((REG_BETA_LINE - 1))) <(lines "$reg" 1 $((REG_BETA_LINE - 1))) &&
     cmp -s <(LC_ALL=C tail -n +$((REG_BETA_LINE + 1)) "$WORK/sync-$variant.orig") <(LC_ALL=C tail -n +$((REG_BETA_LINE + 1)) "$reg"); then
    ok "$variant: every other byte of the registry is unchanged"
  else bad "$variant: every other byte of the registry is unchanged"; diff "$WORK/sync-$variant.orig" "$reg" | head -8 | sed 's/^/      /'; fi
  want="$NEWBETA"; [ "$variant" = crlf ] && want="$NEWBETA$CR"
  same "$variant: the description line is the frontmatter's text" "$want" "$(lines "$reg" $REG_BETA_LINE $REG_BETA_LINE)"
  run "$d" --check
  same "$variant: --check after the sync exits 0" 0 "$RC"
done
d="$WORK/sync-nofinal"
[ -n "$(tail -c 1 "$d/.sumela/SKILL_REGISTRY.md")" ] && ok "nofinal: the missing final newline stays missing" || bad "nofinal: the missing final newline stays missing"
d="$WORK/sync-crlf"
same "crlf: every line keeps its CRLF" "$(nlines "$d/.sumela/SKILL_REGISTRY.md")" "$(crs "$d/.sumela/SKILL_REGISTRY.md")"

# Per-entry answers: two drifted entries, "y" for the first and "n" for the second.
d="$WORK/answers"; mkinstall "$d"; reg="$d/.sumela/SKILL_REGISTRY.md"
skill "$d/.sumela/memory-plugins/gamma/SKILL.md" gamma "'Use when gamma memory is needed (new).'"
commit_all "$d" "gamma drifts"; cp "$reg" "$WORK/answers.orig"
RC=0; OUT="$(cd "$d" && printf 'y\nn\n' | bash "$TOOL" --sync 2>&1)" || RC=$?
same "answers y then n: exit 3 (one entry left)" 3 "$RC"
has "each entry is asked about" "$OUT" "Sync the registry description of beta from its frontmatter? [y/N] "
has "y syncs the first" "$OUT" "synced      beta"
has "n declines the second" "$OUT" "declined    gamma"
has "the summary counts what is left" "$OUT" "4 checked, 1 synced, 1 out of parity (1 drift, 0 attention, 0 unparseable), 1 skipped"
same "beta was rewritten" "Use when beta work starts (new text)." "$(reg_value "$reg" beta)"
same "gamma was not" "Use when gamma memory is needed." "$(reg_value "$reg" gamma)"
# Answers from a Windows pipe: CRLF line ends, and the UTF-8 BOM Windows PowerShell 5.1 writes
# first when the console code page is UTF-8. One of each is trimmed; a second CR stays.
cp "$WORK/answers.orig" "$reg"
RC=0; OUT="$(cd "$d" && printf '\357\273\277y\r\nn\r\n' | bash "$TOOL" --sync 2>&1)" || RC=$?
has "a BOM before y and CRLF after each answer: y still syncs the first" "$OUT" "synced      beta"
has "…and n still declines the second" "$OUT" "declined    gamma"
same "…beta was rewritten" "Use when beta work starts (new text)." "$(reg_value "$reg" beta)"
cp "$WORK/answers.orig" "$reg"
RC=0; OUT="$(cd "$d" && printf 'y\r\r\nyes' | bash "$TOOL" --sync 2>&1)" || RC=$?
has "only one CR is trimmed: y and two CRs declines" "$OUT" "declined    beta"
has "…and a last answer without its line end still counts" "$OUT" "synced      gamma"
cp "$WORK/answers.orig" "$reg"
run "$d" --sync
same "no answer (end of input, as in an agent's shell): exit 3" 3 "$RC"
has "…every entry declined" "$OUT" "declined    beta"
has "…and the developer-consent route is named" "$OUT" "run bash scripts/sumela-registry-parity.sh --sync --yes once the developer consents"
unchanged "…and nothing written" "$WORK/answers.orig" "$reg"
run "$d" --sync --yes --only gamma
same "--only gamma --sync --yes: exit 0 for that entry" 0 "$RC"
same "…gamma synced" "Use when gamma memory is needed (new)." "$(reg_value "$reg" gamma)"
same "…beta untouched" "Use when beta work starts (old text)." "$(reg_value "$reg" beta)"
has "…the summary covers the one entry" "$OUT" "1 checked, 1 synced, 0 out of parity"

# ---------------------------------------------------------------------------------------------
echo "== t_security_routing_drift_is_attention"
d="$WORK/attention"; mkinstall "$d"; reg="$d/.sumela/SKILL_REGISTRY.md"
skill "$d/.sumela/skills/secure-coding-standard/SKILL.md" secure-coding-standard '"Use whenever code is touched."'
for s in requesting-code-review receiving-code-review verification-before-completion; do
  skill "$d/.sumela/skills/$s/SKILL.md" "$s" "\"Use when $s applies (new).\""
  N="$s" LC_ALL=C awk '{ print } $0 == "<available_skills>" { print ""; print "<skill activation=\"lazy\">"; print "<name>" ENVIRON["N"] "</name>"
      print "<description>Use when " ENVIRON["N"] " applies.</description>"; print "<path>.sumela/skills/" ENVIRON["N"] "/SKILL.md</path>"; print "</skill>" }' \
    "$reg" > "$reg.t" && mv "$reg.t" "$reg"
done
commit_all "$d" attention
run "$d" --check
same "security-routing drift exits 3" 3 "$RC"
for s in secure-coding-standard requesting-code-review receiving-code-review verification-before-completion; do
  has "$s drift is an ATTENTION row" "$OUT" "ATTENTION   $s  .sumela/skills/$s/SKILL.md  (security routing: review this diff before it is synced)"
done
has "beta stays a plain DRIFT row" "$OUT" "DRIFT       beta  "
has "the summary counts attention apart" "$OUT" "7 checked, 5 out of parity (1 drift, 4 attention, 0 unparseable), 1 skipped"
run "$d" --plan --only secure-coding-standard
has "--plan shows the ATTENTION entry's diff" "$OUT" "+<description>Use whenever code is touched.</description>"
# Either sign is enough: a security-routing name at another path, another name at such a path.
d="$WORK/attention2"; mkinstall "$d"; reg="$d/.sumela/SKILL_REGISTRY.md"
skill "$d/.sumela/memory-plugins/verification-before-completion/SKILL.md" verification-before-completion '"Use when done (new)."'
skill "$d/.sumela/skills/receiving-code-review/SKILL.md" review-alias '"Use when feedback arrives (new)."'
LC_ALL=C awk '{ print } $0 == "<available_skills>" { print ""
    print "<skill activation=\"lazy\">"; print "<name>verification-before-completion</name>"; print "<description>Use when done.</description>"
    print "<path>.sumela/memory-plugins/verification-before-completion/SKILL.md</path>"; print "</skill>"; print ""
    print "<skill activation=\"lazy\">"; print "<name>review-alias</name>"; print "<description>Use when feedback arrives.</description>"
    print "<path>.sumela/skills/receiving-code-review/SKILL.md</path>"; print "</skill>" }' "$reg" > "$reg.t" && mv "$reg.t" "$reg"
commit_all "$d" attention2
run "$d" --check
has "a security-routing name at another path is ATTENTION" "$OUT" "ATTENTION   verification-before-completion  .sumela/memory-plugins/verification-before-completion/SKILL.md"
has "another name at a security-routing path is ATTENTION" "$OUT" "ATTENTION   review-alias  .sumela/skills/receiving-code-review/SKILL.md"

# ---------------------------------------------------------------------------------------------
echo "== t_reserved_tag_refused"
d="$WORK/reserved"; mkinstall "$d"; reg="$d/.sumela/SKILL_REGISTRY.md"
skill "$d/.sumela/skills/beta/SKILL.md" beta '"Use when </description> ends a block."'
skill "$d/.sumela/memory-plugins/gamma/SKILL.md" gamma '"Use when </skill> ends a block."'
commit_all "$d" reserved; cp "$reg" "$WORK/reserved.orig"
run "$d" --check
same "a reserved tag in a frontmatter description: exit 3" 3 "$RC"
has "it is UNPARSEABLE, not DRIFT (</description>)" "$OUT" "UNPARSEABLE beta  .sumela/skills/beta/SKILL.md  (the frontmatter description holds </description> or </skill>"
has "it is UNPARSEABLE, not DRIFT (</skill>)" "$OUT" "UNPARSEABLE gamma  "
run "$d" --sync --yes
same "--sync --yes leaves them out of parity: exit 3" 3 "$RC"
unchanged "…and never writes them" "$WORK/reserved.orig" "$reg"
rc=0; sumela_registry_set_description "$reg" .sumela/skills/beta/SKILL.md 'a </description> b' || rc=$?
same "the library refuses </description> with 4" 4 "$rc"
rc=0; sumela_registry_set_description "$reg" .sumela/skills/beta/SKILL.md 'a </skill> b' || rc=$?
same "…</skill> with 4" 4 "$rc"
rc=0; sumela_registry_set_description "$reg" .sumela/skills/beta/SKILL.md "$(printf 'two\nlines')" || rc=$?
same "…a line break with 4" 4 "$rc"
rc=0; sumela_registry_add_entry "$reg" 'bad<name' .sumela/skills/x/SKILL.md 'ok' || rc=$?
same "add_entry refuses a name holding < with 4" 4 "$rc"
rc=0; sumela_registry_add_entry "$reg" x .sumela/skills/x/SKILL.md 'a </skill> b' || rc=$?
same "add_entry refuses a reserved tag with 4" 4 "$rc"
unchanged "every refusal left the registry unchanged" "$WORK/reserved.orig" "$reg"
ls "$d/.sumela" | grep -q 'sumela-tmp' && bad "no temp file is left behind" || ok "no temp file is left behind"

# ---------------------------------------------------------------------------------------------
echo "== t_unparseable_is_never_synced"
d="$WORK/unparseable"; mkinstall "$d"; reg="$d/.sumela/SKILL_REGISTRY.md"
printf -- '---\nname: beta\ndescription: >\n  Use when beta work starts,\n  folded.\n---\n' > "$d/.sumela/skills/beta/SKILL.md"
skill "$d/.sumela/skills/alpha/SKILL.md" alpha '""'
LC_ALL=C awk '{ print } $0 == "<description>Use when gamma memory is needed.</description>" { print "<description>A second description line.</description>" }' \
  "$reg" > "$reg.t" && mv "$reg.t" "$reg"
commit_all "$d" unparseable; cp "$reg" "$WORK/unparseable.orig"
run "$d" --check
same "unparseable entries: exit 3" 3 "$RC"
has "a folded block scalar is UNPARSEABLE" "$OUT" "UNPARSEABLE beta  .sumela/skills/beta/SKILL.md  (the frontmatter description is not one line"
has "a registry entry with two <description> lines is UNPARSEABLE" "$OUT" "UNPARSEABLE gamma  .sumela/memory-plugins/gamma/SKILL.md  (the registry entry does not hold exactly one <description> line)"
has "an empty frontmatter description is UNPARSEABLE, never copied over the routing text" "$OUT" "UNPARSEABLE alpha  .sumela/skills/alpha/SKILL.md  (the frontmatter description is empty)"
has "the hand fix is named" "$OUT" "hand fix: each UNPARSEABLE row says what to change; --sync never rewrites it"
run "$d" --sync --yes
same "--sync --yes: exit 3" 3 "$RC"
unchanged "…and the registry is untouched" "$WORK/unparseable.orig" "$reg"
rc=0; sumela_registry_set_description "$reg" .sumela/memory-plugins/gamma/SKILL.md "x" || rc=$?
same "the library refuses a block without exactly one <description> line (exit 1)" 1 "$rc"
unchanged "…leaving the registry unchanged" "$WORK/unparseable.orig" "$reg"
# The frontmatter reader, form by form: <expected exit> <expected value> <description: line(s)>
fx="$WORK/fm"; mkdir -p "$fx"; i=0
fm_case() {
  i=$((i + 1)); printf -- "%s" "$3" > "$fx/$i.md"
  local got rc=0; got="$(sumela_fm_description "$fx/$i.md")" || rc=$?
  if [ "$rc" = "$1" ] && [ "$got" = "$2" ]; then ok "frontmatter form $i ($4)"; else bad "frontmatter form $i ($4): exit $rc, value [$got]"; fi
}
fm_case 0 "Use when x" $'---\ndescription: "Use when x"\n---\n' "double quotes"
fm_case 0 "it''s" $'---\ndescription: \'it\'\'s\'\n---\n' "single quotes, doubled quote kept as written"
fm_case 0 'Use \"x\"' $'---\ndescription: "Use \\"x\\""\n---\n' "escapes kept as written"
fm_case 0 "plain text" $'---\ndescription: plain text  \nname: n\n---\n' "plain, trailing blanks dropped"
fm_case 0 "ö ş" $'---\r\ndescription: "ö ş"\r\n---\r\n' "CRLF"
fm_case 0 "bom" $'\xef\xbb\xbf---\ndescription: bom\n---\n' "a UTF-8 BOM"
fm_case 3 "" $'---\ndescription: |\n  literal\n---\n' "a literal block scalar"
fm_case 3 "" $'---\ndescription:\n  on the next line\n---\n' "an empty value"
fm_case 3 "" $'---\ndescription: "opens\n  and closes"\n---\n' "a quote that does not close on its line"
fm_case 3 "" $'---\ndescription: plain\n  continued\n---\n' "a continuation line"
fm_case 1 "" $'---\nname: n\n---\ndescription: in the body\n' "no description in the frontmatter"
fm_case 1 "" $'# no frontmatter\ndescription: x\n' "no frontmatter"
fm_case 3 "" $'---\ndescription: "ends \\"\n---\n' "an escaped quote does not close its value"
fm_case 0 'ends \\' $'---\ndescription: "ends \\\\"\n---\n' "an escaped backslash before the closing quote"
fm_case 3 "" $'---\ndescription: |\n---\n' "a block scalar with no lines"
fm_case 3 "" $'---\ndescription: \'ends\'\'\n---\n' "a doubled single quote does not close its value"

# ---------------------------------------------------------------------------------------------
echo "== t_malformed_registry_is_never_a_pass"
# Each shape: <name> <registry text> <wanted UNPARSEABLE row>. The skill on disk has drifted, so
# the only right answers are an UNPARSEABLE row and exit 3; none may count as skipped.
mal() {
  local n="$1" text="$2" want="$3" d="$WORK/mal-$1"
  mkdir -p "$d/.sumela"; skill "$d/.sumela/skills/a/SKILL.md" a '"Use when a works (new)."'
  printf '%s' "$text" > "$d/.sumela/SKILL_REGISTRY.md"; cp "$d/.sumela/SKILL_REGISTRY.md" "$WORK/mal-$n.orig"
  run "$d" --check
  same "$n: exit 3" 3 "$RC"
  has "$n: an UNPARSEABLE row" "$OUT" "$want"
  hasnt "$n: never a silent skip" "$OUT" "0 out of parity"
  run "$d" --sync --yes
  same "$n: --sync --yes exits 3" 3 "$RC"
  unchanged "$n: …and writes nothing" "$WORK/mal-$n.orig" "$d/.sumela/SKILL_REGISTRY.md"
}
P1="the registry entry does not hold exactly one <path> line; a tag line in it is indented, has text around it, or opens another block"
mal indented $'<available_skills>\n<skill activation="lazy">\n  <name>a</name>\n  <description>Use when a works.</description>\n  <path>.sumela/skills/a/SKILL.md</path>\n</skill>\n</available_skills>\n' \
  "UNPARSEABLE -  .sumela/SKILL_REGISTRY.md:2  ($P1)"
mal trailing $'<available_skills>\n<skill activation="lazy">\n<name>a</name>\n<description>Use when a works.</description>\n<path>.sumela/skills/a/SKILL.md</path>  \n</skill>\n</available_skills>\n' \
  "UNPARSEABLE a  .sumela/SKILL_REGISTRY.md:2  ($P1)"
mal lost-end $'<available_skills>\n<skill activation="lazy">\n<name>a</name>\n<description>Use when a works.</description>\n<path>.sumela/skills/a/SKILL.md</path>\n\n<skill activation="lazy">\n<name>b</name>\n<description>B.</description>\n<path>.sumela/skills/b/SKILL.md</path>\n</skill>\n</available_skills>\n' \
  "UNPARSEABLE a  .sumela/skills/a/SKILL.md  ($P1)"
mal all-indented $'  <available_skills>\n  <skill activation="lazy">\n  <name>a</name>\n  <description>Use when a works.</description>\n  <path>.sumela/skills/a/SKILL.md</path>\n  </skill>\n  </available_skills>\n' \
  "UNPARSEABLE -  .sumela/SKILL_REGISTRY.md:2  (a <skill> line the registry grammar does not read: it is indented, or not followed by a space or >)"
mal tab-start $'<available_skills>\n<skill\tactivation="lazy">\n<name>a</name>\n<description>Use when a works.</description>\n<path>.sumela/skills/a/SKILL.md</path>\n</skill>\n</available_skills>\n' \
  "UNPARSEABLE -  .sumela/SKILL_REGISTRY.md:2  (a <skill> line the registry grammar does not read"
mal loose-description $'<available_skills>\n<skill activation="lazy">\n<name>a</name>\n<description>Use when a works (new).</description>\n   <description>Use when a works.</description>\n<path>.sumela/skills/a/SKILL.md</path>\n</skill>\n</available_skills>\n' \
  "UNPARSEABLE a  .sumela/skills/a/SKILL.md  (a tag line in the registry entry is indented, has text around it, or opens another block)"
mal one-line $'<available_skills>\nx <skill activation="lazy"><name>a</name><description>Use when a works.</description><path>.sumela/skills/a/SKILL.md</path></skill>\n</available_skills>\n' \
  "UNPARSEABLE -  .sumela/SKILL_REGISTRY.md  (the registry holds <skill text but no block its readers can parse)"
# The writer refuses a block with a loose line itself, whoever calls it.
reg="$WORK/mal-loose-description/.sumela/SKILL_REGISTRY.md"
rc=0; msg="$(sumela_registry_set_description "$reg" .sumela/skills/a/SKILL.md "Use when a works (newer)." 2>&1)" || rc=$?
same "the library refuses to rewrite a block that holds a loose line (exit 1)" 1 "$rc"
has "…saying why" "$msg" "holds a loose tag line"
unchanged "…and leaves the registry as it was" "$WORK/mal-loose-description.orig" "$reg"
# Only a well-formed entry whose file is absent is skipped, as before.
d="$WORK/mal-orphan"; mkdir -p "$d/.sumela"
printf '<available_skills>\n<skill activation="lazy">\n<name>gone</name>\n<description>X.</description>\n<path>.sumela/skills/gone/SKILL.md</path>\n</skill>\n</available_skills>\n' > "$d/.sumela/SKILL_REGISTRY.md"
run "$d" --check
same "a well-formed orphaned entry is still skipped: exit 0" 0 "$RC"
has "…and counted" "$OUT" "0 checked, 0 out of parity (0 drift, 0 attention, 0 unparseable), 1 skipped"

# ---------------------------------------------------------------------------------------------
echo "== t_unsafe_paths_are_unparseable"
d="$WORK/unsafe"; mkdir -p "$d/inst/.sumela" "$d/outside"
# A file outside the install with a frontmatter description: its text must never be printed.
skill "$d/outside/SKILL.md" outside '"SECRET OUTSIDE TEXT"'
{
  printf '<available_skills>\n'
  for p in "$d/outside/SKILL.md" ../outside/SKILL.md .sumela/../../outside/SKILL.md 'C:x/SKILL.md' '.sumela\skills\x\SKILL.md' ..; do
    printf '<skill activation="lazy">\n<name>u</name>\n<description>Old.</description>\n<path>%s</path>\n</skill>\n' "$p"
  done
  printf '</available_skills>\n'
} > "$d/inst/.sumela/SKILL_REGISTRY.md"
run "$d/inst" --plan
same "paths that leave the install: exit 3" 3 "$RC"
same "…each is an UNPARSEABLE row" 6 "$(printf '%s\n' "$OUT" | LC_ALL=C grep -c '^UNPARSEABLE u  .*(the path leaves the install (absolute, or with a .. segment): not read)$')"
has "…an absolute one included" "$OUT" "UNPARSEABLE u  $d/outside/SKILL.md  (the path leaves the install"
hasnt "…and the file outside is never read" "$OUT" "SECRET OUTSIDE TEXT"
has "…none is skipped" "$OUT" "6 checked, 6 out of parity (0 drift, 0 attention, 6 unparseable), 0 skipped"

# ---------------------------------------------------------------------------------------------
echo "== t_writers_keep_bytes"
d="$WORK/keep"; mkinstall "$d"; reg="$d/.sumela/SKILL_REGISTRY.md"; to_crlf "$reg"; cp "$reg" "$WORK/keep.orig"
rc=0; sumela_registry_add_entry "$reg" delta .sumela/memory-plugins/delta/SKILL.md "Use when delta — ö ş." || rc=$?
same "add_entry on a CRLF registry: exit 0" 0 "$rc"
tag="$(LC_ALL=C grep -n '^</available_skills>' "$WORK/keep.orig" | cut -d: -f1)"
same "…the lines before the closing tag are unchanged" "$(lines "$WORK/keep.orig" 1 $((tag - 1)) | od -c)" "$(lines "$reg" 1 $((tag - 1)) | od -c)"
same "…the new block ends every line with CRLF" \
  "$(printf '<skill activation="lazy">\r\n<name>delta</name>\r\n<description>Use when delta — ö ş.</description>\r\n<path>.sumela/memory-plugins/delta/SKILL.md</path>\r\n</skill>\r\n\r\n' | od -c)" \
  "$(lines "$reg" "$tag" $((tag + 5)) | od -c)"
same "…and what follows is unchanged" "$(LC_ALL=C tail -n +"$tag" "$WORK/keep.orig" | od -c)" "$(LC_ALL=C tail -n +$((tag + 6)) "$reg" | od -c)"
# A rendering with a line missing (a shim awk drops the last output line) is never renamed in.
REAL_AWK="$(command -v awk)"; mkdir -p "$WORK/shortawk"
printf '#!/bin/sh\n"%s" "$@" | sed '"'"'$d'"'"'\n' "$REAL_AWK" > "$WORK/shortawk/awk"; chmod +x "$WORK/shortawk/awk"
d="$WORK/short"; mkinstall "$d"; reg="$d/.sumela/SKILL_REGISTRY.md"; cp "$reg" "$WORK/short.orig"
rc=0; msg="$(PATH="$WORK/shortawk:$PATH"; sumela_registry_set_description "$reg" .sumela/skills/beta/SKILL.md "Use when beta work starts (new text)." 2>&1)" || rc=$?
same "a rendering one line short: exit 1" 1 "$rc"
has "…it says why" "$msg" "lines where"
unchanged "…and the registry is left as it was" "$WORK/short.orig" "$reg"
ls "$d/.sumela" | grep -q 'sumela-tmp' && bad "…no temp file is left behind" || ok "…no temp file is left behind"

# ---------------------------------------------------------------------------------------------
echo "== t_text_mode_awk_keeps_line_endings"
# Git for Windows' awk is an MSYS2 gawk: it opens its input files and stdin in text mode, so each
# CRLF reaches the program as LF unless the call passes -v BINMODE=3 (posix/gawkmisc.c). Without
# that, a sync turned a CRLF registry into an LF one on Git Bash. mkawk wraps the real awk to
# behave that way anywhere: "text" as Git for Windows' gawk does, "blind" dropping those CRs
# whatever the call says (an awk that cannot keep them: the writers' CR check must refuse it).
mkawk() {  # <dir> <text|blind>
  mkdir -p "$1"
  { printf '#!/usr/bin/env bash\nREAL=%s MODE=%s\n' "$(printf '%q' "$REAL_AWK")" "$2"
    cat <<'EOF'
tmp="$(mktemp -d)" || exit 2
trap 'rm -rf "$tmp"' EXIT
text() {  # stdin -> stdout, the CR before each LF dropped (a lone CR, and a last line without LF, kept)
  local l
  while IFS= read -r l; do printf '%s\n' "${l%$'\r'}"; done
  printf '%s' "$l"
}
bin=false prog=false files=0 n=0
set -- "$@" --end-of-arguments--
while [ "$1" != --end-of-arguments-- ]; do
  a="$1"; shift
  if [ "$prog" = false ]; then
    case "$a" in
      -v|-F|-f) v="$1"; shift; set -- "$@" "$a" "$v"
                if [ "$a" = -v ]; then case "$v" in BINMODE=1|BINMODE=3|BINMODE=*r*) bin=true ;; esac; fi
                if [ "$a" = -f ]; then prog=true; fi
                continue ;;
      -*) set -- "$@" "$a"; continue ;;
      *) prog=true; set -- "$@" "$a"; continue ;;
    esac
  fi
  case "$a" in *=*) set -- "$@" "$a"; continue ;; esac
  files=$((files + 1))
  if [ -f "$a" ] && { [ "$bin" = false ] || [ "$MODE" = blind ]; }; then
    n=$((n + 1)); text < "$a" > "$tmp/$n"; set -- "$@" "$tmp/$n"
  else set -- "$@" "$a"; fi
done
shift
if [ "$files" -eq 0 ] && { [ "$bin" = false ] || [ "$MODE" = blind ]; }; then text | "$REAL" "$@"; else "$REAL" "$@"; fi
EOF
  } > "$1/awk"
  chmod +x "$1/awk"
}
mkawk "$WORK/textawk" text; mkawk "$WORK/blindawk" blind
probe="$(printf 'a\r\nb\n' | PATH="$WORK/textawk:$PATH" awk '{ printf "%s|", $0 }')"
same "the text-mode awk drops the CR of a CRLF line read without BINMODE (the Git for Windows reading)" "a|b|" "$probe"
probe="$(printf 'a\r\nb\n' | PATH="$WORK/textawk:$PATH" awk -v BINMODE=3 '{ printf "%s|", $0 }' | LC_ALL=C tr '\r' '^')"
same "…and keeps it with BINMODE=3" "a^|b|" "$probe"
# want <variant> <file>: the expected registry, built without the library: the LF fixture with
# beta's description (and, for "add", a new delta block) in it, then given the variant's endings.
want() {
  LC_ALL=C awk -v BINMODE=3 -v n="$REG_BETA_LINE" -v s="$NEWBETA" -v add="$1" '
    add == "add" && $0 == "</available_skills>" { print "<skill activation=\"lazy\">"; print "<name>delta</name>"
      print "<description>Use when delta.</description>"; print "<path>.sumela/memory-plugins/delta/SKILL.md</path>"
      print "</skill>"; print "" }
    add != "add" && NR == n { print s; next }
    { print }' "$WORK/endings.lf" > "$2"
}
mkinstall "$WORK/endings"; cp "$WORK/endings/.sumela/SKILL_REGISTRY.md" "$WORK/endings.lf"
for shape in crlf mixed; do
  d="$WORK/endings-$shape"; mkinstall "$d"; reg="$d/.sumela/SKILL_REGISTRY.md"
  if [ "$shape" = crlf ]; then to_crlf "$reg"; else to_mixed "$reg"; fi
  commit_all "$d" "$shape"; cp "$reg" "$WORK/endings-$shape.orig"
  want sync "$WORK/endings-$shape.want"; want add "$WORK/endings-$shape.add"
  if [ "$shape" = crlf ]; then to_crlf "$WORK/endings-$shape.want"; to_crlf "$WORK/endings-$shape.add"
  else to_mixed "$WORK/endings-$shape.want"; to_mixed "$WORK/endings-$shape.add"; fi
  PATH="$WORK/textawk:$PATH" run "$d" --sync --yes
  same "$shape, under a text-mode awk: --sync --yes exits 0" 0 "$RC"
  unchanged "$shape: only beta's line changed, and every line kept its ending (the rewritten one too)" "$WORK/endings-$shape.want" "$reg"
  cp "$WORK/endings-$shape.orig" "$reg"
  rc=0; msg="$(PATH="$WORK/textawk:$PATH"; sumela_registry_add_entry "$reg" delta .sumela/memory-plugins/delta/SKILL.md "Use when delta." 2>&1)" || rc=$?
  same "$shape: add_entry under a text-mode awk exits 0" 0 "$rc"
  unchanged "$shape: …the new block ends as the line it went before; nothing else changed" "$WORK/endings-$shape.add" "$reg"
  cp "$WORK/endings-$shape.orig" "$reg"
  rc=0; msg="$(PATH="$WORK/blindawk:$PATH"; sumela_registry_set_description "$reg" .sumela/skills/beta/SKILL.md "Use when beta work starts (new text)." 2>&1)" || rc=$?
  same "$shape: an awk that drops the CRs is refused: exit 1" 1 "$rc"
  has "…the CR check says why" "$msg" "CR bytes where the registry holds $(crs "$WORK/endings-$shape.orig")"
  rc=0; msg="$(PATH="$WORK/blindawk:$PATH"; sumela_registry_add_entry "$reg" delta .sumela/memory-plugins/delta/SKILL.md "Use when delta." 2>&1)" || rc=$?
  same "$shape: …add_entry too: exit 1" 1 "$rc"
  unchanged "$shape: …and the registry is left as it was" "$WORK/endings-$shape.orig" "$reg"
  ls "$d/.sumela" | grep -q 'sumela-tmp' && bad "$shape: …no temp file is left behind" || ok "$shape: …no temp file is left behind"
done
d="$WORK/endings-crlf"
PATH="$WORK/blindawk:$PATH" run "$d" --sync --yes
same "the CLI under such an awk: exit 1" 1 "$RC"
has "…it stops at the write it could not make" "$OUT" "stopped at the first failed write (beta)"
unchanged "…and writes nothing" "$WORK/endings-crlf.orig" "$d/.sumela/SKILL_REGISTRY.md"
PATH="$WORK/blindawk:$PATH" run "$WORK/endings" --sync --yes
same "an LF registry has no CR to lose: the same awk syncs it (exit 0)" 0 "$RC"

# ---------------------------------------------------------------------------------------------
echo "== t_register_plugin"
# The one plugin writer, called directly (setup.sh and setup-memory.sh only map its exit codes).
d="$WORK/plug"; mkinstall "$d"; reg="$d/.sumela/SKILL_REGISTRY.md"
skill "$d/.sumela/memory-plugins/omega/SKILL.md" omega '"Use when omega memory is needed — ö ş ğ ı İ."'
commit_all "$d" omega; cp "$reg" "$WORK/plug.orig"
rc=0; sumela_registry_register_plugin "$d" omega || rc=$?
same "a new plugin: exit 0" 0 "$rc"
same "…its entry carries the frontmatter description verbatim" "Use when omega memory is needed — ö ş ğ ı İ." "$(reg_value "$reg" omega)"
files="$(LC_ALL=C awk '/^  "files": \[/ { f = 1; next } f && /^  \]/ { exit } f { sub(/^ *"/, ""); sub(/",?$/, ""); print }' "$d/.sumela/.last-update.json" 2>/dev/null)"
same "…and the write is recorded in the provenance record" ".sumela/SKILL_REGISTRY.md" "$files"
run "$d" --check
same "…parity stays 0 for it" "" "$(printf '%s\n' "$OUT" | grep 'omega')"
cp "$reg" "$WORK/plug.after"
rc=0; sumela_registry_register_plugin "$d" omega || rc=$?
same "already registered: exit 5" 5 "$rc"
unchanged "…and nothing written" "$WORK/plug.after" "$reg"
rc=0; sumela_registry_register_plugin "$d" missing || rc=$?
same "no SKILL.md: exit 2" 2 "$rc"
mkdir -p "$d/.sumela/memory-plugins/multi"; printf -- '---\nname: multi\ndescription: >\n  folded\n---\n' > "$d/.sumela/memory-plugins/multi/SKILL.md"
rc=0; sumela_registry_register_plugin "$d" multi || rc=$?
same "a multi-line description: exit 3" 3 "$rc"
skill "$d/.sumela/memory-plugins/empty/SKILL.md" empty '""'
rc=0; sumela_registry_register_plugin "$d" empty || rc=$?
same "an empty description: exit 3" 3 "$rc"
skill "$d/.sumela/memory-plugins/tagged/SKILL.md" tagged '"Use when </skill> appears."'
rc=0; sumela_registry_register_plugin "$d" tagged || rc=$?
same "a description holding </skill>: exit 4" 4 "$rc"
unchanged "every refusal left the registry unchanged" "$WORK/plug.after" "$reg"
mkdir -p "$WORK/plug-noreg/.sumela"
rc=0; sumela_registry_register_plugin "$WORK/plug-noreg" omega || rc=$?
same "no registry: exit 6" 6 "$rc"
d="$WORK/plug-crlf"; mkinstall "$d"; reg="$d/.sumela/SKILL_REGISTRY.md"; to_crlf "$reg"
skill "$d/.sumela/memory-plugins/omega/SKILL.md" omega '"Use when omega."'; commit_all "$d" crlf
rc=0; sumela_registry_register_plugin "$d" omega || rc=$?
same "a CRLF registry: exit 0" 0 "$rc"
same "…every line still ends with CRLF" "$(nlines "$reg")" "$(crs "$reg")"
d="$WORK/plug-rec"; mkinstall "$d"
skill "$d/.sumela/memory-plugins/omega/SKILL.md" omega '"Use when omega."'; commit_all "$d" rec
printf 'not a record\n' > "$d/.sumela/.last-update.json"
rc=0; msg="$(sumela_registry_register_plugin "$d" omega 2>&1)" || rc=$?
same "an unreadable provenance record: exit 7 (registered, not recorded)" 7 "$rc"
same "…the entry is written" "Use when omega." "$(reg_value "$d/.sumela/SKILL_REGISTRY.md" omega)"
has "…and the reason is named" "$msg" ".last-update.json"
d="$WORK/plug-notag"; mkdir -p "$d/.sumela"; printf '<skills_system>\n</skills_system>\n' > "$d/.sumela/SKILL_REGISTRY.md"
skill "$d/.sumela/memory-plugins/omega/SKILL.md" omega '"Use when omega."'
rc=0; msg="$(sumela_registry_register_plugin "$d" omega 2>&1)" || rc=$?
same "a registry without </available_skills>: exit 1" 1 "$rc"
has "…naming the missing line" "$msg" "no </available_skills> line"

# ---------------------------------------------------------------------------------------------
echo "== t_sync_stops_at_failed_write"
d="$WORK/stop"; mkinstall "$d"; reg="$d/.sumela/SKILL_REGISTRY.md"
skill "$d/.sumela/memory-plugins/gamma/SKILL.md" gamma "'Use when gamma memory is needed (new).'"
commit_all "$d" "two drift"; cp "$reg" "$WORK/stop.orig"
chmod a-w "$d/.sumela"
if ( : > "$d/.sumela/probe" ) 2>/dev/null; then
  rm -f "$d/.sumela/probe"; chmod u+w "$d/.sumela"
  skip "a read-only .sumela/ is still writable here (root, or no POSIX modes): the failed-write case"
else
  run "$d" --sync --yes
  chmod u+w "$d/.sumela"
  same "a failed write: exit 1" 1 "$RC"
  has "…the run says where it stopped" "$OUT" "sumela-registry-parity: stopped at the first failed write (beta); the entries after it were not checked"
  has "…and counts that entry as left" "$OUT" "2 checked, 0 synced, 1 out of parity (1 drift, 0 attention, 0 unparseable), 0 skipped"
  hasnt "…never claims parity" "$OUT" "0 out of parity"
  unchanged "…the registry is unchanged" "$WORK/stop.orig" "$reg"
  ls "$d/.sumela" | grep -q 'sumela-tmp' && bad "…no temp file is left behind" || ok "…no temp file is left behind"
fi

# ---------------------------------------------------------------------------------------------
echo "== t_interrupted_sync_leaves_no_temp"
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) skip "signals to a waiting script are emulated under this bash: the interrupt case" ;;
  *)
    d="$WORK/intr"; mkinstall "$d"; reg="$d/.sumela/SKILL_REGISTRY.md"
    mkfifo "$WORK/intr.fifo"
    # The sync waits for an answer on the fifo; a temp file named as its write would name it is
    # planted; TERM must remove it on the way out.
    ( cd "$d" && exec bash "$TOOL" --sync < "$WORK/intr.fifo" > "$WORK/intr.out" 2>&1 ) &
    pid=$!
    exec 7> "$WORK/intr.fifo"                  # open the writer end, so the reader's open returns
    n=0; while [ "$n" -lt 50 ] && ! LC_ALL=C grep -q 'y/N' "$WORK/intr.out" 2>/dev/null; do sleep 0.1; n=$((n + 1)); done
    : > "$reg.sumela-tmp.$pid"
    kill -TERM "$pid" 2>/dev/null; rc=0; wait "$pid" || rc=$?
    exec 7>&-
    same "an interrupted --sync exits 143 (TERM)" 143 "$rc"
    [ -e "$reg.sumela-tmp.$pid" ] && bad "…its temp file is removed" || ok "…its temp file is removed"
    ;;
esac

# ---------------------------------------------------------------------------------------------
echo "== t_writers_copy_verbatim"
QD=".sumela/memory-plugins/qdrant-session-memory/SKILL.md"
w="$WORK/writers"
# setup.sh and setup-memory.sh run end to end only where they are known to run: under Git Bash
# (Windows) the PowerShell suite covers the writers there, through setup.ps1 and setup-memory.ps1.
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) WINBASH=true ;; *) WINBASH=false ;; esac
if [ "$WINBASH" = true ]; then
  skip "setup.sh and setup-memory.sh end to end under Git Bash (tests/test_registry_parity.ps1 covers the Windows writers)"
elif seed "$w"; then
  strip_entry "$w/.sumela/SKILL_REGISTRY.md" qdrant-session-memory
  if grep -q '<name>qdrant-session-memory</name>' "$w/.sumela/SKILL_REGISTRY.md"; then bad "the fixture registry lost its qdrant entry"; fi
  cp "$w/.sumela/SKILL_REGISTRY.md" "$WORK/writers.stripped"
  want="$(fm_value "$w/$QD")"
  if ( cd "$w" && bash scripts/setup.sh --non-interactive --project-name "ParityProbe" --plugins qdrant-session-memory ) > "$WORK/writers.setup.log" 2>&1; then
    ok "setup.sh --plugins qdrant-session-memory succeeds"
  else bad "setup.sh --plugins qdrant-session-memory succeeds"; tail -8 "$WORK/writers.setup.log" | sed 's/^/      /'; fi
  same "setup.sh registers the plugin once" 1 "$(grep -c '<name>qdrant-session-memory</name>' "$w/.sumela/SKILL_REGISTRY.md")"
  same "setup.sh copies the frontmatter description verbatim (em dash included)" "$want" "$(reg_value "$w/.sumela/SKILL_REGISTRY.md" qdrant-session-memory)"
  run "$w" --check
  same "parity stays 0 after setup.sh" 0 "$RC"
  same "only the new block was added" "$(sed -n '/<\/available_skills>/=' "$WORK/writers.stripped")" \
    "$(( $(sed -n '/<\/available_skills>/=' "$w/.sumela/SKILL_REGISTRY.md") - 6 ))"
  # register_plugin, through setup-memory.sh: no pip download (empty requirements), no Qdrant (a
  # closed port), and stubs for the services it would otherwise look for.
  strip_entry "$w/.sumela/SKILL_REGISTRY.md" qdrant-session-memory
  : > "$w/.sumela/memory-plugins/qdrant-session-memory/requirements.txt"
  mkdir -p "$WORK/stubs"
  for t in ollama docker curl uv pipx graphify; do printf '#!/bin/sh\nexit 1\n' > "$WORK/stubs/$t"; chmod +x "$WORK/stubs/$t"; done
  if command -v python3 >/dev/null 2>&1; then
    smout="$(cd "$w" && PATH="$WORK/stubs:$PATH" QDRANT_HOST=127.0.0.1 QDRANT_PORT=9 bash scripts/setup-memory.sh --plugins qdrant-session-memory --non-interactive 2>&1)"
    has "register_plugin registers the plugin" "$smout" "Registered qdrant-session-memory in SKILL_REGISTRY.md"
    same "register_plugin copies the frontmatter description verbatim" "$want" "$(reg_value "$w/.sumela/SKILL_REGISTRY.md" qdrant-session-memory)"
    run "$w" --check
    same "parity stays 0 after register_plugin" 0 "$RC"
    cp "$w/.sumela/SKILL_REGISTRY.md" "$WORK/writers.bash"
    smout="$(cd "$w" && PATH="$WORK/stubs:$PATH" QDRANT_HOST=127.0.0.1 QDRANT_PORT=9 bash scripts/setup-memory.sh --plugins qdrant-session-memory --non-interactive 2>&1)"
    unchanged "a second register_plugin run changes nothing" "$WORK/writers.bash" "$w/.sumela/SKILL_REGISTRY.md"
    if [ -n "$PWSH" ]; then
      strip_entry "$w/.sumela/SKILL_REGISTRY.md" qdrant-session-memory
      smout="$(cd "$w" && PATH="$WORK/stubs:$PATH" QDRANT_HOST=127.0.0.1 QDRANT_PORT=9 "$PWSH" -NoProfile -File scripts/setup-memory.ps1 -Plugins qdrant-session-memory -NonInteractive 2>&1)"
      has "setup-memory.ps1's Register-Plugin registers the plugin" "$smout" "Registered qdrant-session-memory in SKILL_REGISTRY.md"
      unchanged "…with the same bytes as the bash writer" "$WORK/writers.bash" "$w/.sumela/SKILL_REGISTRY.md"
    else skip "setup-memory.ps1's Register-Plugin (pwsh unavailable)"; fi
  else skip "register_plugin (setup-memory.sh needs python3)"; fi
else bad "could not seed a clone of the repository"; fi

# ---------------------------------------------------------------------------------------------
echo "== t_source_repo_parity_zero"
run "$REPO_ROOT" --check
same "this repository: --check exits 0" 0 "$RC"
has "…with nothing out of parity" "$OUT" "0 out of parity (0 drift, 0 attention, 0 unparseable)"
v="$(fm_value "$REPO_ROOT/$QD")"
same "the qdrant frontmatter carries the registry's text (208 characters: 210 bytes with its em dash)" 210 \
  "$(printf '%s' "$v" | wc -c | tr -d ' ')"
same "…which is the registry's qdrant entry, byte for byte" "$(reg_value "$REPO_ROOT/.sumela/SKILL_REGISTRY.md" qdrant-session-memory)" "$v"

# ---------------------------------------------------------------------------------------------
echo "== t_validate_fails_in_source_warns_in_consumer"
v="$WORK/validate"
if seed "$v"; then
  RC=0; OUT="$(cd "$v" && bash scripts/validate-structure.sh 2>&1)" || RC=$?
  same "a clean source tree validates" 0 "$RC"
  has "…section 2b passes" "$OUT" "[PASS] Skill descriptions match their frontmatter ("
  f="$v/.sumela/skills/writing-plans/SKILL.md"
  LC_ALL=C sed 's/^description: "Use when starting implementation/description: "Use when beginning implementation/' "$f" > "$f.t" && mv "$f.t" "$f"
  RC=0; OUT="$(cd "$v" && bash scripts/validate-structure.sh 2>&1)" || RC=$?
  same "drift in the source repository (README marker present) FAILs: exit 1" 1 "$RC"
  has "…naming the count and the fixer" "$OUT" "[FAIL] Skill descriptions match their frontmatter — 1 drifted (fix: bash scripts/sumela-registry-parity.sh --sync)"
  has "…and showing the drifted entry" "$OUT" "DRIFT       writing-plans  .sumela/skills/writing-plans/SKILL.md"
  LC_ALL=C grep -v 'sumela:skill-count' "$v/README.md" > "$v/README.md.t" && mv "$v/README.md.t" "$v/README.md"
  RC=0; OUT="$(cd "$v" && bash scripts/validate-structure.sh 2>&1)" || RC=$?
  same "the same drift in a consumer (no marker) does not fail: exit 0" 0 "$RC"
  has "…it WARNs with the count and the fixer" "$OUT" "[WARN] registry descriptions drifted (1) — fix: bash scripts/sumela-registry-parity.sh --sync"
  hasnt "…and FAILs nothing" "$OUT" "[FAIL]"
  f="$v/.sumela/skills/secure-coding-standard/SKILL.md"
  LC_ALL=C sed 's/^description: "Use whenever the task involves/description: "Use when the task involves/' "$f" > "$f.t" && mv "$f.t" "$f"
  RC=0; OUT="$(cd "$v" && bash scripts/validate-structure.sh 2>&1)" || RC=$?
  same "an ATTENTION drift in a consumer still WARNs: exit 0" 0 "$RC"
  has "…counted in the warning" "$OUT" "[WARN] registry descriptions drifted (2) — fix:"
  has "…and shown as ATTENTION" "$OUT" "ATTENTION   secure-coding-standard"
  # An entry whose tags are indented is UNPARSEABLE: the warning names the hand fix for it.
  r="$v/.sumela/SKILL_REGISTRY.md"
  LC_ALL=C awk '/^<name>executing-plans<\/name>\r?$/ { f = 1 } f && /^<\/skill>/ { f = 0 } f { $0 = "  " $0 } { print }' "$r" > "$r.t" && mv "$r.t" "$r"
  RC=0; OUT="$(cd "$v" && bash scripts/validate-structure.sh 2>&1)" || RC=$?
  same "drift and an unparseable entry in a consumer: exit 0" 0 "$RC"
  has "…the warning names both fixes" "$OUT" "[WARN] registry descriptions drifted (3) — fix: bash scripts/sumela-registry-parity.sh --sync; 1 unparseable: fix those by hand, as each row says"
  git -C "$v" checkout -q -- .sumela/skills/writing-plans/SKILL.md .sumela/skills/secure-coding-standard/SKILL.md
  RC=0; OUT="$(cd "$v" && bash scripts/validate-structure.sh 2>&1)" || RC=$?
  same "only an unparseable entry in a consumer: exit 0" 0 "$RC"
  has "…the warning names the hand fix, not --sync" "$OUT" "[WARN] registry descriptions unparseable (1) — fix them by hand, as each row says; --sync never rewrites them"
  has "…and shows the entry" "$OUT" "UNPARSEABLE -  .sumela/SKILL_REGISTRY.md:"
  git -C "$v" checkout -q -- README.md
  RC=0; OUT="$(cd "$v" && bash scripts/validate-structure.sh 2>&1)" || RC=$?
  same "the same entry in the source repository FAILs: exit 1" 1 "$RC"
  has "…naming the hand fix" "$OUT" "[FAIL] Skill descriptions match their frontmatter — 1 unparseable (fix them by hand, as each row says; --sync never rewrites them)"
else bad "could not seed a clone of the repository"; fi

# ---------------------------------------------------------------------------------------------
echo "== t_registry_write_recorded_in_provenance"
d="$WORK/prov"; mkinstall "$d"; rec="$d/.sumela/.last-update.json"
run "$d" --sync --yes
same "a sync with a rewrite: exit 0" 0 "$RC"
head="$(git -C "$d" rev-parse HEAD)"; blob="$(git -C "$d" hash-object --no-filters -- .sumela/SKILL_REGISTRY.md)"
same "with no record, a minimal one names the registry in \"files\" and binds it to HEAD and its content" \
  "$(printf '{\n  "files": [\n    ".sumela/SKILL_REGISTRY.md"\n  ],\n  "carry_head": "%s",\n  "carry": ["%s .sumela/SKILL_REGISTRY.md"]\n}' "$head" "$blob")" \
  "$(cat "$rec" 2>/dev/null)"
# The carry is git hash-object --no-filters of the registry as written, in both twins: a CRLF
# registry is recorded with its CRs (a twin that lost them would record another blob).
d="$WORK/prov-crlf"; mkinstall "$d"; rec="$d/.sumela/.last-update.json"; reg="$d/.sumela/SKILL_REGISTRY.md"
to_crlf "$reg"; commit_all "$d" crlf
run "$d" --sync --yes
same "a CRLF registry: the sync exits 0" 0 "$RC"
same "…every line keeps its CRLF" "$(nlines "$reg")" "$(crs "$reg")"
blob="$(git -C "$d" hash-object --no-filters -- .sumela/SKILL_REGISTRY.md)"
has "…and the carry is the blob of those bytes" "$(cat "$rec" 2>/dev/null)" "\"carry\": [\"$blob .sumela/SKILL_REGISTRY.md\"]"
d="$WORK/prov2"; mkinstall "$d"; rec="$d/.sumela/.last-update.json"
cat > "$rec" <<'JSON'
{
  "updater_schema": 2,
  "version": "0.20.0",
  "base_version": "0.19.0",
  "upstream_commit": "",
  "updated_at": "2026-10-14T00:00:00Z",
  "pending_rerun": false,
  "partial_upgrade": false,
  "files": [
    ".sumela/skills/beta/SKILL.md"
  ],
  "merged": [],
  "kept": [],
  "theirs_over_fork": [],
  "removed": []
}
JSON
run "$d" --sync --yes
same "an existing record: the sync exits 0" 0 "$RC"
files="$(LC_ALL=C awk '/^  "files": \[/ { f = 1; next } f && /^  \]/ { exit } f { sub(/^ *"/, ""); sub(/",?$/, ""); print }' "$rec")"
same "…its \"files\" gains the registry, sorted, and keeps what it held" "$(printf '.sumela/SKILL_REGISTRY.md\n.sumela/skills/beta/SKILL.md')" "$files"
has "…and every other member is kept" "$(cat "$rec")" '"version": "0.20.0",'
d="$WORK/prov3"; mkinstall "$d"
run "$d" --sync
[ -e "$d/.sumela/.last-update.json" ] && bad "a declined sync writes no record" || ok "a declined sync writes no record"
d="$WORK/prov4"; mkinstall "$d"; rec="$d/.sumela/.last-update.json"
printf 'not a record\n' > "$rec"; cp "$rec" "$WORK/prov4.rec"
run "$d" --sync --yes
same "an unreadable record: the sync exits 1" 1 "$RC"
same "…the registry rewrite itself stands" "Use when beta work starts (new text)." "$(reg_value "$d/.sumela/SKILL_REGISTRY.md" beta)"
has "…and the message says the record was not updated" "$OUT" ".sumela/SKILL_REGISTRY.md was rewritten, but the provenance record"
unchanged "…which is left as it was" "$WORK/prov4.rec" "$rec"

# ---------------------------------------------------------------------------------------------
echo "== t_usage_and_errors"
d="$WORK/usage"; mkinstall "$d"
run "$d" --bogus;            same "an unknown argument: exit 2" 2 "$RC"
run "$d" --yes;              same "--yes without --sync: exit 2" 2 "$RC"
run "$d" --check --sync;     same "two modes: exit 2" 2 "$RC"
run "$d" --only;             same "--only without a name: exit 2" 2 "$RC"
run "$d" --only nobody;      same "--only with an unknown name: exit 2" 2 "$RC"
has "…naming it" "$OUT" "no registry entry is named 'nobody'"
mkdir -p "$WORK/noinstall"
run "$WORK/noinstall" --check; same "no .sumela/ above the working directory: exit 1" 1 "$RC"
mkdir -p "$WORK/noreg/.sumela"
run "$WORK/noreg" --check;   same "no registry: exit 1" 1 "$RC"
mkdir -p "$d/sub/dir"
run "$d/sub/dir" --check;    same "from a subdirectory, the install root is found above it" 3 "$RC"

# ---------------------------------------------------------------------------------------------
echo "== t_twins_agree"
if [ -z "$PWSH" ]; then
  skip "the PowerShell twin (pwsh unavailable)"
else
  # psrun <dir> <args>...: the PowerShell twin from <dir>; OUT has the bash twin's fixer spelling.
  psrun() {
    local d="$1"; shift; RC=0
    OUT="$(cd "$d" && "$PWSH" -NoProfile -NonInteractive -File "$PSTOOL" "$@" 2>&1 </dev/null)" || RC=$?
    OUT="$(printf '%s\n' "$OUT" | LC_ALL=C sed -e 's#powershell -NoProfile -File scripts/sumela-registry-parity.ps1 -Sync -Yes#bash scripts/sumela-registry-parity.sh --sync --yes#' \
      -e 's#powershell -NoProfile -File scripts/sumela-registry-parity.ps1 -Sync#bash scripts/sumela-registry-parity.sh --sync#')"
  }
  # same_bytes <label> <bash twin's file> <PowerShell twin's file>: on a difference, each side's
  # LF and CR counts (a lost line ending shows there) and the first differing bytes.
  same_bytes() {
    if cmp -s "$2" "$3"; then ok "$1"; return; fi
    bad "$1"
    printf '      bash: %s LF, %s CR; PowerShell: %s LF, %s CR\n' "$(nlines "$2")" "$(crs "$2")" "$(nlines "$3")" "$(crs "$3")"
    cmp -l "$2" "$3" 2>&1 | head -4 | sed 's/^/      /'
  }
  # Each variant answers its own way (one line each for beta, then secure-coding-standard): lf
  # plainly; crlf as a Windows pipe may, with CRLF line ends and the BOM Windows PowerShell 5.1
  # writes first; mixed with "yes" and a CRLF, then a declining "No".
  for variant in lf crlf mixed; do
    b="$WORK/twin-$variant-bash"; p="$WORK/twin-$variant-ps"
    for t in "$b" "$p"; do
      mkinstall "$t"
      skill "$t/.sumela/skills/secure-coding-standard/SKILL.md" secure-coding-standard '"Use whenever code is touched — ö."'
      printf -- '---\nname: gamma\ndescription: |\n  block\n---\n' > "$t/.sumela/memory-plugins/gamma/SKILL.md"
      case "$variant" in
        crlf) for f in "$t/.sumela/SKILL_REGISTRY.md" "$t"/.sumela/skills/*/SKILL.md; do to_crlf "$f"; done ;;
        mixed) to_mixed "$t/.sumela/SKILL_REGISTRY.md" ;;
      esac
      commit_all "$t" "$variant"
    done
    cp "$b/.sumela/SKILL_REGISTRY.md" "$WORK/twin-$variant-bash.orig"
    case "$variant" in
      lf) answers='y\nn\n' ;;
      crlf) answers='\357\273\277y\r\nn\r\n' ;;
      mixed) answers='yes\r\nNo\n' ;;
    esac
    for mode in check plan; do
      run "$b" "--$mode"; bo="$OUT"; brc="$RC"
      if [ "$mode" = check ]; then psrun "$p" -Check; else psrun "$p" -Plan; fi
      same "$variant $mode: the same exit code" "$brc" "$RC"
      if [ "$bo" = "$OUT" ]; then ok "$variant $mode: the same lines"; else bad "$variant $mode: the same lines"; diff <(printf '%s\n' "$bo") <(printf '%s\n' "$OUT") | head -8 | sed 's/^/      /'; fi
    done
    # shellcheck disable=SC2059   # the answers are a printf format: their escapes are the bytes
    RC=0; bo="$(cd "$b" && printf "$answers" | bash "$TOOL" --sync 2>&1)" || RC=$?; brc="$RC"
    # shellcheck disable=SC2059
    RC=0; OUT="$(cd "$p" && printf "$answers" | "$PWSH" -NoProfile -NonInteractive -File "$PSTOOL" -Sync 2>&1)" || RC=$?
    OUT="$(printf '%s\n' "$OUT" | LC_ALL=C sed 's#powershell -NoProfile -File scripts/sumela-registry-parity.ps1 -Sync -Yes#bash scripts/sumela-registry-parity.sh --sync --yes#')"
    same "$variant answered sync: the same exit code" "$brc" "$RC"
    if [ "$bo" = "$OUT" ]; then ok "$variant answered sync: the same lines"; else bad "$variant answered sync: the same lines"; diff <(printf '%s\n' "$bo") <(printf '%s\n' "$OUT") | head -8 | sed 's/^/      /'; fi
    has "$variant answered sync: the first entry is synced" "$bo" "synced      beta"
    same_bytes "$variant answered sync: the same registry bytes" "$b/.sumela/SKILL_REGISTRY.md" "$p/.sumela/SKILL_REGISTRY.md"
    run "$b" --sync --yes; psrun "$p" -Sync -Yes
    same_bytes "$variant --sync --yes: the same registry bytes" "$b/.sumela/SKILL_REGISTRY.md" "$p/.sumela/SKILL_REGISTRY.md"
    same "$variant --sync --yes: the bash twin kept every CR the registry had" "$(crs "$WORK/twin-$variant-bash.orig")" "$(crs "$b/.sumela/SKILL_REGISTRY.md")"
    same_bytes "$variant --sync --yes: the same provenance record" "$b/.sumela/.last-update.json" "$p/.sumela/.last-update.json"
  done
  # The malformed registries and the paths that leave the install: the same rows and exit codes.
  for t in mal-indented mal-trailing mal-lost-end mal-all-indented mal-tab-start mal-loose-description mal-one-line mal-orphan unsafe/inst; do
    run "$WORK/$t" --plan; bo="$OUT"; brc="$RC"
    psrun "$WORK/$t" -Plan
    if [ "$bo" = "$OUT" ] && [ "$brc" = "$RC" ]; then ok "$t: the same lines and exit code ($RC)"
    else bad "$t: the same lines and exit code (bash $brc, PowerShell $RC)"; diff <(printf '%s\n' "$bo") <(printf '%s\n' "$OUT") | head -8 | sed 's/^/      /'; fi
  done
  psrun "$REPO_ROOT" -Check
  same "the PowerShell twin: this repository is in parity" 0 "$RC"
  psrun "$WORK/usage" -Bogus; same "the PowerShell twin: an unknown argument exits 2" 2 "$RC"
fi

echo ""
echo "registry-parity: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
