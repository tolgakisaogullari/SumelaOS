# shellcheck shell=bash
# -----------------------------------------------------------------------------
# tests/lib/upgrade-fixture.sh — fake SumelaOS upstreams and forked consumers for the updater
# suites (R1-04; the R1-05 and R1-06 suites reuse it). Sourced, never run. Everything here is
# synthetic: generic file names, generic text, example.com identities.
#
# An upstream is a git repository holding a minimal SumelaOS tree. Each text file has 30 numbered
# lines ("alpha line 7"), so a test can change line 3 on one side and line 25 on the other (a
# clean merge) or line 10 on both (a conflict). git merge-file treats ADJACENT changes as a
# conflict: keep edits that should merge cleanly at least two lines apart.
#
#   fx_upstream <dir>
#       Writes the base tree into a new repository and commits nothing. Files:
#         .sumela/VERSION, .sumela/sumela-prompt.md, .sumela/rules/security_protocol.md,
#         .sumela/skills/{alpha,beta,gamma}/SKILL.md, .sumela/git-hooks/pre-commit (100755),
#         scripts/tool.sh (100755), docs/second-brain/template/wiki/_SCHEMA.md,
#         .sumela/SKILL_REGISTRY.md (the upstream's own overlay copy: not CORE).
#   fx_release <dir> <version> [--no-tag]
#       Writes .sumela/VERSION, commits every change (additions and deletions), and tags
#       v<version> (lightweight) unless --no-tag. Prints nothing.
#   fx_consumer <dir> <upstream> <tree-ish> [<install-subdir>]
#       A consumer repository whose install (the repository itself, or <install-subdir> of it)
#       is the upstream's .sumela, scripts and docs/second-brain/template at <tree-ish>, read
#       with git archive so modes are kept, plus an overlay (AGENTS.md, SKILL_REGISTRY.md, a
#       .gitignore with the runtime entries, a repository README outside a subdirectory install).
#       Committed. The install directory is <dir>[/<install-subdir>].
#   fx_commit <dir> [<message>]                       commits every change in the repository
#   fx_updater_stub <file> <label> [--v020]           a stand-in updater; --v020 marks it v0.20.0+
#   fx_set_line <file> <n> <text>                     replaces line n (LF; the file keeps its mode)
#   fx_del_line <file> <n>                            deletes line n
#   fx_crlf <file>                                    rewrites every line ending as CR LF
#   fx_lines <word> <count>                           prints "<word> line 1" ... "<word> line <count>"
#   fx_record_v1 <install> <version> <path>...        a record as v0.19's update.sh wrote it
#   fx_record_v2 <install> <version> <upstream-commit> <path>...
#                                                     a v2 record of a complete run vouching for <path>...
#   fx_old_updater_pass <install> <upstream> <tree-ish> <path>...
#       What a pre-0.20 updater did on an empty answer: the paths overwritten with the upstream's
#       copy, VERSION stamped with that tree's version, a v1 record listing the paths. Uncommitted.
#   fx_update <install> <upstream> <log> [<arg>...]
#       Runs THIS repository's scripts/update.sh --source <upstream> [<arg>...] from <install>,
#       under the bash running the suite, stdin from /dev/null, output to <log>. Returns its exit.
#   fx_env <command>...                               runs <command> with QDRANT_HOST/QDRANT_PORT
#                                                     on a closed port (fx_update does this)
#
# Requires git 2.28+ (init -b). Callers set their own pass/fail reporting.
# -----------------------------------------------------------------------------

FX_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FX_TAB="$(printf '\t')"
# A suite's repositories never read the machine's system git config, and never run the
# developer's hooks (fx_git_init points core.hooksPath at an empty directory). The global config
# still applies: the CI job sets core.autocrlf there for the CRLF run.
export GIT_CONFIG_NOSYSTEM=1

fx_lines() { local i=1; while [ "$i" -le "$2" ]; do printf '%s line %d\n' "$1" "$i"; i=$((i + 1)); done; }

