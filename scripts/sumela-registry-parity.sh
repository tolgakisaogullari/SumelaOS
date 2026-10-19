#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# sumela-registry-parity.sh — skill-description parity between .sumela/SKILL_REGISTRY.md and each
# skill's SKILL.md frontmatter (v0.20.0+).
#
# A registry <description> is the dispatcher's routing surface, so it must equal the skill's
# frontmatter description byte for byte (the comparison and the registry grammar are defined in
# scripts/lib/sumela-registry.sh). The registry is an overlay file the updater never touches, so a
# release that changes a skill's frontmatter leaves the registry behind. This script finds that
# drift and, with consent, copies each drifted frontmatter description into its registry entry.
# Only the <description> line of a drifted entry changes; every other byte of the registry,
# including CRLF line endings, is kept.
#
# Usage, from anywhere inside the install (the install root is the nearest ancestor of the working
# directory that holds .sumela/):
#   bash scripts/sumela-registry-parity.sh [--check]      report drift (the default)
#   bash scripts/sumela-registry-parity.sh --plan         report it with one diff per drifted entry
#   bash scripts/sumela-registry-parity.sh --sync         show each diff, ask, rewrite on "y"
#   bash scripts/sumela-registry-parity.sh --sync --yes   rewrite every drifted entry without asking:
#                                                         agent mode, only after the developer consented
#   add --only <name> to any of them for the one registry entry with that <name>.
#
# Each entry out of parity prints one row: a label, the entry's <name>, its <path> (or, when it has
# none, the registry line its block starts on).
#   DRIFT        the registry <description> differs from the frontmatter description.
#   ATTENTION    the same, in a security-routing skill (secure-coding-standard,
#                requesting-code-review, receiving-code-review, verification-before-completion):
#                review that diff before it is synced.
#   UNPARSEABLE  an entry that cannot be checked, or a side that must not be copied: a block without
#                exactly one <path> line or one <description> line, a loose tag line (indented, with
#                text around it, or a block whose </skill> was lost), a <skill> line the registry
#                grammar does not read, a <path> that leaves the install (absolute, or with a ..
#                segment), multi-line YAML, no description or an empty one, or a description that
#                holds </description> or </skill>. Fix it by hand; --sync never rewrites it.
# Then one summary line:
#   sumela-registry-parity: <n> checked, <m> out of parity (<d> drift, <a> attention, <u> unparseable), <s> skipped
# (with --sync: "<n> checked, <k> synced, <m> out of parity (...), <s> skipped", <m> counting what is
# left). Only a well-formed entry whose <path> is not a file is skipped: orphaned entries belong to
# scripts/reconcile-registry.py, whose --check keeps its meaning. A run that stops early (a write
# that failed, a skill that cannot be read) says so before the summary; the entries after that
# point are not checked.
#
# --sync reads one answer per entry from stdin: "y" or "yes" rewrites it; anything else, or no
# answer at all (end of input, as in an agent's shell), declines it. An answer is one line of
# stdin, read as bytes, without one UTF-8 byte order mark before it and one CR after it: a Windows
# pipe can end each line in CRLF, and Windows PowerShell 5.1 starts what it writes to a child's
# stdin with a BOM when the console code page is UTF-8. Each rewrite goes through a temp file and
# a rename and is re-read; the temp file is removed if the run is interrupted. Every line keeps
# its own ending, on Git Bash too (scripts/lib/sumela-registry.sh). After a rewrite,
# .sumela/SKILL_REGISTRY.md is added to the provenance record's "files"
# (scripts/lib/sumela-provenance.sh), so the self-modification guard knows that a framework tool,
# not the developer, wrote that diff. Its "carry" entry is `git hash-object --no-filters` of the
# registry as written, in both twins: the same registry bytes give the same record.
#
# Exit: 0 every checked entry is in parity (after --sync: none is left out of parity);
#       1 error: no install root or registry, a skill that cannot be read, a write that failed or
#         did not re-read, or the provenance record not updated (the registry rewrite itself
#         stands; the message says so);
#       2 usage; 3 out of parity (after --sync: entries declined or unparseable).
# The PowerShell twin, scripts/sumela-registry-parity.ps1 (-Check, -Plan, -Sync, -Yes, -Only <name>),
# prints the same lines (naming its own command as the fixer) and writes the same bytes.
# -----------------------------------------------------------------------------
if [ -z "${BASH_VERSION:-}" ]; then
  echo "sumela-registry-parity: run it with bash: bash scripts/sumela-registry-parity.sh" >&2
  exit 2
