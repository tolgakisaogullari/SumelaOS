#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# setup.sh — SumelaOS Template Interactive Setup
# -----------------------------------------------------------------------------
# Generates project-specific files from templates. Asks the user for
# configuration, copies selected rule templates, generates IDE pointer files,
# optionally registers memory plugins, and runs validation.
#
# Usage:
#   bash scripts/setup.sh                          # interactive
#   bash scripts/setup.sh --non-interactive \      # CI/automation
#     --project-name "MyApp" \
#     --project-purpose "My app purpose" \
#     --interaction-language "English" \
#     --code-language "English" \           # fallback for naming + documentation
#     --naming-language "English" \         # optional; defaults to --code-language
#     --documentation-language "English" \  # optional; defaults to --code-language
#     --stacks "backend,frontend" \
#     --rule-variant "best-practice" \
#     --plugins "qdrant-session-memory,graphify-code-graph" \
#     --ides "claude,cursor,cline,kilo-code,trae,opencode" \
#     --governance "solo"                   # or "team" (PR-gated /evolve)
#     --domains "Card,Payments"             # team mode only: business-domain taxonomy (optional)
#     --hooks-only                          # wire core.hooksPath ONLY (no config generation);
#                                           #   used by /onboardSumela for a teammate's clone
#     --ci                                  # opt in to the GitHub Actions workflow (default: off)
# -----------------------------------------------------------------------------

set -euo pipefail

# --- Colors ---
if command -v tput &>/dev/null && [ -t 1 ]; then
  GREEN=$(tput setaf 2) RED=$(tput setaf 1) YELLOW=$(tput setaf 3) CYAN=$(tput setaf 6) RESET=$(tput sgr0) BOLD=$(tput bold)
else
  GREEN="" RED="" YELLOW="" CYAN="" RESET="" BOLD=""
fi

info()  { echo "${CYAN}[INFO]${RESET} $1"; }
ok()    { echo "${GREEN}[OK]${RESET} $1"; }
warn()  { echo "${YELLOW}[WARN]${RESET} $1"; }
err()   { echo "${RED}[ERROR]${RESET} $1"; }

# --- Non-interactive defaults ---
NON_INTERACTIVE=false
NI_PROJECT_NAME=""
NI_PROJECT_PURPOSE=""
NI_INTERACTION_LANG="English"
NI_CODE_LANG="English"
NI_NAMING_LANG=""
NI_DOC_LANG=""
NI_STACKS=""
NI_RULE_VARIANT="best-practice"
NI_PLUGINS=""
NI_IDES=""
NI_GOVERNANCE="solo"
NI_DOMAINS=""   # comma-separated business-domain taxonomy (team mode only)
WITH_CI=false   # CI workflow is opt-in (--ci, or 'y' at the interactive prompt)
HOOKS_WIRED=false
HOOKS_ONLY=false   # --hooks-only: wire core.hooksPath ONLY, no config generation (teammate onboarding)

# --- Parse CLI args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --non-interactive) NON_INTERACTIVE=true; shift ;;
    --project-name)    NI_PROJECT_NAME="$2"; shift 2 ;;
    --project-purpose) NI_PROJECT_PURPOSE="$2"; shift 2 ;;
    --interaction-language) NI_INTERACTION_LANG="$2"; shift 2 ;;
    --code-language)   NI_CODE_LANG="$2"; shift 2 ;;
    --naming-language) NI_NAMING_LANG="$2"; shift 2 ;;
    --documentation-language) NI_DOC_LANG="$2"; shift 2 ;;
    --stacks)          NI_STACKS="$2"; shift 2 ;;
    --rule-variant)    NI_RULE_VARIANT="$2"; shift 2 ;;
    --plugins)         NI_PLUGINS="$2"; shift 2 ;;
    --ides)            NI_IDES="$2"; shift 2 ;;
    --governance)      NI_GOVERNANCE="$2"; shift 2 ;;
    --domains)         NI_DOMAINS="$2"; shift 2 ;;
    --hooks-only)      HOOKS_ONLY=true; shift ;;
    --ci)              WITH_CI=true; shift ;;
    *) err "Unknown option: $1"; exit 1 ;;
  esac
done

# --- Cleanup on Ctrl+C ---
cleanup() {
  echo ""
  warn "Setup interrupted. Partial files may exist — re-run to overwrite."
  exit 130
}
trap cleanup INT

# --- Template existence preflight ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

