#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# setup-relay.sh — enable the optional Teammate Relay (team plugin).
# Mirrors setup-memory.sh: registering it is what turns "files present" into
# "feature enabled". Safe to re-run (idempotent). Declining = never run this.
#
# Usage:
#   bash scripts/setup-relay.sh --server-url wss://relay.example.com:8765 \
#        [--verify-key-file path/to/server.pub.pem] [--self-host] \
#        [--yes] [--non-interactive]
# -----------------------------------------------------------------------------
set -euo pipefail

SERVER_URL=""; VERIFY_KEY_FILE=""; SELF_HOST=false; ASSUME_YES=false; NON_INTERACTIVE=false
while [ $# -gt 0 ]; do
  case "$1" in
    --server-url)       SERVER_URL="$2"; shift 2 ;;
    --verify-key-file)  VERIFY_KEY_FILE="$2"; shift 2 ;;
    --self-host)        SELF_HOST=true; shift ;;
    --yes)              ASSUME_YES=true; shift ;;
    --non-interactive)  NON_INTERACTIVE=true; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

PLUGDIR=".sumela/team-plugins/teammate-relay"
REG=".sumela/SKILL_REGISTRY.md"
CFG="$PLUGDIR/relay-config.md"
# Target the SAME CODEOWNERS init-sumela uses + GitHub's precedence (.github/ first), so the
# relay gate lands where GitHub actually enforces it (not a shadowed root file).
if [ -f ".github/CODEOWNERS" ]; then CO=".github/CODEOWNERS"
elif [ -f "CODEOWNERS" ]; then CO="CODEOWNERS"
elif [ -d ".github" ]; then CO=".github/CODEOWNERS"
else CO="CODEOWNERS"; fi

if command -v tput >/dev/null 2>&1 && [ -t 1 ]; then
  B=$(tput bold); G=$(tput setaf 2); Y=$(tput setaf 3); C=$(tput setaf 6); R=$(tput sgr0)
else B="" G="" Y="" C="" R=""; fi
ok(){ echo "  ${G}ok${R}    $1"; }
todo(){ echo "  ${Y}todo${R}  $1"; }
info(){ echo "  ${C}info${R}  $1"; }
section(){ echo ""; echo "${B}$1${R}"; }
confirm() {
  $ASSUME_YES && return 0
  $NON_INTERACTIVE && return 1
  [ -t 1 ] && [ -r /dev/tty ] || return 1
  printf '  %s [Y/n] ' "$1" >/dev/tty
  local a=""; read -r a </dev/tty 2>/dev/null || a=""
  case "$a" in n|N|no|NO) return 1 ;; *) return 0 ;; esac
}

echo "${B}SumelaOS teammate-relay setup${R}"
[ -d "$PLUGDIR" ] || { echo "relay plugin not present at $PLUGDIR — re-run bootstrap first." >&2; exit 1; }
case "$SERVER_URL" in
  ""|wss://*) : ;;
  *) echo "refusing: --server-url must be wss:// (TLS required; got '$SERVER_URL')" >&2; exit 2 ;;
esac

# 1) Register the skill in SKILL_REGISTRY.md (description copied from the SKILL.md
#    frontmatter so the registry routing surface matches the skill — parity).
section "Register skill"
if [ -f "$REG" ] && grep -q "<name>teammate-relay</name>" "$REG"; then
  ok "teammate-relay already registered"
elif [ -f "$REG" ]; then
  if python3 - "$REG" "$PLUGDIR/SKILL.md" <<'PY'
import re, sys
reg, skill = sys.argv[1], sys.argv[2]
fm = re.match(r'^---\n(.*?)\n---', open(skill, encoding="utf-8").read(), re.S)
desc = ""
if fm:
    m = re.search(r'description:\s*"(.*?)"\s*$', fm.group(1), re.S | re.M)
    desc = (m.group(1) if m else "").replace("\n", " ").strip()
entry = ('\n<skill activation="lazy">\n<name>teammate-relay</name>\n'
         '<description>%s</description>\n'
         '<path>.sumela/team-plugins/teammate-relay/SKILL.md</path>\n</skill>\n') % desc
s = open(reg, encoding="utf-8").read()
tag = "</available_skills>"
if tag not in s:
    sys.exit(1)