fi
set -uo pipefail
export LC_ALL=C

ME="sumela-registry-parity"
FIXER="bash scripts/sumela-registry-parity.sh --sync"
usage() { echo "usage: bash scripts/sumela-registry-parity.sh [--check | --plan | --sync [--yes]] [--only <name>]"; }
die_usage() { echo "$ME: $1" >&2; usage >&2; exit 2; }

MODE="" YES=false ONLY="" ONLY_SET=false
while [ $# -gt 0 ]; do
  case "$1" in
    --check|--plan|--sync)
      if [ -n "$MODE" ] && [ "$MODE" != "${1#--}" ]; then die_usage "--$MODE and $1 exclude each other"; fi
      MODE="${1#--}" ;;
    --yes|-y) YES=true ;;
    --only)
      if [ $# -lt 2 ] || [ -z "$2" ]; then die_usage "--only needs a skill name"; fi
      ONLY="$2"; ONLY_SET=true; shift ;;
    -h|--help)
      usage
      echo "Reports skill-description drift between the registry and the skills, and repairs it with consent; see the header of this file."
      exit 0 ;;
    *) die_usage "unknown argument: $1" ;;
  esac
  shift
done
[ -n "$MODE" ] || MODE=check
if [ "$YES" = true ] && [ "$MODE" != sync ]; then die_usage "--yes goes with --sync"; fi

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib" || { echo "$ME: cannot find the scripts directory" >&2; exit 1; }
for lib in sumela-provenance.sh sumela-registry.sh; do
  if [ ! -f "$LIB_DIR/$lib" ]; then echo "$ME: $LIB_DIR/$lib is missing" >&2; exit 1; fi
done
# shellcheck source=lib/sumela-registry.sh
. "$LIB_DIR/sumela-registry.sh"                 # loads sumela-provenance.sh too

ROOT="$PWD"
while [ ! -d "$ROOT/.sumela" ]; do
  up="$(dirname "$ROOT")"
  [ "$up" = "$ROOT" ] && break
  ROOT="$up"
done
if [ ! -d "$ROOT/.sumela" ]; then echo "$ME: no .sumela/ in $PWD or above it: not inside a SumelaOS install" >&2; exit 1; fi
REG_REL=".sumela/SKILL_REGISTRY.md"
REG="$ROOT/$REG_REL"
if [ ! -f "$REG" ]; then echo "$ME: $REG not found" >&2; exit 1; fi

T="$(mktemp -d)" || { echo "$ME: cannot create a temporary directory" >&2; exit 1; }
# The library writes through "$REG.sumela-tmp.$$": an interrupted run must not leave it behind.
trap 'rm -rf "$T"; rm -f "$REG.sumela-tmp.$$"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
if ! sumela_registry_rows "$REG" > "$T/rows"; then echo "$ME: cannot read $REG" >&2; exit 1; fi

TAB="	"
split_row() {  # <B row> -> sets r_line r_count r_paths r_loose r_bline r_name r_path r_desc
  local rest="${1#*"$TAB"}"
  r_line="${rest%%"$TAB"*}"; rest="${rest#*"$TAB"}"
  r_count="${rest%%"$TAB"*}"; rest="${rest#*"$TAB"}"
  r_paths="${rest%%"$TAB"*}"; rest="${rest#*"$TAB"}"
  r_loose="${rest%%"$TAB"*}"; rest="${rest#*"$TAB"}"
  r_bline="${rest%%"$TAB"*}"; rest="${rest#*"$TAB"}"
  r_name="${rest%%"$TAB"*}"; rest="${rest#*"$TAB"}"
  r_path="${rest%%"$TAB"*}"; r_desc="${rest#*"$TAB"}"
}