# Skip the template preflight for --hooks-only: it generates nothing, so the
# config templates are irrelevant. (cd "$ROOT_DIR" above still ran — wire_git_hooks
# needs CWD = repo root.) Without this skip, a teammate onboarding via
# `setup.sh --hooks-only` on a clone that didn't commit the *.template files would
# abort before wiring hooks.
if [ "$HOOKS_ONLY" != true ]; then
  REQUIRED_TEMPLATES=(
    "AGENTS.md.template"
    ".sumela/RULE_REGISTRY.md.template"
    "CLAUDE.md.template"
    ".clinerules.template"
    ".cursor/rules/00-agent.md.template"
    ".kilocode/rules.md.template"
    ".trae/rules/00-agent.md.template"
    ".opencode/AGENTS.md.template"
    "docs/second-brain/template/wiki/_INDEX.md.template"
    "docs/second-brain/template/wiki/_LOG.md.template"
    "docs/second-brain/template/wiki/_SEARCH_INDEX.md.template"
    "docs/second-brain/template/wiki/_improvement-queue/README.md"
    "docs/second-brain/template/wiki/_SCHEMA.md"
    "docs/second-brain/template/wiki/active-project-context.md.template"
  )

  MISSING_TEMPLATES=()
  for tmpl in "${REQUIRED_TEMPLATES[@]}"; do
    if [ ! -f "$tmpl" ]; then
      MISSING_TEMPLATES+=("$tmpl")
    fi
  done

  if [ ${#MISSING_TEMPLATES[@]} -gt 0 ]; then
    err "Missing template files:"
    for m in "${MISSING_TEMPLATES[@]}"; do
      echo "  - $m"
    done
    exit 1
  fi
fi

# --- Helper: render template using Python (handles multi-line, pipes, special chars) ---
render_template() {
  local template="$1"
  local output="$2"
  python3 -c "
import os, re, sys
with open(sys.argv[1], 'r') as f:
    content = f.read()
for key, val in os.environ.items():
    if key.startswith('TMPL_'):
        placeholder = '{{' + key[5:].lower() + '}}'
        content = content.replace(placeholder, val)
with open(sys.argv[2], 'w') as f:
    f.write(content)
" "$template" "$output"
}

# Slugify a domain name -> filesystem-safe slug. Transliterates accented Latin +
# Turkish letters to ASCII FIRST (so 'Ödeme'->'odeme', 'Çek'->'cek', 'Café'->'cafe'
# rather than lossy 'deme'/'ek'/'caf'), then lowercases, maps runs of non-alnum to a
# single hyphen, and trims. Uses python3 (already required by render_template) for
# reliable Unicode handling; ASCII input yields the same slug as a plain tr pipeline.
slugify() {
  python3 -c '
import sys, unicodedata, re
s = sys.argv[1]
# Turkish letters NFKD does not reduce to ASCII (esp. dotless i) — map explicitly first.
tr = {"ı":"i","İ":"i","ş":"s","Ş":"s","ğ":"g","Ğ":"g","ç":"c","Ç":"c","ö":"o","Ö":"o","ü":"u","Ü":"u"}
s = "".join(tr.get(ch, ch) for ch in s)
s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode("ascii")
print(re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-"))
' "$1"
}

# --- Git hook wiring (core.hooksPath) — used by the full install AND by --hooks-only ---
# Helpers for the multi-install (monorepo) dispatcher. core.hooksPath holds ONE path,
# so a second SumelaOS install in the same repo is handled by a root dispatcher that
# fans each git event out to every registered install (see .sumela/git-hooks/_dispatch.sh).
sumela_register_install() {        # $1 = git_root, $2 = install_rel ("" => repo root)
  local reg="$1/.sumela-hooks/installs" entry="${2:-.}"
  [ -z "$entry" ] && entry="."
  touch "$reg"
  grep -qxF "$entry" "$reg" 2>/dev/null || printf '%s\n' "$entry" >> "$reg"
}
sumela_setup_dispatch() {          # $1 = git_root, $2 = install_abs (source of _dispatch.sh)
  local dh="$1/.sumela-hooks" hk
  mkdir -p "$dh"
  for hk in pre-commit post-merge post-checkout; do
    cp "$2/.sumela/git-hooks/_dispatch.sh" "$dh/$hk"
    chmod +x "$dh/$hk" 2>/dev/null || true
  done
}
# Wire core.hooksPath for THIS install, handling unset / already-this-install /
# existing-dispatcher / other-SumelaOS-install / non-SumelaOS (e.g. Husky) cases.
# Sets the global HOOKS_WIRED. NEVER regenerates project config — so it is safe for
# `--hooks-only` (teammate onboarding) as well as the full install flow.
wire_git_hooks() {
  if [ -d ".sumela/git-hooks" ]; then
    info "Wiring git hooks (pre-commit validation + memory sync)..."
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      GIT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
      INSTALL_ABS="$(pwd)"
      # --show-prefix gives cwd relative to the repo root ("packages/app/" or "" at root),
      # avoiding fragile path subtraction (e.g. macOS /var vs /private/var symlinks).
      INSTALL_REL="$(git rev-parse --show-prefix 2>/dev/null)"
      INSTALL_REL="${INSTALL_REL%/}"                          # strip trailing slash; "" at repo root
      HOOKS_REL="${INSTALL_REL:+$INSTALL_REL/}.sumela/git-hooks"
      chmod +x .sumela/git-hooks/pre-commit .sumela/git-hooks/post-merge .sumela/git-hooks/post-checkout 2>/dev/null || true
      EXISTING_HOOKS_PATH="$(git config --local --get core.hooksPath 2>/dev/null || true)"
      if [ -z "$EXISTING_HOOKS_PATH" ] || [ "$EXISTING_HOOKS_PATH" = "$HOOKS_REL" ]; then
        # Unset, or already pointing at THIS install → wire directly (idempotent).
        git config core.hooksPath "$HOOKS_REL"
        HOOKS_WIRED=true
        ok "Git hooks enabled (core.hooksPath = $HOOKS_REL) — pre-commit validation active (bypass: git commit --no-verify)"
      else
        case "$EXISTING_HOOKS_PATH" in
          .sumela-hooks|*/.sumela-hooks)
            # A SumelaOS dispatcher already owns hooks → just register this install.
            sumela_setup_dispatch "$GIT_ROOT" "$INSTALL_ABS"   # refresh dispatcher scripts
            sumela_register_install "$GIT_ROOT" "$INSTALL_REL"
            HOOKS_WIRED=true
            ok "Registered this install with the existing SumelaOS hook dispatcher (.sumela-hooks/)." ;;
          *.sumela/git-hooks)
            # Another SumelaOS install owns core.hooksPath → promote to a dispatcher that
            # runs BOTH (this + the other) on every git event (multi-install monorepo).
            OTHER_REL="${EXISTING_HOOKS_PATH%/.sumela/git-hooks}"
            [ "$OTHER_REL" = "$EXISTING_HOOKS_PATH" ] && OTHER_REL=""   # other install at root
            sumela_setup_dispatch "$GIT_ROOT" "$INSTALL_ABS"
            sumela_register_install "$GIT_ROOT" "$OTHER_REL"
            sumela_register_install "$GIT_ROOT" "$INSTALL_REL"
            git config core.hooksPath ".sumela-hooks"
            HOOKS_WIRED=true
            ok "Multiple SumelaOS installs detected — installed a hook dispatcher at .sumela-hooks/ that runs all of them."
            info "Commit .sumela-hooks/ so teammates share the dispatcher (each runs setup once to wire core.hooksPath)." ;;
          *)
            warn "core.hooksPath already set to '$EXISTING_HOOKS_PATH' (non-SumelaOS) — not overriding."
            warn "To enable SumelaOS hooks, merge .sumela/git-hooks/{pre-commit,post-merge,post-checkout} into '$EXISTING_HOOKS_PATH', or unset it and re-run setup." ;;
        esac
      fi
    else
      warn "Not a git repository — skipping git hook setup."
      warn "After 'git init', run setup again (it wires core.hooksPath automatically)."
    fi
  fi
}

# --- Helper: prompt with default ---
prompt_default() {
  local prompt="$1"
  local default="$2"
  local result
  read -rp "$prompt [$default]: " result
  echo "${result:-$default}"
}