fx_git_init() {  # <dir>: a repository with a local identity and no hooks
  mkdir -p "$1" && git -C "$1" init -q -b main && git -C "$1" config user.email fixture@example.com &&
    git -C "$1" config user.name Fixture && git -C "$1" config commit.gpgsign false &&
    mkdir -p "$1/.git/fx-no-hooks" && git -C "$1" config core.hooksPath "$1/.git/fx-no-hooks"
}

fx_updater_stub() {  # <file> <label> [--v020]: a stand-in scripts/update.sh; --v020 carries the
                     # marker every v0.20.0+ updater has (it writes the v2 record)
  { printf '#!/usr/bin/env bash
echo "updater stub %s"
' "$2"
    [ "${3:-}" = --v020 ] && echo "# writes the provenance record with sumela_record_write"
  } > "$1" && chmod 755 "$1"
}

fx_upstream() {  # <dir>
  local d="$1"
  fx_git_init "$d" || return 1
  mkdir -p "$d/.sumela/rules" "$d/.sumela/skills/alpha" "$d/.sumela/skills/beta" "$d/.sumela/skills/gamma" \
           "$d/.sumela/git-hooks" "$d/scripts" "$d/docs/second-brain/template/wiki"
  echo 0.19.0 > "$d/.sumela/VERSION"
  fx_lines prompt 30 > "$d/.sumela/sumela-prompt.md"
  fx_lines security 30 > "$d/.sumela/rules/security_protocol.md"
  fx_lines alpha 30 > "$d/.sumela/skills/alpha/SKILL.md"
  fx_lines beta 30 > "$d/.sumela/skills/beta/SKILL.md"
  fx_lines gamma 30 > "$d/.sumela/skills/gamma/SKILL.md"
  { echo '#!/usr/bin/env bash'; fx_lines hook 30 | sed 's/^/# /'; } > "$d/.sumela/git-hooks/pre-commit"
  { echo '#!/usr/bin/env bash'; fx_lines tool 30 | sed 's/^/# /'; } > "$d/scripts/tool.sh"
  chmod 755 "$d/.sumela/git-hooks/pre-commit" "$d/scripts/tool.sh"
  fx_lines schema 30 > "$d/docs/second-brain/template/wiki/_SCHEMA.md"
  echo "upstream registry" > "$d/.sumela/SKILL_REGISTRY.md"
}

fx_release() {  # <dir> <version> [--no-tag]
  echo "$2" > "$1/.sumela/VERSION"
  git -C "$1" add -A . && git -C "$1" commit -q -m "release $2" || return 1
  [ "${3:-}" = --no-tag ] || git -C "$1" tag "v$2"
}

fx_commit() { git -C "$1" add -A . && git -C "$1" commit -q -m "${2:-change}"; }

fx_consumer() {  # <dir> <upstream> <tree-ish> [<install-subdir>]
  local d="$1" up="$2" ref="$3" sub="${4:-}" inst tarball
  inst="$d${sub:+/$sub}"
  fx_git_init "$d" || return 1
  mkdir -p "$inst" || return 1
  tarball="$d.fixture.tar"
  git -C "$up" archive --format=tar -o "$tarball" "$ref" -- .sumela scripts docs/second-brain/template &&
    tar -xf "$tarball" -C "$inst" && rm -f "$tarball" || return 1
  rm -f "$inst/.sumela/SKILL_REGISTRY.md"
  echo "consumer registry" > "$inst/.sumela/SKILL_REGISTRY.md"
  echo "consumer agents file" > "$inst/AGENTS.md"
  printf '%s\n' .sumela/.last-update.json .sumela/.upgrade/ scripts/update.sh.bak scripts/update.ps1.bak > "$inst/.gitignore"
  [ -z "$sub" ] || echo "a repository with more than one project" > "$d/README.md"
  fx_commit "$d" "install SumelaOS at $ref"
}