if [ "$ONLY_SET" = true ]; then
  found=false
  while IFS= read -r row || [ -n "$row" ]; do
    case "$row" in B"$TAB"*) ;; *) continue ;; esac
    split_row "$row"
    if [ "$r_name" = "$ONLY" ]; then found=true; break; fi
  done < "$T/rows"
  if [ "$found" != true ]; then echo "$ME: no registry entry is named '$ONLY' in $REG_REL" >&2; exit 2; fi
fi

is_security_routing() {  # <name> <path>
  case "$1" in secure-coding-standard|requesting-code-review|receiving-code-review|verification-before-completion) return 0 ;; esac
  case "$2" in
    .sumela/skills/secure-coding-standard/*|.sumela/skills/requesting-code-review/*|\
    .sumela/skills/receiving-code-review/*|.sumela/skills/verification-before-completion/*) return 0 ;;
  esac
  return 1
}
print_row() {  # <label> <name> <path> [<note>]
  if [ -n "${4:-}" ]; then printf '%-11s %s  %s  (%s)\n' "$1" "${2:--}" "$3" "$4"
  else printf '%-11s %s  %s\n' "$1" "${2:--}" "$3"; fi
}
print_diff() {  # <line> <name> <registry description> <frontmatter description>
  printf '%s\n' "--- a/$REG_REL" "+++ b/$REG_REL" "@@ -$1 +$1 @@ ${2:--}" \
    "-<description>$3</description>" "+<description>$4</description>"
}
ask() {  # <name>: 0 on "y" or "yes"; no answer (end of input) declines
  local a=""
  printf 'Sync the registry description of %s from its frontmatter? [y/N] ' "${1:--}"
  if IFS= read -r a || [ -n "$a" ]; then
    [ -t 0 ] || printf '\n'
  else
    printf '\n'
    return 1
  fi
  a="${a#$'\357\273\277'}"; a="${a%$'\r'}"         # one UTF-8 BOM before it, one CR after it
  case "$a" in y|Y|yes|Yes|YES) return 0 ;; esac
  return 1
}

LOOSE_IN="a tag line in it is indented, has text around it, or opens another block"
n_checked=0 n_skip=0 n_drift=0 n_attn=0 n_unp=0 n_synced=0 l_drift=0 l_attn=0 n_rows=0
wrote=false failed=false stopped=""
while IFS= read -r row <&3 || [ -n "$row" ]; do
  n_rows=$((n_rows + 1))
  case "$row" in
    L"$TAB"*)                                      # a block start no reader sees
      [ "$ONLY_SET" = true ] && continue
      n_checked=$((n_checked + 1)); n_unp=$((n_unp + 1))
      print_row UNPARSEABLE "" "$REG_REL:${row#*"$TAB"}" "a <skill> line the registry grammar does not read: it is indented, or not followed by a space or >"
      continue ;;
  esac
  split_row "$row"
  if [ "$ONLY_SET" = true ] && [ "$r_name" != "$ONLY" ]; then continue; fi
  where="${r_path:-$REG_REL:$r_bline}"
  note=""
  if [ "$r_paths" != 1 ]; then
    note="the registry entry does not hold exactly one <path> line"
    [ "$r_loose" = 0 ] || note="$note; $LOOSE_IN"
  else
    case "$r_path" in
      /*|\\*|[A-Za-z]:*|..|../*|*/..|*/../*|*\\*) note="the path leaves the install (absolute, or with a .. segment): not read" ;;
      *) if [ ! -f "$ROOT/$r_path" ]; then n_skip=$((n_skip + 1)); continue; fi ;;
    esac
  fi
  n_checked=$((n_checked + 1))
  if [ -z "$note" ]; then
    if [ "$r_count" != 1 ]; then
      note="the registry entry does not hold exactly one <description> line"
      [ "$r_loose" = 0 ] || note="$note; $LOOSE_IN"
    elif [ "$r_loose" != 0 ]; then
      note="a tag line in the registry entry is indented, has text around it, or opens another block"
    fi
  fi
  if [ -z "$note" ]; then
    fm_rc=0; fm="$(sumela_fm_description "$ROOT/$r_path")" || fm_rc=$?
    case "$fm_rc" in
      0) case "$fm" in
           '') note="the frontmatter description is empty" ;;
           *"</description>"*|*"</skill>"*) note="the frontmatter description holds </description> or </skill>, which the registry cannot hold" ;;
         esac ;;
      1) note="the frontmatter has no description: line" ;;
      3) note="the frontmatter description is not one line: a block scalar, an open quote or a continuation line" ;;
      *) echo "$ME: cannot read $ROOT/$r_path" >&2; failed=true; stopped="$r_path, which cannot be read"; break ;;
    esac
    if [ -z "$note" ] && [ "$fm" = "$r_desc" ]; then continue; fi        # in parity
  fi
  if [ -n "$note" ]; then
    if is_security_routing "$r_name" "$r_path"; then note="$note; a security-routing skill"; fi
    print_row UNPARSEABLE "$r_name" "$where" "$note"
    n_unp=$((n_unp + 1)); continue
  fi

  if is_security_routing "$r_name" "$r_path"; then
    label=ATTENTION; n_attn=$((n_attn + 1))
    print_row ATTENTION "$r_name" "$r_path" "security routing: review this diff before it is synced"
  else
    label=DRIFT; n_drift=$((n_drift + 1))
    print_row DRIFT "$r_name" "$r_path"
  fi
  [ "$MODE" = check ] && continue
  print_diff "$r_line" "$r_name" "$r_desc" "$fm"
  [ "$MODE" = plan ] && continue

  if [ "$YES" = true ] || ask "$r_name"; then
    set_rc=0; sumela_registry_set_description "$REG" "$r_path" "$fm" || set_rc=$?
    if [ "$set_rc" -eq 0 ]; then
      wrote=true; n_synced=$((n_synced + 1))
      echo "synced      ${r_name:--}"
      continue
    fi
    echo "$ME: could not rewrite the entry for $r_path in $REG_REL (exit $set_rc)" >&2
    failed=true; stopped="the first failed write (${r_name:--})"
  else
    echo "declined    ${r_name:--}"
  fi
  if [ "$label" = ATTENTION ]; then l_attn=$((l_attn + 1)); else l_drift=$((l_drift + 1)); fi
  [ -n "$stopped" ] && break
done 3< "$T/rows"

# A registry that holds <skill text but no block or block start the grammar sees parses as empty:
# never a pass. (awk with BINMODE=3, not grep: a CR stays part of its line on every platform.)
if [ "$n_rows" -eq 0 ] && [ "$ONLY_SET" != true ] &&
   LC_ALL=C awk -v BINMODE=3 '/<skill([ >\t]|$)/ { f = 1; exit } END { exit !f }' "$REG"; then
  n_checked=$((n_checked + 1)); n_unp=$((n_unp + 1))
  print_row UNPARSEABLE "" "$REG_REL" "the registry holds <skill text but no block its readers can parse"
fi

if [ "$wrote" = true ]; then
  if ! sumela_registry_record "$ROOT"; then
    echo "$ME: $REG_REL was rewritten, but the provenance record $ROOT/.sumela/.last-update.json was not updated" >&2
    failed=true
  fi
fi

[ -z "$stopped" ] || echo "$ME: stopped at $stopped; the entries after it were not checked"
if [ "$MODE" = sync ]; then
  n_left=$((l_drift + l_attn + n_unp))
  echo "$ME: $n_checked checked, $n_synced synced, $n_left out of parity ($l_drift drift, $l_attn attention, $n_unp unparseable), $n_skip skipped"
  if [ "$failed" != true ] && [ $((l_drift + l_attn)) -gt 0 ]; then
    echo "declined entries stay as they are: answer y to sync one, or run $FIXER --yes once the developer consents"
  fi
else
  n_left=$((n_drift + n_attn + n_unp))
  echo "$ME: $n_checked checked, $n_left out of parity ($n_drift drift, $n_attn attention, $n_unp unparseable), $n_skip skipped"
  if [ $((n_drift + n_attn)) -gt 0 ]; then echo "fix: $FIXER"; fi
fi
if [ "$n_unp" -gt 0 ]; then echo "hand fix: each UNPARSEABLE row says what to change; --sync never rewrites it"; fi

[ "$failed" = true ] && exit 1
[ "$n_left" -eq 0 ] && exit 0
exit 3