# --- Helper: multi-select from list ---
prompt_multiselect() {
  local prompt="$1"
  shift
  local options=("$@")
  # Menu UI goes to stderr so command substitution captures ONLY the result line.
  echo "$prompt" >&2
  local i
  for i in "${!options[@]}"; do
    echo "  $((i+1)). ${options[$i]}" >&2
  done
  local selection
  read -rp "Enter numbers separated by commas (e.g. 1,3): " selection
  local result=()
  local nums
  IFS=',' read -ra nums <<< "$selection"
  local num
  # ${nums[@]+...} guard: empty-array-safe under `set -u` on bash 3.2 (macOS default).
  for num in ${nums[@]+"${nums[@]}"}; do
    num=$(echo "$num" | tr -d ' ')
    if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le ${#options[@]} ]; then
      result+=("${options[$((num-1))]}")
    fi
  done
  echo "${result[@]+${result[@]}}"
}

# --- Helper: yes/no prompt ---
prompt_yn() {
  local prompt="$1"
  local default="${2:-n}"
  local result
  read -rp "$prompt [y/n, default: $default]: " result
  result="${result:-$default}"
  [[ "$result" =~ ^[yY] ]]
}

# --- --hooks-only: wire git hooks and stop (no config generation). Used by
# /onboardSumela so a teammate's clone gets the SAME hook-wiring logic (incl. the
# monorepo dispatcher + non-SumelaOS-hooksPath cases) WITHOUT regenerating any
# tracked team config. ---
if [ "$HOOKS_ONLY" = true ]; then
  info "Wiring git hooks only (no config generation)..."
  wire_git_hooks
  exit 0
fi

# =============================================================================
# 1. COLLECT CONFIGURATION
# =============================================================================
echo ""
echo "${BOLD}=== SumelaOS Template Setup ===${RESET}"
echo ""

if [ "$NON_INTERACTIVE" = true ]; then
  PROJECT_NAME="$NI_PROJECT_NAME"
  PROJECT_PURPOSE="$NI_PROJECT_PURPOSE"
  INTERACTION_LANG="$NI_INTERACTION_LANG"
  CODE_LANG="$NI_CODE_LANG"
  NAMING_LANG="${NI_NAMING_LANG:-$NI_CODE_LANG}"
  DOC_LANG="${NI_DOC_LANG:-$NI_CODE_LANG}"
  IFS=',' read -ra STACKS <<< "$NI_STACKS"
  RULE_VARIANT="$NI_RULE_VARIANT"
  IFS=',' read -ra PLUGINS <<< "$NI_PLUGINS"
  IFS=',' read -ra IDES <<< "$NI_IDES"
  GOVERNANCE="$NI_GOVERNANCE"

  if [ -z "$PROJECT_NAME" ]; then
    err "--project-name is required in non-interactive mode"
    exit 1
  fi
else
  PROJECT_NAME=$(prompt_default "Project name" "")
  if [ -z "$PROJECT_NAME" ]; then
    err "Project name is required"
    exit 1
  fi

  PROJECT_PURPOSE=$(prompt_default "Project purpose" "A software project")
  INTERACTION_LANG=$(prompt_default "Interaction language (agent chat/explanations)" "English")
  NAMING_LANG=$(prompt_default "Code naming language (services, methods, classes, files)" "English")
  DOC_LANG=$(prompt_default "Code documentation language (comments, docstrings)" "English")
  # CODE_LANG retained for backward-compat consumers; mirrors the naming language.
  CODE_LANG="$NAMING_LANG"

  echo ""
  echo "Select tech stacks (comma-separated numbers):"
  # AI and infra stacks coming soon — not yet available
  # read -ra instead of mapfile (mapfile is bash 4+; macOS ships bash 3.2).
  STACKS=()
  read -ra STACKS <<< "$(prompt_multiselect "Tech stacks:" "backend" "frontend" "mobile")"

  echo ""
  RULE_VARIANT=$(prompt_default "Rule variant for selected stacks (empty/best-practice)" "best-practice")

  echo ""
  PLUGINS=()
  if prompt_yn "Enable qdrant-session-memory plugin?" "n"; then
    PLUGINS+=("qdrant-session-memory")
  fi
  if prompt_yn "Enable graphify-code-graph plugin?" "n"; then
    PLUGINS+=("graphify-code-graph")
  fi

  echo ""
  IDES=()
  read -ra IDES <<< "$(prompt_multiselect "IDEs to generate pointer files for:" "claude" "cursor" "cline" "kilo-code" "trae" "opencode")"

  echo ""
  echo "Governance mode controls how /evolve applies changes to the agent-control surface (rules/skills/prompt/schema):"
  echo "  solo — apply directly (one developer owns the config)"
  echo "  team — route through a pull request so a code owner reviews before it becomes everyone's standard"
  GOVERNANCE=$(prompt_default "Governance mode (solo/team)" "solo")

  echo ""
  echo "Optional: a GitHub Actions workflow that runs the structure validation on push/PR."
  echo "(Skip if you use GitLab/Azure/no CI — see ADOPTION_GUIDE for those.)"
  if prompt_yn "Add the GitHub Actions CI workflow?" "n"; then
    WITH_CI=true
  fi
fi

# Normalize / validate governance value.
GOVERNANCE="$(echo "$GOVERNANCE" | tr '[:upper:]' '[:lower:]' | tr -d ' ')"
if [ "$GOVERNANCE" != "team" ]; then GOVERNANCE="solo"; fi

# --- Business-domain taxonomy (team mode only) ---
# The SET of domains is team-wide and TRACKED — rendered into RULE_REGISTRY
# <domain_scopes> + one rule file each. Which domain(s) a given developer works in
# is per-developer and UNTRACKED (.sumela/local.md `domains:`), asked during
# onboarding (/onboardSumela), NOT here. Blank/solo => no domains; add later.
DOMAINS=()
if [ "$GOVERNANCE" = "team" ]; then
  if [ "$NON_INTERACTIVE" = true ]; then
    IFS=',' read -ra DOMAINS <<< "$NI_DOMAINS"
  else
    echo ""
    echo "Does your team organize work by business domain (e.g. Card, Payments, Onboarding)?"
    echo "Each one gets a rule file the agent loads for developers who work in that domain."
    echo "Leave blank to skip — domains can be added later via /onboardSumela or /evolve."
    DOMAIN_CSV=$(prompt_default "Domains (comma-separated)" "")
    IFS=',' read -ra DOMAINS <<< "$DOMAIN_CSV"
  fi
fi

# Validate the domain taxonomy BEFORE generating anything: reject names that would
# corrupt the registry (table/XML metacharacters) or collide on their slug (two
# distinct names -> one file + duplicate <name>/<path>, which would otherwise pass
# every parity check silently). Fail fast with a clear rename message.
_seen_slugs=""
for dom in ${DOMAINS[@]+"${DOMAINS[@]}"}; do
  dom="$(echo "$dom" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  [ -z "$dom" ] && continue
  case "$dom" in
    *'|'*|*'<'*|*'>'*|*'"'*)
      err "Domain name '$dom' contains an unsupported character (one of | < > \"). Rename it and re-run."; exit 1 ;;
  esac
  _slug="$(slugify "$dom")"
  [ -z "$_slug" ] && { err "Domain name '$dom' has no usable (alphanumeric) characters. Rename it and re-run."; exit 1; }
  case " $_seen_slugs " in
    *" $_slug "*) err "Domain names collide on slug '$_slug' (e.g. '$dom'). Pick names that stay distinct after lowercasing + hyphenation."; exit 1 ;;
  esac
  _seen_slugs="$_seen_slugs $_slug"
done

# --- Validate inputs ---
if [ -z "$PROJECT_NAME" ]; then
  err "Project name cannot be empty"
  exit 1
fi

DATE_CREATED="$(date +%Y-%m-%d)"

info "Project: $PROJECT_NAME"
info "Governance: $GOVERNANCE"
info "Stacks: ${STACKS[*]:-none}"
[ "$GOVERNANCE" = "team" ] && info "Domains: ${DOMAINS[*]:-none}"
info "Rule variant: $RULE_VARIANT"
info "Plugins: ${PLUGINS[*]:-none}"
info "IDEs: ${IDES[*]:-none}"
echo ""