# The edits rewrite the file in place (cat, not mv), so it keeps its mode: a hook stays 100755.
fx_rewrite() { cat "$1.fx" > "$1" && rm -f "$1.fx"; }
fx_set_line() {  # <file> <n> <text>
  t="$3" LC_ALL=C awk -v n="$2" 'BEGIN { t = ENVIRON["t"] } { sub(/\r$/, "") } NR == n { print t; next } { print }' "$1" > "$1.fx" &&
    fx_rewrite "$1"
}
fx_del_line() { LC_ALL=C awk -v n="$2" '{ sub(/\r$/, "") } NR != n { print }' "$1" > "$1.fx" && fx_rewrite "$1"; }
fx_crlf() { LC_ALL=C awk '{ sub(/\r$/, ""); printf "%s\r\n", $0 }' "$1" > "$1.fx" && fx_rewrite "$1"; }

fx_json_list() {  # <indent> <path>... -> the "files" lines of a record
  local ind="$1" n=0 total p; shift; total=$#
  for p in "$@"; do n=$((n + 1)); if [ "$n" -lt "$total" ]; then printf '%s"%s",\n' "$ind" "$p"; else printf '%s"%s"\n' "$ind" "$p"; fi; done
}
fx_record_v1() {  # <install> <version> <path>...
  local inst="$1" v="$2"; shift 2
  {
    printf '{\n  "version": "%s",\n  "updated_at": "2026-10-01T00:00:00Z",\n  "pending_rerun": false,\n  "files": [\n' "$v"
    fx_json_list '    ' "$@"
    printf '  ]\n}\n'
  } > "$inst/.sumela/.last-update.json"
}
fx_record_v2() {  # <install> <version> <upstream-commit> <path>...
  local inst="$1" v="$2" uc="$3"; shift 3
  {
    printf '{\n  "updater_schema": 2,\n  "version": "%s",\n  "base_version": "0.18.0",\n' "$v"
    printf '  "upstream_commit": "%s",\n  "updated_at": "2026-10-01T00:00:00Z",\n' "$uc"
    printf '  "pending_rerun": false,\n  "partial_upgrade": false,\n  "files": [\n'
    fx_json_list '    ' "$@"
    printf '  ],\n  "merged": [],\n  "kept": [],\n  "theirs_over_fork": [],\n  "removed": []\n}\n'
  } > "$inst/.sumela/.last-update.json"
}

fx_old_updater_pass() {  # <install> <upstream> <tree-ish> <path>...
  local inst="$1" up="$2" ref="$3" p tmp
  shift 3
  tmp="$inst.fixture-old"
  rm -rf "$tmp"; mkdir -p "$tmp"
  git -C "$up" archive --format=tar -o "$tmp.tar" "$ref" -- .sumela scripts docs/second-brain/template &&
    tar -xf "$tmp.tar" -C "$tmp" && rm -f "$tmp.tar" || return 1
  for p in "$@"; do cp "$tmp/$p" "$inst/$p" || return 1; done
  cp "$tmp/.sumela/VERSION" "$inst/.sumela/VERSION"
  fx_record_v1 "$inst" "$(tr -d '[:space:]' < "$tmp/.sumela/VERSION")" "$@"
  rm -rf "$tmp"
}

# The updater's Qdrant step talks to QDRANT_HOST:QDRANT_PORT whenever an install carries the
# qdrant plugin. Every run here points it at a closed local port, so no suite ever reaches a
# developer's live Qdrant. fx_env prefixes a command with that environment.
fx_env() { QDRANT_HOST=127.0.0.1 QDRANT_PORT=1 "$@"; }
fx_update() {  # <install> <upstream> <log> [<arg>...]
  local inst="$1" up="$2" log="$3"
  shift 3
  (cd "$inst" && fx_env "${BASH:-bash}" "$FX_REPO_ROOT/scripts/update.sh" --source "$up" "$@") < /dev/null > "$log" 2>&1
}
