# -----------------------------------------------------------------------------
# setup-relay.ps1 — enable the optional Teammate Relay (team plugin). PowerShell
# parity with setup-relay.sh: same flags, same idempotent register+config+CODEOWNERS
# behavior, same exit contract. Declining = never run this.
#
# Usage:
#   pwsh scripts/setup-relay.ps1 -ServerUrl wss://relay.example.com:8765 `
#        [-VerifyKeyFile path] [-SelfHost] [-Yes] [-NonInteractive]
# -----------------------------------------------------------------------------
param(
    [string]$ServerUrl = "",
    [string]$VerifyKeyFile = "",
    [switch]$SelfHost,
    [switch]$Yes,
    [switch]$NonInteractive
)
$ErrorActionPreference = "Stop"

$PlugDir = ".sumela/team-plugins/teammate-relay"
$Reg = ".sumela/SKILL_REGISTRY.md"
$Cfg = "$PlugDir/relay-config.md"
# Match init-sumela + GitHub precedence (.github/ first) so the gate lands where it's enforced.
if (Test-Path ".github/CODEOWNERS") { $Co = ".github/CODEOWNERS" }
elseif (Test-Path "CODEOWNERS") { $Co = "CODEOWNERS" }
elseif (Test-Path ".github") { $Co = ".github/CODEOWNERS" }
else { $Co = "CODEOWNERS" }

function Ok($m)      { Write-Host "  ok    $m" }
function Todo($m)    { Write-Host "  todo  $m" }
function Info($m)    { Write-Host "  info  $m" }
function Section($m) { Write-Host ""; Write-Host $m }
function Confirm($m) {
    if ($Yes) { return $true }
    if ($NonInteractive) { return $false }
    $a = Read-Host "  $m [Y/n]"
    return ($a -notmatch '^(n|N|no|NO)$')
}

Write-Host "SumelaOS teammate-relay setup"
if (-not (Test-Path $PlugDir)) { Write-Error "relay plugin not present at $PlugDir — re-run bootstrap first."; exit 1 }
if ($ServerUrl -ne "" -and -not $ServerUrl.StartsWith("wss://")) {
    Write-Error "refusing: -ServerUrl must be wss:// (TLS required; got '$ServerUrl')"; exit 2
}

# 1) Register the skill (description copied from SKILL.md frontmatter — parity).
Section "Register skill"
if ((Test-Path $Reg) -and (Select-String -Path $Reg -SimpleMatch "<name>teammate-relay</name>" -Quiet)) {
    Ok "teammate-relay already registered"
} elseif (Test-Path $Reg) {
    $skill = Get-Content "$PlugDir/SKILL.md" -Raw
    $desc = ""
    if ($skill -match '(?s)^---\s*\n(.*?)\n---') {
        $fm = $Matches[1]
        if ($fm -match '(?s)description:\s*"(.*?)"\s*$') { $desc = ($Matches[1] -replace '\s*\n\s*', ' ').Trim() }
    }
    $entry = "`n<skill activation=`"lazy`">`n<name>teammate-relay</name>`n<description>$desc</description>`n<path>.sumela/team-plugins/teammate-relay/SKILL.md</path>`n</skill>`n"
    $s = Get-Content $Reg -Raw
    $tag = "</available_skills>"
    if ($s.Contains($tag)) {
        # first-occurrence replace (parity with the bash version's .replace(tag, ..., 1))
        $idx = $s.IndexOf($tag)
        $s = $s.Substring(0, $idx) + $entry + "`n" + $s.Substring($idx)
        Set-Content -NoNewline $Reg $s
        Ok "Registered teammate-relay in SKILL_REGISTRY.md"
    } else { Todo "register teammate-relay by hand (no </available_skills> anchor)" }
} else {
    Todo "no SKILL_REGISTRY.md — run /initSumela first"
}

# 2) Write the committed relay-config.md (no secrets).
Section "Project config"
if (Test-Path $Cfg) {
    Ok "relay-config.md already present (leaving as-is)"
} elseif ($ServerUrl -ne "") {
    if ($VerifyKeyFile -ne "" -and (Test-Path $VerifyKeyFile)) {
        $vk = (Get-Content $VerifyKeyFile | ForEach-Object { "  $_" }) -join "`n"
    } else { $vk = "  # paste the server verify-key PEM here (server/DEPLOY.md prints it)" }
    @(
        "# Teammate Relay — project configuration (COMMITTED, team-wide, CODEOWNERS-gated; no secrets)",
        '```yaml',
        "server_url: $ServerUrl",
        "server_verify_key: |",
        $vk,
        '```'
    ) -join "`n" | Set-Content $Cfg
    Ok "Wrote $Cfg"
} else {
    Todo "no -ServerUrl given — write $Cfg from relay-config.example.md by hand"
}
# Scaffold the committed role map so `ask.py --domain` works; edit it after.
if (Test-Path "$PlugDir/roles.json") { Ok "roles.json present" }
elseif (Test-Path "$PlugDir/roles.example.json") {
    Copy-Item "$PlugDir/roles.example.json" "$PlugDir/roles.json"
    Todo "edit $PlugDir/roles.json: map your real domains -> member ids"
}

# 3) CODEOWNERS gate (validate-structure §8b requires it when relay is configured).
Section "CODEOWNERS gate"
$coDir = Split-Path -Parent $Co
if ($coDir -and -not (Test-Path $coDir)) { New-Item -ItemType Directory -Path $coDir | Out-Null }
if (-not (Test-Path $Co)) { New-Item -ItemType File -Path $Co | Out-Null }
$coText = Get-Content $Co -Raw -ErrorAction SilentlyContinue
if ($null -eq $coText) { $coText = "" }
if ($coText -notmatch "Teammate Relay key-trust surface") {
    Add-Content $Co "`n# Teammate Relay key-trust surface — changes here are security-critical."
}
foreach ($g in @("**/teammate-relay/keys/", "**/teammate-relay/relay-config.md", "**/teammate-relay/roles.json")) {
    if ((Get-Content $Co -Raw).Contains($g)) { Ok "gated: $g" }
    else { Add-Content $Co "$g @REPLACE-WITH-RELAY-OWNERS"; Todo "set real owners for '$g' in CODEOWNERS" }
}

# 4) Python deps.
Section "Dependencies"
if (Get-Command python3 -ErrorAction SilentlyContinue) {
    try { python3 -m pip install -q -r "$PlugDir/requirements.txt"; Ok "Python deps installed" }
    catch { Todo "pip install -r $PlugDir/requirements.txt (do it in your venv)" }
} else { Todo "install Python 3.10+ then: pip install -r $PlugDir/requirements.txt" }

# 5) Optional self-hosted server.
if ($SelfHost) {
    Section "Relay server (self-host)"
    if ((Get-Command docker -ErrorAction SilentlyContinue) -and (Confirm "Start the relay server via docker compose now?")) {
        Push-Location "$PlugDir/server"; try { docker compose up -d; Ok "relay server started (see server/DEPLOY.md)" }
        catch { Todo "docker compose up failed — see server/DEPLOY.md" } finally { Pop-Location }
    } else { Todo "start the server: cd $PlugDir/server; docker compose up -d (then see DEPLOY.md)" }
}

Section "Next"
Info "each developer runs /onboardSumela to create their identity + start the client daemon"
Write-Host ""; Ok "teammate-relay enabled"