# =============================================================================
# 2. GENERATE AGENTS.md
# =============================================================================
info "Generating AGENTS.md from template..."

# Build tech stack summary
TECH_SUMMARY=""
if [[ " ${STACKS[*]:-} " =~ " backend" ]]; then TECH_SUMMARY="Backend"; fi
if [[ " ${STACKS[*]:-} " =~ " frontend" ]]; then
  [ -n "$TECH_SUMMARY" ] && TECH_SUMMARY="$TECH_SUMMARY + "
  TECH_SUMMARY="${TECH_SUMMARY}Frontend"
fi
if [[ " ${STACKS[*]:-} " =~ " mobile" ]]; then
  [ -n "$TECH_SUMMARY" ] && TECH_SUMMARY="$TECH_SUMMARY + "
  TECH_SUMMARY="${TECH_SUMMARY}Mobile"
fi
[ -z "$TECH_SUMMARY" ] && TECH_SUMMARY="TBD"

# Build package boundaries table rows
PKG_BOUNDARIES=""
if [[ " ${STACKS[*]:-} " =~ " backend" ]]; then
  PKG_BOUNDARIES="| \`src/\` | Backend | \`main\` |"
fi
if [[ " ${STACKS[*]:-} " =~ " frontend" ]]; then
  [ -n "$PKG_BOUNDARIES" ] && PKG_BOUNDARIES="$PKG_BOUNDARIES"$'\n'
  PKG_BOUNDARIES="${PKG_BOUNDARIES}| \`web/\` | Frontend | \`npm run dev\` |"
fi
if [[ " ${STACKS[*]:-} " =~ " mobile" ]]; then
  [ -n "$PKG_BOUNDARIES" ] && PKG_BOUNDARIES="$PKG_BOUNDARIES"$'\n'
  PKG_BOUNDARIES="${PKG_BOUNDARIES}| \`mobile/\` | Mobile | \`npx expo start\` |"
fi
[ -z "$PKG_BOUNDARIES" ] && PKG_BOUNDARIES="| TBD | TBD | TBD |"

# Build commands sections
BACKEND_CMDS="# Add your backend build/run/test commands here"
FRONTEND_CMDS="# Add your frontend build/run/test commands here"
MOBILE_CMDS="# Add your mobile build/run/test commands here"
INFRA_CMDS="# Add your Docker infrastructure commands here"

if [[ " ${STACKS[*]:-} " =~ " backend" ]]; then
  BACKEND_CMDS='```bash
# Build
./gradlew build   # or: dotnet build / mvn package / go build
# Run
./gradlew run     # or: dotnet run / mvn spring-boot:run / go run .
# Test
./gradlew test    # or: dotnet test / mvn test / go test ./...
```'
fi
if [[ " ${STACKS[*]:-} " =~ " frontend" ]]; then
  FRONTEND_CMDS='```bash
# Install dependencies
npm install       # or: yarn / pnpm install
# Run dev server
npm run dev
# Build
npm run build
# Test
npm run test
```'
fi
if [[ " ${STACKS[*]:-} " =~ " mobile" ]]; then
  MOBILE_CMDS='```bash
# Install dependencies
npx expo install
# Start dev server
npx expo start
# Build for Android
npx expo run:android
# Build for iOS
npx expo run:ios
```'
fi

# Build project-specific security
PROJECT_SECURITY=""
if [[ " ${STACKS[*]:-} " =~ " backend" ]]; then
  PROJECT_SECURITY=$'\n'"- Skill path: \`.sumela/rules/backend_standards.md\` — backend-specific security patterns."
fi

# Build dependency flow
DEP_FLOW='```'"$PROJECT_NAME"' → Application → Domain
         ↑
   Infrastructure