open(reg, "w", encoding="utf-8").write(s.replace(tag, entry + "\n" + tag, 1))
PY
  then ok "Registered teammate-relay in SKILL_REGISTRY.md"; else todo "register teammate-relay by hand"; fi
else
  todo "no SKILL_REGISTRY.md — run /initSumela first"
fi

# 2) Write the committed relay-config.md (URL + pinned server verify-key; NO secrets).
section "Project config"
if [ -f "$CFG" ]; then
  ok "relay-config.md already present (leaving as-is)"
elif [ -n "$SERVER_URL" ]; then
  vk="$( [ -n "$VERIFY_KEY_FILE" ] && [ -f "$VERIFY_KEY_FILE" ] && sed 's/^/  /' "$VERIFY_KEY_FILE" || echo "  # paste the server verify-key PEM here (server/DEPLOY.md prints it)" )"
  {
    echo "# Teammate Relay — project configuration (COMMITTED, team-wide, CODEOWNERS-gated; no secrets)"
    echo '```yaml'
    echo "server_url: $SERVER_URL"
    echo "server_verify_key: |"
    echo "$vk"
    echo '```'
  } > "$CFG"
  ok "Wrote $CFG"
else
  todo "no --server-url given — write $CFG from relay-config.example.md by hand"
fi
# Scaffold the committed role map (domain -> owners) so `ask.py --domain` works; edit it after.
if [ -f "$PLUGDIR/roles.json" ]; then ok "roles.json present"
elif [ -f "$PLUGDIR/roles.example.json" ]; then
  cp "$PLUGDIR/roles.example.json" "$PLUGDIR/roles.json"; todo "edit $PLUGDIR/roles.json: map your real domains -> member ids"
fi

# 3) Ensure the key-trust surface is CODEOWNERS-gated (validate-structure §8b requires this
#    whenever the relay is configured). Append patterns if missing; create the file if absent.
section "CODEOWNERS gate"
need_keys='**/teammate-relay/keys/'
need_cfg='**/teammate-relay/relay-config.md'
need_roles='**/teammate-relay/roles.json'
mkdir -p "$(dirname "$CO")"; touch "$CO"
add_gate() {  # $1 = path-glob
  if grep -qF "$1" "$CO"; then ok "gated: $1"; else
    printf '%s @REPLACE-WITH-RELAY-OWNERS\n' "$1" >> "$CO"
    todo "set real owners for '$1' in CODEOWNERS (placeholder written)"
  fi
}
if ! grep -q "Teammate Relay key-trust surface" "$CO" 2>/dev/null; then
  echo "" >> "$CO"; echo "# Teammate Relay key-trust surface — changes here are security-critical." >> "$CO"
fi
add_gate "$need_keys"
add_gate "$need_cfg"
add_gate "$need_roles"     # routing authority — an unreviewed roles.json edit could harvest questions (I2)

# 4) Python deps (cheap, project-local) — auto.
section "Dependencies"
if command -v python3 >/dev/null 2>&1; then
  python3 -m pip install -q -r "$PLUGDIR/requirements.txt" 2>/dev/null && ok "Python deps installed" \
    || todo "pip install -r $PLUGDIR/requirements.txt (do it in your venv)"
else
  todo "install Python 3.10+ then: pip install -r $PLUGDIR/requirements.txt"
fi

# 5) Optional: start a local relay SERVER via Docker (confirm; never auto on a server box).
if $SELF_HOST; then
  section "Relay server (self-host)"
  if command -v docker >/dev/null 2>&1 && confirm "Start the relay server via docker compose now?"; then
    ( cd "$PLUGDIR/server" && docker compose up -d ) && ok "relay server started (see server/DEPLOY.md for TLS + enrollment)" \
      || todo "docker compose up failed — see $PLUGDIR/server/DEPLOY.md"
  else
    todo "start the server on your box: cd $PLUGDIR/server && docker compose up -d (then see DEPLOY.md)"
  fi
fi

# 6) Per-developer client identity + daemon is provisioned by /onboardSumela, not here.
section "Next"
info "each developer runs /onboardSumela to create their identity + start the client daemon"
echo ""; ok "teammate-relay enabled"