```'
if [[ ! " ${STACKS[*]:-} " =~ " backend" ]]; then
  DEP_FLOW="# Define your project dependency flow here"
fi

# Perform template replacements via environment variables (TMPL_ prefix)
export TMPL_PROJECT_NAME="$PROJECT_NAME"
export TMPL_PROJECT_PURPOSE="$PROJECT_PURPOSE"
export TMPL_TECH_STACK_SUMMARY="$TECH_SUMMARY"
export TMPL_INTERACTION_LANGUAGE="$INTERACTION_LANG"
export TMPL_NAMING_LANGUAGE="$NAMING_LANG"
export TMPL_DOCUMENTATION_LANGUAGE="$DOC_LANG"
export TMPL_BACKEND_COMMANDS="$BACKEND_CMDS"
export TMPL_FRONTEND_COMMANDS="$FRONTEND_CMDS"
export TMPL_MOBILE_COMMANDS="$MOBILE_CMDS"
export TMPL_INFRASTRUCTURE_COMMANDS="$INFRA_CMDS"
export TMPL_DEPENDENCY_FLOW="$DEP_FLOW"
export TMPL_PACKAGE_BOUNDARIES="$PKG_BOUNDARIES"
export TMPL_GOVERNANCE_MODE="$GOVERNANCE"
export TMPL_NAMING_CONVENTIONS="# Define your naming conventions here"
export TMPL_TECHNICAL_CONSTRAINTS="# Define your technical constraints here"
export TMPL_PROJECT_SPECIFIC_SECURITY="$PROJECT_SECURITY"

# Non-destructive guard: setup.sh is the deterministic (greenfield-oriented) path and
# does NOT do the brownfield merge that /initSumela does. If the user already has an
# AGENTS.md, back it up rather than silently clobbering it, and point them at the merge.
if [ -f AGENTS.md ] && ! grep -qF "SumelaOS" AGENTS.md 2>/dev/null; then
  AGENTS_BAK="AGENTS.md.bak"; [ -e "$AGENTS_BAK" ] && AGENTS_BAK="AGENTS.md.bak.$(date +%Y%m%d%H%M%S)"
  cp AGENTS.md "$AGENTS_BAK"
  warn "Existing AGENTS.md detected — backed up to $AGENTS_BAK (gitignored). For a proper merge of your existing config, use the /initSumela agent flow (brownfield merge) instead of setup.sh."
fi
render_template AGENTS.md.template AGENTS.md

ok "AGENTS.md generated"

# =============================================================================
# 3. GENERATE RULE_REGISTRY.md
# =============================================================================
info "Generating RULE_REGISTRY.md from template..."

# Build stack scopes
STACK_SCOPES=""
if [[ " ${STACKS[*]:-} " =~ " backend" ]]; then
  STACK_SCOPES="| \`backend\` | \`src/\`, \`*.cs\`, \`*.java\`, \`*.go\`, \`*.py\`, \`api/\`, \`server/\` |"
fi
if [[ " ${STACKS[*]:-} " =~ " frontend" ]]; then
    [ -n "$STACK_SCOPES" ] && STACK_SCOPES="$STACK_SCOPES"$'\n'
    STACK_SCOPES="${STACK_SCOPES}| \`frontend\` | \`web/\`, \`*.tsx\`, \`*.jsx\`, \`*.vue\`, \`*.svelte\` |"
fi
if [[ " ${STACKS[*]:-} " =~ " mobile" ]]; then
    [ -n "$STACK_SCOPES" ] && STACK_SCOPES="$STACK_SCOPES"$'\n'
    STACK_SCOPES="${STACK_SCOPES}| \`mobile\` | \`mobile/\`, \`*.swift\`, \`*.kt\`, \`app/\` |"
fi
[ -z "$STACK_SCOPES" ] && STACK_SCOPES="| \`default\` | All project files |"

# Build stack rules entries
STACK_RULES=""
for stack in ${STACKS[@]+"${STACKS[@]}"}; do
  stack=$(echo "$stack" | tr -d ' ')
  case "$stack" in
    backend)
      STACK_RULES="${STACK_RULES}
<rule activation=\"stack-conditional\" applies_phases=\"planning,implementation,verification,code_review,debugging\" stack=\"backend\">
<name>backend_standards</name>
<description>Use when the task scope includes backend — architecture layers, naming conventions, data access, API design, error handling, testing, security.</description>
<path>.sumela/rules/backend_standards.md</path>
</rule>
"
      ;;
    frontend)
      STACK_RULES="${STACK_RULES}
<rule activation=\"stack-conditional\" applies_phases=\"planning,implementation,verification,code_review,debugging\" stack=\"frontend\">
<name>frontend_standards</name>
<description>Use when the task scope includes frontend — component architecture, state management, styling, accessibility, build tooling, testing.</description>
<path>.sumela/rules/frontend_standards.md</path>
</rule>
"
      ;;
    mobile)
      STACK_RULES="${STACK_RULES}
<rule activation=\"stack-conditional\" applies_phases=\"planning,implementation,verification,code_review,debugging\" stack=\"mobile\">
<name>mobile_standards</name>
<description>Use when the task scope includes mobile — navigation, offline-first, push notifications, platform conventions, performance, testing.</description>
<path>.sumela/rules/mobile_standards.md</path>
</rule>
"
      ;;
  esac
done

# Build domain scopes + domain-conditional rule entries (team-mode taxonomy).
DOMAIN_SCOPES=""
DOMAIN_RULES=""
for dom in ${DOMAINS[@]+"${DOMAINS[@]}"}; do
  dom="$(echo "$dom" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  [ -z "$dom" ] && continue
  dom_slug="$(slugify "$dom")"
  [ -z "$dom_slug" ] && continue
  dom_name="${dom_slug//-/_}_domain"
  [ -n "$DOMAIN_SCOPES" ] && DOMAIN_SCOPES="$DOMAIN_SCOPES"$'\n'
  DOMAIN_SCOPES="${DOMAIN_SCOPES}| \`${dom}\` | Work scoped to the ${dom} domain (from a developer's \`domains:\` or an explicit mention) |"
  DOMAIN_RULES="${DOMAIN_RULES}
<rule activation=\"domain-conditional\" applies_phases=\"all\" domain=\"${dom}\">
<name>${dom_name}</name>
<description>Use when the task scope includes the ${dom} domain — business rules, vocabulary, invariants, and conventions specific to ${dom} (applies across all stacks).</description>
<path>.sumela/rules/domains/${dom_slug}.md</path>
</rule>
"
done
[ -z "$DOMAIN_SCOPES" ] && DOMAIN_SCOPES="| \`(none)\` | No domains configured — add via /onboardSumela or /evolve |"

# Build phase matrix rows (5 columns: Phase | Universal | Phase-conditional | Stack-conditional | Domain-conditional)
PHASE_MATRIX='| `ideation` | engineering_philosophy, identity_and_behavior | architecture_patterns | (load matching stack rules) | (load matching domain rules) |
| `specification` | engineering_philosophy, identity_and_behavior | architecture_patterns | (load matching stack rules) | (load matching domain rules) |
| `planning` | engineering_philosophy, identity_and_behavior | architecture_patterns, operational_excellence_maintenance | (load matching stack rules) | (load matching domain rules) |
| `implementation` | engineering_philosophy, identity_and_behavior | audit_and_output | (load matching stack rules) | (load matching domain rules) |
| `verification` | engineering_philosophy, identity_and_behavior | audit_and_output | (load matching stack rules) | (load matching domain rules) |
| `code_review` | engineering_philosophy, identity_and_behavior | audit_and_output, git_workflow_mandatory_review_protocol | (load matching stack rules) | (load matching domain rules) |
| `branch_finish` | engineering_philosophy, identity_and_behavior | git_workflow_mandatory_review_protocol, operational_excellence_maintenance | (load matching stack rules) | (load matching domain rules) |
| `shipping` | engineering_philosophy, identity_and_behavior | operational_excellence_maintenance | (load matching stack rules) | (load matching domain rules) |
| `debugging` | engineering_philosophy, identity_and_behavior | audit_and_output | (load matching stack rules) | (load matching domain rules) |'

export TMPL_STACK_SCOPES="$STACK_SCOPES"
export TMPL_STACK_RULES="$STACK_RULES"
export TMPL_DOMAIN_SCOPES="$DOMAIN_SCOPES"
export TMPL_DOMAIN_RULES="$DOMAIN_RULES"
export TMPL_PHASE_MATRIX_ROWS="$PHASE_MATRIX"
export TMPL_EXAMPLE_OVERRIDE="backend"

render_template .sumela/RULE_REGISTRY.md.template .sumela/RULE_REGISTRY.md

ok "RULE_REGISTRY.md generated"

# =============================================================================
# 4. COPY RULE TEMPLATES
# =============================================================================
info "Copying rule templates (variant: $RULE_VARIANT)..."

# Map stack name -> template file name (case fn instead of associative array; bash 3.2 compat).
stack_rule_name() {
  case "$1" in
    backend)  echo "backend_standards" ;;
    frontend) echo "frontend_standards" ;;
    mobile)   echo "mobile_standards" ;;
    *)        echo "" ;;
  esac
}

# Copy stack-specific rule templates
for stack in ${STACKS[@]+"${STACKS[@]}"}; do
  stack=$(echo "$stack" | tr -d ' ')
  rule_name="$(stack_rule_name "$stack")"
  if [ -n "$rule_name" ]; then
    src=".sumela/rules/templates/${rule_name}.md.${RULE_VARIANT}"
    dst=".sumela/rules/${rule_name}.md"
    if [ -f "$src" ]; then
      export TMPL_DATE_CREATED="$DATE_CREATED"
      render_template "$src" "$dst"
      ok "Copied $dst"
    else
      warn "Template not found: $src — skipping"
    fi
  else
    warn "No rule template for stack '$stack' — skipping"
  fi
done

# Copy operational_excellence_maintenance (always needed)
OP_SRC=".sumela/rules/templates/operational_excellence_maintenance.md.${RULE_VARIANT}"
OP_DST=".sumela/rules/operational_excellence_maintenance.md"
if [ -f "$OP_SRC" ]; then
  export TMPL_DATE_CREATED="$DATE_CREATED"
  render_template "$OP_SRC" "$OP_DST"
  ok "Copied $OP_DST"
else
  warn "Template not found: $OP_SRC — skipping"
fi

# Copy domain rule templates (team-mode taxonomy). One .empty file per domain; NEVER
# clobber an existing (possibly customized) domain rule — generation is idempotent.
DOMAIN_TMPL=".sumela/rules/templates/domain_standards.md.empty"
for dom in ${DOMAINS[@]+"${DOMAINS[@]}"}; do
  dom="$(echo "$dom" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  [ -z "$dom" ] && continue
  dom_slug="$(slugify "$dom")"
  [ -z "$dom_slug" ] && continue
  dst=".sumela/rules/domains/${dom_slug}.md"
  if [ -f "$dst" ]; then
    info "Domain rule exists, leaving as-is: $dst"
    continue
  fi
  if [ -f "$DOMAIN_TMPL" ]; then
    mkdir -p .sumela/rules/domains
    export TMPL_DATE_CREATED="$DATE_CREATED"
    export TMPL_DOMAIN_NAME="$dom"
    render_template "$DOMAIN_TMPL" "$dst"
    ok "Copied $dst"
  else
    warn "Template not found: $DOMAIN_TMPL — skipping"
  fi
done
unset TMPL_DOMAIN_NAME 2>/dev/null || true

# Prune orphaned domain rules: re-running setup with a NARROWER domain list regenerates
# RULE_REGISTRY.md without the dropped domain, but its .sumela/rules/domains/<slug>.md
# would linger — unregistered — and fail domain parity (blocking commits). Quarantine
# (never delete) such files to the gitignored _migration dir, with a clear warning.
if [ -d .sumela/rules/domains ]; then
  CUR_SLUGS=""
  for dom in ${DOMAINS[@]+"${DOMAINS[@]}"}; do
    dom="$(echo "$dom" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"; [ -z "$dom" ] && continue
    CUR_SLUGS="$CUR_SLUGS $(slugify "$dom")"
  done
  for f in .sumela/rules/domains/*.md; do
    [ -e "$f" ] || continue
    fslug="$(basename "$f" .md)"
    case " $CUR_SLUGS " in
      *" $fslug "*) : ;;                          # still in the taxonomy — keep
      *)
        QDIR=".sumela/_migration/domains-$DATE_CREATED"
        mkdir -p "$QDIR"
        mv "$f" "$QDIR/" 2>/dev/null && \
          warn "Domain '$fslug' is no longer in the taxonomy — quarantined $f to $QDIR/ (gitignored). If unintended, move it back and re-add the domain." ;;
    esac
  done
fi

# =============================================================================
# 5. GENERATE IDE POINTER FILES
# =============================================================================
info "Generating IDE pointer files..."

# Map IDE name -> "dst:template" (case fn instead of associative array; bash 3.2 compat).
ide_file_map() {
  case "$1" in
    claude)    echo "CLAUDE.md:CLAUDE.md.template" ;;
    cursor)    echo ".cursor/rules/00-agent.md:.cursor/rules/00-agent.md.template" ;;
    cline)     echo ".clinerules:.clinerules.template" ;;
    kilo-code) echo ".kilocode/rules.md:.kilocode/rules.md.template" ;;
    trae)      echo ".trae/rules/00-agent.md:.trae/rules/00-agent.md.template" ;;
    opencode)  echo ".opencode/AGENTS.md:.opencode/AGENTS.md.template" ;;
    *)         echo "" ;;
  esac
}

for ide in ${IDES[@]+"${IDES[@]}"}; do
  ide=$(echo "$ide" | tr -d ' ')
  ide_mapping="$(ide_file_map "$ide")"
  if [ -n "$ide_mapping" ]; then
    IFS=':' read -r dst tmpl <<< "$ide_mapping"
    if [ -f "$tmpl" ]; then
      # Ensure parent directory exists
      mkdir -p "$(dirname "$dst")"
      export TMPL_PROJECT_NAME="$PROJECT_NAME"
      render_template "$tmpl" "$dst"
      ok "Generated $dst"
    else
      warn "Template not found: $tmpl — skipping"
    fi
  else
    warn "Unknown IDE: $ide — skipping"
  fi
done

# =============================================================================
# 6. COPY WIKI TEMPLATES
# =============================================================================
info "Copying wiki templates..."

mkdir -p docs/second-brain/wiki
mkdir -p docs/second-brain/wiki/_improvement-queue
mkdir -p docs/second-brain/raw_sources
mkdir -p docs/second-brain/artifacts/plans
mkdir -p docs/second-brain/artifacts/specs

WIKI_TEMPLATES=(
  "_INDEX.md.template:_INDEX.md"
  "_LOG.md.template:_LOG.md"
  "_SEARCH_INDEX.md.template:_SEARCH_INDEX.md"
  "_SCHEMA.md:_SCHEMA.md"
  "active-project-context.md.template:active-project-context.md"
)

for entry in "${WIKI_TEMPLATES[@]}"; do
  IFS=':' read -r src_name dst_name <<< "$entry"
  src="docs/second-brain/template/wiki/$src_name"
  dst="docs/second-brain/wiki/$dst_name"
  if [ -f "$src" ]; then
    export TMPL_PROJECT_NAME="$PROJECT_NAME"
    export TMPL_DATE_CREATED="$DATE_CREATED"
    render_template "$src" "$dst"
    ok "Copied $dst"
  else
    warn "Template not found: $src — skipping"
  fi
done

# Improvement queue is a DIRECTORY (one file per signal) — copy its README anchor.
IQ_SRC="docs/second-brain/template/wiki/_improvement-queue/README.md"
IQ_DST="docs/second-brain/wiki/_improvement-queue/README.md"
if [ -f "$IQ_SRC" ]; then
  export TMPL_PROJECT_NAME="$PROJECT_NAME"
  render_template "$IQ_SRC" "$IQ_DST"
  ok "Copied $IQ_DST"
else
  warn "Template not found: $IQ_SRC — skipping"
fi

# =============================================================================
# 6b. CONFIGURE GIT MERGE STRATEGY (append-only ledger)
# =============================================================================
info "Ensuring .gitattributes union-merge for the append-only log..."
GITATTR_LINE="docs/second-brain/wiki/_LOG.md merge=union"
if [ -f .gitattributes ] && grep -qF "$GITATTR_LINE" .gitattributes; then
  ok ".gitattributes already has the union-merge rule"
else
  {
    # -s (not -f): the redirect creates the file before this runs, so -f would
    # be true even on a brand-new empty file and emit a spurious leading blank.
    [ -s .gitattributes ] && echo ""
    echo "# SumelaOS — append-only ledger: concurrent log appends combine instead of conflicting"
    echo "$GITATTR_LINE"
  } >> .gitattributes
  ok ".gitattributes union-merge rule added"
fi

# =============================================================================
# 6c. CONFIGURE .gitignore (per-developer / runtime artifacts — never commit)
# =============================================================================
info "Ensuring .gitignore covers per-developer / runtime artifacts..."
GITIGNORE_MARKER="# SumelaOS — per-developer / runtime artifacts"
# Guard on the stable entry line (not the comment) so re-runs AND the framework
# repo's own .gitignore — which already lists these under different headers — are
# both detected and not duplicated.
if [ -f .gitignore ] && grep -qxF ".sumela/local.md" .gitignore; then
  ok ".gitignore already ignores per-developer artifacts"
else
  {
    [ -s .gitignore ] && echo ""
    echo "$GITIGNORE_MARKER (never commit)"
    echo ".sumela/local.md"          # per-developer interaction-language override
    echo ".sumela/.memory-sync.log"  # memory-sync hook log
    echo ".sumela/.graph-sync.log"   # graph-sync hook log
    echo ".sumela/.code-chunks-synced"  # code_chunks last-ingest marker
    echo ".superpowers/"             # brainstorming skill runtime state
    echo "**/scripts/.superpowers/"
    echo "graphify-out/"             # Graphify plugin output
    echo "qdrant-storage/"           # Qdrant plugin storage
    echo ".sumela/_migration/"       # brownfield migration quarantine (may hold legacy secrets — never commit)
    echo "AGENTS.md.bak*"            # setup backup(s) of a pre-existing AGENTS.md (may hold legacy secrets)
  } >> .gitignore
  ok ".gitignore SumelaOS block added"
fi

# Independent line-guards for entries added AFTER the block first shipped: the block
# above is skipped wholesale when `.sumela/local.md` is already present (an upgraded
# project), so newer lines would never land. Append each individually if missing —
# this keeps the secret-bearing quarantine + AGENTS backup ignored on the upgrade path.
for _ln in ".sumela/_migration/" "AGENTS.md.bak*"; do
  grep -qxF "$_ln" .gitignore 2>/dev/null || printf '%s\n' "$_ln" >> .gitignore
done

# Secret-file baseline — never commit credentials. Idempotent via its own marker
# (not a single content line) so all patterns land even when the project already
# ignored `.env`. The pre-commit hook adds a gitleaks scan on top if it's installed.
SECRET_MARKER="# SumelaOS — common secret files"
if [ -f .gitignore ] && grep -qF "$SECRET_MARKER" .gitignore; then
  ok ".gitignore already covers secret files"
else
  {
    [ -s .gitignore ] && echo ""
    echo "$SECRET_MARKER (never commit; see .sumela/rules/security_protocol.md)"
    echo ".env"
    echo ".env.*"
    echo "!.env.example"
    echo "!.env.*.example"
    echo "*.pem"
    echo "*.key"
    echo "*.p12"
    echo "*.pfx"
    echo "*.secret"
    echo "secrets.json"
  } >> .gitignore
  ok ".gitignore secret-file baseline added"
fi

# =============================================================================
# 7. REGISTER MEMORY PLUGINS
# =============================================================================
if [ ${#PLUGINS[@]} -gt 0 ]; then
  info "Registering memory plugins in SKILL_REGISTRY.md..."

  PLUGIN_ENTRIES=""
  for plugin in ${PLUGINS[@]+"${PLUGINS[@]}"}; do
    plugin=$(echo "$plugin" | tr -d ' ')
    if [ ! -f ".sumela/memory-plugins/$plugin/SKILL.md" ]; then
      warn "Plugin SKILL.md not found: .sumela/memory-plugins/$plugin/SKILL.md"
    elif grep -q "<name>$plugin</name>" .sumela/SKILL_REGISTRY.md; then
      # Idempotent: the shipped registry may already list this plugin.
      info "Plugin already registered: $plugin — skipping"
    else
      PLUGIN_ENTRIES="${PLUGIN_ENTRIES}
<skill activation=\"lazy\">
<name>$plugin</name>
<description>Memory plugin — see \`.sumela/memory-plugins/$plugin/SKILL.md\` for routing and prerequisites.</description>
<path>.sumela/memory-plugins/$plugin/SKILL.md</path>
</skill>
"
      ok "Registered plugin: $plugin"
    fi
  done

  # Insert plugin entries before the closing </available_skills> tag.
  # Done via python3 (already required by render_template) — BSD awk on macOS
  # rejects multi-line `-v` variables ("awk: newline in string").
  if [ -n "$PLUGIN_ENTRIES" ]; then
    export TMPL_PLUGIN_ENTRIES="$PLUGIN_ENTRIES"
    python3 -c "
import os, sys
path = '.sumela/SKILL_REGISTRY.md'
entries = os.environ['TMPL_PLUGIN_ENTRIES']
with open(path, 'r') as f:
    content = f.read()
tag = '</available_skills>'
if tag in content:
    content = content.replace(tag, entries + '\n' + tag, 1)
    with open(path, 'w') as f:
        f.write(content)
else:
    sys.stderr.write('WARN: </available_skills> tag not found; plugins not appended\n')
"
    ok "Plugins appended to SKILL_REGISTRY.md"
  fi
fi

# =============================================================================
# 7b-memory. BRING UP THE MEMORY RUNTIME (auto-safe + confirm-invasive)
# =============================================================================
# Copying the plugin files isn't enough — the developer would still have to install
# Qdrant/Ollama/graphify by hand. setup-memory.sh closes that: it auto-installs the
# cheap/safe deps (pip) and confirms-and-runs the invasive ones (start Qdrant via
# Docker, pull the Ollama model, install the graphify CLI), leaving no manual homework.
if [ ${#PLUGINS[@]} -gt 0 ] && [ -f scripts/setup-memory.sh ] && [ -z "${SUMELA_SKIP_MEMORY_SETUP:-}" ]; then
  MEM_LIST="$(IFS=,; echo "${PLUGINS[*]}")"; MEM_LIST="$(echo "$MEM_LIST" | tr -d ' ')"
  info "Setting up the memory runtime (auto-installs safe deps; asks before invasive steps)..."
  if [ "$NON_INTERACTIVE" = true ]; then
    # CI/automation: never start services silently — print exact commands instead.
    bash scripts/setup-memory.sh --plugins "$MEM_LIST" --non-interactive || true
  else
    bash scripts/setup-memory.sh --plugins "$MEM_LIST" || true
  fi
fi

# =============================================================================
# 7c. INSTALL GIT HOOKS (core.hooksPath — pre-commit validation + memory sync)
# =============================================================================
# Wired whenever the project is a git repo: the pre-commit validation hook is
# useful for everyone, and the post-merge/post-checkout memory hooks self-gate
# (they no-op unless the Qdrant plugin + summaries + a reachable Qdrant exist).
# Logic lives in wire_git_hooks() near the top (shared with the --hooks-only path).
wire_git_hooks

# =============================================================================
# 7d. GOVERNANCE — CODEOWNERS for the agent-control surface (team mode only)
# =============================================================================
if [ "$GOVERNANCE" = "team" ]; then
  info "Ensuring CODEOWNERS covers the agent-control surface (team mode)..."
  CODEOWNERS_FILE=".github/CODEOWNERS"
  CODEOWNERS_MARKER="# SumelaOS agent-control surface"
  if [ -f "$CODEOWNERS_FILE" ] && grep -qF "$CODEOWNERS_MARKER" "$CODEOWNERS_FILE"; then
    ok "CODEOWNERS already covers the agent-control surface"
  else
    mkdir -p .github
    {
      [ -s "$CODEOWNERS_FILE" ] && echo ""
      echo "$CODEOWNERS_MARKER — changes here alter every developer's agent."
      echo "# Replace @OWNER with your team/maintainer handle (e.g. @org/maintainers)."
      echo "/AGENTS.md                          @OWNER"
      echo "/.sumela/rules/                     @OWNER"
      echo "/.sumela/skills/                    @OWNER"
      echo "/.sumela/sumela-prompt.md           @OWNER"
      echo "/.sumela/RULE_REGISTRY.md           @OWNER"
      echo "/.sumela/SKILL_REGISTRY.md          @OWNER"
      echo "/.sumela/git-hooks/                 @OWNER"
      echo "/docs/second-brain/wiki/_SCHEMA.md  @OWNER"
    } >> "$CODEOWNERS_FILE"
    ok "CODEOWNERS updated ($CODEOWNERS_FILE) — replace @OWNER with your handle"
  fi
fi

# =============================================================================
# 7e. CI WORKFLOW — run validate-structure on push/PR (opt-in: --ci / prompt)
# =============================================================================
if [ "$WITH_CI" = true ]; then
  CI_FILE=".github/workflows/sumela-validate.yml"
  if [ -f "$CI_FILE" ]; then
    ok "CI workflow already present ($CI_FILE)"
  else
    info "Adding CI validation workflow ($CI_FILE)..."
    mkdir -p .github/workflows
    cat > "$CI_FILE" <<'YAML'
name: SumelaOS Validate

# Enforces the SumelaOS structure contract on every push / PR. Mirrors
# scripts/validate-structure.sh — the same check the pre-commit hook runs locally.
# Not on GitHub? See docs/second-brain/ADOPTION_GUIDE.md for a GitLab / Azure equivalent.

on:
  push:
    branches: ["**"]
  pull_request:

permissions:
  contents: read

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Validate SumelaOS structure (+ unfilled placeholders)
        run: bash scripts/validate-structure.sh --check-placeholders
      - name: IDE mirror drift check (no-op unless .sumela/mirrors.conf lists mirrors)
        run: bash scripts/sync-mirrors.sh --check
      - name: Shell script syntax check
        run: |
          set -e
          for f in scripts/*.sh; do [ -f "$f" ] && bash -n "$f"; done
          for h in .sumela/git-hooks/_lib.sh .sumela/git-hooks/pre-commit \
                   .sumela/git-hooks/post-merge .sumela/git-hooks/post-checkout; do
            [ -f "$h" ] && bash -n "$h"
          done
      - name: PowerShell script parse check
        shell: pwsh
        run: |
          $bad = 0
          Get-ChildItem -Recurse -Filter *.ps1 -ErrorAction SilentlyContinue | ForEach-Object {
            $tokens = $null; $errs = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errs)
            if ($errs) { Write-Host "::error::Parse errors in $($_.FullName)"; $errs | ForEach-Object { Write-Host "  $($_.Extent.StartLineNumber): $($_.Message)" }; $bad = 1 }
          }
          if ($bad) { exit 1 } else { Write-Host "PowerShell scripts parse clean." }
YAML
    ok "CI workflow added — GitHub Actions; delete it if you use other CI (GitLab/Azure: see ADOPTION_GUIDE)"
  fi
fi

# =============================================================================
# 7f. SYNC ORG-SHARED RULES (monorepo — no-op unless .sumela-shared/rules/ exists)
# =============================================================================
if [ -f scripts/sync-shared-rules.py ] && command -v python3 >/dev/null 2>&1; then
  shr_out="$(python3 scripts/sync-shared-rules.py --check 2>&1)"
  case "$shr_out" in
    *"no .sumela-shared/rules"*) : ;;   # not a shared-rules monorepo — silent
    *)
      info "Syncing org-shared rules from .sumela-shared/rules/ ..."
      python3 scripts/sync-shared-rules.py | sed 's/^/  /'
      ok "Org-shared rules synced + registered (universal)." ;;
  esac
fi

# =============================================================================
# 8. RUN VALIDATION
# =============================================================================
echo ""
info "Running structure validation..."
echo ""

VALIDATION_FAILED=false
if bash scripts/validate-structure.sh --check-placeholders --post-setup; then
  echo ""
  ok "Validation passed"
else
  echo ""
  warn "Validation had failures — review output above"
  VALIDATION_FAILED=true
fi

# =============================================================================
# 9. SUMMARY
# =============================================================================
echo ""
echo "${BOLD}=== Setup Complete ===${RESET}"
echo ""
echo "  Project:    $PROJECT_NAME"
echo "  Purpose:    $PROJECT_PURPOSE"
echo "  Governance: $GOVERNANCE"
echo "  Stacks:     ${STACKS[*]:-none}"
echo "  Rule variant: $RULE_VARIANT"
echo "  Plugins:    ${PLUGINS[*]:-none}"
echo "  IDEs:       ${IDES[*]:-none}"
echo ""
echo "  Files generated:"
echo "    - AGENTS.md"
echo "    - .sumela/RULE_REGISTRY.md"
echo "    - .sumela/rules/ (stack-specific rules)"
echo "    - docs/second-brain/wiki/ (6 wiki pages)"
[ ${#IDES[@]} -gt 0 ] && echo "    - IDE pointer files"
[ ${#PLUGINS[@]} -gt 0 ] && echo "    - SKILL_REGISTRY.md (plugins appended)"
[ "$HOOKS_WIRED" = true ] && echo "    - git hooks wired (core.hooksPath = .sumela/git-hooks; pre-commit validation)"
[ "$GOVERNANCE" = "team" ] && echo "    - .github/CODEOWNERS (agent-control surface — replace @OWNER)"
[ "$WITH_CI" = true ] && echo "    - .github/workflows/sumela-validate.yml (CI structure check)"
echo ""
echo "  Next steps:"
echo "    1. Edit AGENTS.md — fill in project-specific commands and conventions"
echo "    2. Edit .sumela/rules/*.md — customize stack standards"
echo "    3. Edit docs/second-brain/wiki/active-project-context.md — add current sprint"
echo "    4. Review .sumela/RULE_REGISTRY.md — adjust stack scopes if needed"
[ ${#PLUGINS[@]} -gt 0 ] && echo "    5. Install plugin dependencies: pip install -r .sumela/memory-plugins/*/requirements.txt"
echo ""

# Exit non-zero if our own validation failed — otherwise the "Setup Complete" banner
# masks a broken project (e.g. a registered rule whose file is missing), and the user
# only discovers it when the pre-commit hook blocks their next commit.
if [ "$VALIDATION_FAILED" = true ]; then
  err "Setup finished but structure validation FAILED — fix the issues listed above before committing (the pre-commit hook will otherwise block you)."
  exit 1
fi
