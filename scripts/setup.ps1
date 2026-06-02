<#
.SYNOPSIS
    SumelaOS Template Interactive Setup (PowerShell).

.DESCRIPTION
    Generates project-specific files from templates. Asks the user for
    configuration, copies selected rule templates, generates IDE pointer files,
    optionally registers memory plugins, and runs validation.

.PARAMETER NonInteractive
    Run without prompts. Requires ProjectName and other parameters.

.PARAMETER ProjectName
    Name of the project (required in non-interactive mode).

.PARAMETER ProjectPurpose
    Purpose/description of the project.

.PARAMETER InteractionLanguage
    Language for user interaction (default: English).

.PARAMETER CodeLanguage
    Fallback language for code naming + documentation (default: English).

.PARAMETER NamingLanguage
    Language for code names (services, methods, classes, files). Defaults to CodeLanguage.

.PARAMETER DocumentationLanguage
    Language for code comments and docstrings. Defaults to CodeLanguage.

.PARAMETER Stacks
    Comma-separated list of tech stacks: backend, frontend, mobile, ai, infra.

.PARAMETER RuleVariant
    Rule template variant: empty or best-practice (default: best-practice).

.PARAMETER Plugins
    Comma-separated list of plugins: qdrant-session-memory, graphify-code-graph.

.PARAMETER IDEs
    Comma-separated list of IDEs: claude, cursor, cline, kilo-code, trae, opencode.

.PARAMETER Governance
    Governance mode: solo (apply /evolve changes directly) or team (PR-gate the
    agent-control surface). Default: solo.

.PARAMETER Ci
    Opt in to creating the GitHub Actions validation workflow (default: off).

.EXAMPLE
    pwsh -File scripts/setup.ps1

.EXAMPLE
    pwsh -File scripts/setup.ps1 -NonInteractive -ProjectName "MyApp" -Stacks "backend,frontend" -IDEs "claude,cursor"
#>

param(
    [switch]$NonInteractive,
    [string]$ProjectName = "",
    [string]$ProjectPurpose = "A software project",
    [string]$InteractionLanguage = "English",
    [string]$CodeLanguage = "English",
    [string]$NamingLanguage = "",
    [string]$DocumentationLanguage = "",
    [string]$Stacks = "",
    [string]$RuleVariant = "best-practice",
    [string]$Plugins = "",
    [string]$IDEs = "",
    [string]$Governance = "solo",
    [switch]$Ci
)

$ErrorActionPreference = "Stop"

# --- Colors ---
function Write-Info  { param([string]$msg) Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Ok    { param([string]$msg) Write-Host "[OK]   $msg" -ForegroundColor Green }
function Write-Warn  { param([string]$msg) Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Err   { param([string]$msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }

# --- Cleanup on Ctrl+C ---
$cleanupRegistered = $false
try {
    [Console]::TreatControlCAsInput = $false
} catch {
    # Not all terminals support this
}

# --- Template existence preflight ---
$RequiredTemplates = @(
    "AGENTS.md.template",
    ".sumela/RULE_REGISTRY.md.template",
    "CLAUDE.md.template",
    ".clinerules.template",
    ".cursor/rules/00-agent.md.template",
    ".kilocode/rules.md.template",
    ".trae/rules/00-agent.md.template",
    ".opencode/AGENTS.md.template",
    "docs/second-brain/template/wiki/_INDEX.md.template",
    "docs/second-brain/template/wiki/_LOG.md.template",
    "docs/second-brain/template/wiki/_SEARCH_INDEX.md.template",
    "docs/second-brain/template/wiki/_improvement-queue/README.md",
    "docs/second-brain/template/wiki/_SCHEMA.md",
    "docs/second-brain/template/wiki/active-project-context.md.template"
)

$MissingTemplates = @()
foreach ($tmpl in $RequiredTemplates) {
    if (-not (Test-Path $tmpl)) {
        $MissingTemplates += $tmpl
    }
}

if ($MissingTemplates.Count -gt 0) {
    Write-Err "Missing template files:"
    foreach ($m in $MissingTemplates) {
        Write-Host "  - $m"
    }
    exit 1
}

# --- Helper: prompt with default ---
function Read-WithDefault {
    param([string]$Prompt, [string]$Default)
    $result = Read-Host "$Prompt [$Default]"
    if ([string]::IsNullOrWhiteSpace($result)) { return $Default }
    return $result
}

# --- Helper: multi-select ---
function Read-MultiSelect {
    param([string]$Prompt, [string[]]$Options)
    Write-Host $Prompt
    for ($i = 0; $i -lt $Options.Count; $i++) {
        Write-Host "  $($i + 1). $($Options[$i])"
    }
    $selection = Read-Host "Enter numbers separated by commas (e.g. 1,3)"
    $result = @()
    foreach ($num in ($selection -split ",")) {
        $num = $num.Trim()
        if ($num -match '^\d+$' -and [int]$num -ge 1 -and [int]$num -le $Options.Count) {
            $result += $Options[[int]$num - 1]
        }
    }
    return $result
}

# --- Helper: yes/no ---
function Read-YesNo {
    param([string]$Prompt, [string]$Default = "n")
    $result = Read-Host "$Prompt [y/n, default: $Default]"
    if ([string]::IsNullOrWhiteSpace($result)) { $result = $Default }
    return $result -match '^[yY]'
}

# =============================================================================
# 1. COLLECT CONFIGURATION
# =============================================================================
Write-Host ""
Write-Host "=== SumelaOS Template Setup ===" -ForegroundColor White
Write-Host ""

if ($NonInteractive) {
    if ([string]::IsNullOrWhiteSpace($ProjectName)) {
        Write-Err "-ProjectName is required in non-interactive mode"
        exit 1
    }
    $StackArray = if ($Stacks) { $Stacks -split "," } else { @() }
    $PluginArray = if ($Plugins) { $Plugins -split "," } else { @() }
    $IDEArray = if ($IDEs) { $IDEs -split "," } else { @() }
}
else {
    $ProjectName = Read-WithDefault "Project name" ""
    if ([string]::IsNullOrWhiteSpace($ProjectName)) {
        Write-Err "Project name is required"
        exit 1
    }

    $ProjectPurpose = Read-WithDefault "Project purpose" "A software project"
    $InteractionLanguage = Read-WithDefault "Interaction language (agent chat/explanations)" "English"
    $NamingLanguage = Read-WithDefault "Code naming language (services, methods, classes, files)" "English"
    $DocumentationLanguage = Read-WithDefault "Code documentation language (comments, docstrings)" "English"
    # CodeLanguage retained for backward-compat consumers; mirrors the naming language.
    $CodeLanguage = $NamingLanguage

    Write-Host ""
    # AI and infra stacks coming soon — not yet available
    $StackArray = Read-MultiSelect "Select tech stacks:" @("backend", "frontend", "mobile")

    Write-Host ""
    $RuleVariant = Read-WithDefault "Rule variant for selected stacks (empty/best-practice)" "best-practice"

    Write-Host ""
    $PluginArray = @()
    if (Read-YesNo "Enable qdrant-session-memory plugin?" "n") { $PluginArray += "qdrant-session-memory" }
    if (Read-YesNo "Enable graphify-code-graph plugin?" "n") { $PluginArray += "graphify-code-graph" }

    Write-Host ""
    $IDEArray = Read-MultiSelect "IDEs to generate pointer files for:" @("claude", "cursor", "cline", "kilo-code", "trae", "opencode")

    Write-Host ""
    Write-Host "Governance mode controls how /evolve applies changes to the agent-control surface (rules/skills/prompt/schema):"
    Write-Host "  solo — apply directly (one developer owns the config)"
    Write-Host "  team — route through a pull request so a code owner reviews before it becomes everyone's standard"
    $Governance = Read-WithDefault "Governance mode (solo/team)" "solo"

    Write-Host ""
    Write-Host "Optional: a GitHub Actions workflow that runs the structure validation on push/PR."
    Write-Host "(Skip if you use GitLab/Azure/no CI — see ADOPTION_GUIDE for those.)"
    if (Read-YesNo "Add the GitHub Actions CI workflow?" "n") { $Ci = $true }
}

# CI workflow is opt-in (-Ci switch, or 'y' at the interactive prompt).
$WithCi = [bool]$Ci

# Default naming/documentation languages to CodeLanguage when not supplied (non-interactive parity).
if ([string]::IsNullOrWhiteSpace($NamingLanguage)) { $NamingLanguage = $CodeLanguage }
if ([string]::IsNullOrWhiteSpace($DocumentationLanguage)) { $DocumentationLanguage = $CodeLanguage }

# Normalize / validate governance value.
$Governance = $Governance.ToLower().Trim()
if ($Governance -ne "team") { $Governance = "solo" }

$DateCreated = Get-Date -Format "yyyy-MM-dd"

Write-Info "Project: $ProjectName"
Write-Info "Governance: $Governance"
Write-Info "Stacks: $(if ($StackArray.Count) { $StackArray -join ', ' } else { 'none' })"
Write-Info "Rule variant: $RuleVariant"
Write-Info "Plugins: $(if ($PluginArray.Count) { $PluginArray -join ', ' } else { 'none' })"
Write-Info "IDEs: $(if ($IDEArray.Count) { $IDEArray -join ', ' } else { 'none' })"
Write-Host ""

# =============================================================================
# 2. GENERATE AGENTS.md
# =============================================================================
Write-Info "Generating AGENTS.md from template..."

# Build tech stack summary
$TechSummary = @()
if ($StackArray -contains "backend") { $TechSummary += "Backend" }
if ($StackArray -contains "frontend") { $TechSummary += "Frontend" }
if ($StackArray -contains "mobile") { $TechSummary += "Mobile" }
$TechSummaryStr = if ($TechSummary.Count) { $TechSummary -join " + " } else { "TBD" }

# Build package boundaries
$PkgBoundaries = @()
if ($StackArray -contains "backend")  { $PkgBoundaries += "| ``src/`` | Backend | ``main`` |" }
if ($StackArray -contains "frontend") { $PkgBoundaries += "| ``web/`` | Frontend | ``npm run dev`` |" }
if ($StackArray -contains "mobile")   { $PkgBoundaries += "| ``mobile/`` | Mobile | ``npx expo start`` |" }
$PkgBoundariesStr = if ($PkgBoundaries.Count) { $PkgBoundaries -join "`n" } else { "| TBD | TBD | TBD |" }

# Build commands
$BackendCmds = "# Add your backend build/run/test commands here"
$FrontendCmds = "# Add your frontend build/run/test commands here"
$MobileCmds = "# Add your mobile build/run/test commands here"
$InfraCmds = "# Add your Docker infrastructure commands here"

if ($StackArray -contains "backend") {
    $BackendCmds = @"
``````bash
# Build
./gradlew build   # or: dotnet build / mvn package / go build
# Run
./gradlew run     # or: dotnet run / mvn spring-boot:run / go run .
# Test
./gradlew test    # or: dotnet test / mvn test / go test ./...
``````
"@
}

if ($StackArray -contains "frontend") {
    $FrontendCmds = @"
``````bash
# Install dependencies
npm install       # or: yarn / pnpm install
# Run dev server
npm run dev
# Build
npm run build
# Test
npm run test
``````
"@
}

if ($StackArray -contains "mobile") {
    $MobileCmds = @"
``````bash
# Install dependencies
npx expo install
# Start dev server
npx expo start
# Build for Android
npx expo run:android
# Build for iOS
npx expo run:ios
``````
"@
}

# Dependency flow
$DepFlow = @"
``````$ProjectName -> Application -> Domain
         ^
   Infrastructure
``````
"@
if ($StackArray -notcontains "backend") {
    $DepFlow = "# Define your project dependency flow here"
}

# Project-specific security
$ProjectSecurity = ""
if ($StackArray -contains "backend") {
    $ProjectSecurity = "`n- Skill path: ``.sumela/rules/backend_standards.md`` — backend-specific security patterns."
}

# Perform replacements
$content = Get-Content "AGENTS.md.template" -Raw
$content = $content -replace '\{\{project_name\}\}', $ProjectName
$content = $content -replace '\{\{project_purpose\}\}', $ProjectPurpose
$content = $content -replace '\{\{tech_stack_summary\}\}', $TechSummaryStr
$content = $content -replace '\{\{interaction_language\}\}', $InteractionLanguage
$content = $content -replace '\{\{naming_language\}\}', $NamingLanguage
$content = $content -replace '\{\{documentation_language\}\}', $DocumentationLanguage
$content = $content -replace '\{\{backend_commands\}\}', $BackendCmds
$content = $content -replace '\{\{frontend_commands\}\}', $FrontendCmds
$content = $content -replace '\{\{mobile_commands\}\}', $MobileCmds
$content = $content -replace '\{\{infrastructure_commands\}\}', $InfraCmds
$content = $content -replace '\{\{dependency_flow\}\}', $DepFlow
$content = $content -replace '\{\{package_boundaries\}\}', $PkgBoundariesStr
$content = $content -replace '\{\{governance_mode\}\}', $Governance
$content = $content -replace '\{\{naming_conventions\}\}', "# Define your naming conventions here"
$content = $content -replace '\{\{technical_constraints\}\}', "# Define your technical constraints here"
$content = $content -replace '\{\{project_specific_security\}\}', $ProjectSecurity
$content | Set-Content "AGENTS.md" -NoNewline

Write-Ok "AGENTS.md generated"

# =============================================================================
# 3. GENERATE RULE_REGISTRY.md
# =============================================================================
Write-Info "Generating RULE_REGISTRY.md from template..."

# Build stack scopes
$StackScopes = @()
if ($StackArray -contains "backend")  { $StackScopes += "| ``backend`` | ``src/``, ``*.cs``, ``*.java``, ``*.go``, ``*.py``, ``api/``, ``server/`` |" }
if ($StackArray -contains "frontend") { $StackScopes += "| ``frontend`` | ``web/``, ``*.tsx``, ``*.jsx``, ``*.vue``, ``*.svelte`` |" }
if ($StackArray -contains "mobile")   { $StackScopes += "| ``mobile`` | ``mobile/``, ``*.swift``, ``*.kt``, ``app/`` |" }
$StackScopesStr = if ($StackScopes.Count) { $StackScopes -join "`n" } else { "| ``default`` | All project files |" }

# Build stack rules
$StackRules = ""
$StackRuleMap = @{
    "backend"  = @("backend_standards", "architecture layers, naming conventions, data access, API design, error handling, testing, security")
    "frontend" = @("frontend_standards", "component architecture, state management, styling, accessibility, build tooling, testing")
    "mobile"   = @("mobile_standards", "navigation, offline-first, push notifications, platform conventions, performance, testing")
}

foreach ($stack in $StackArray) {
    $stack = $stack.Trim()
    if ($StackRuleMap.ContainsKey($stack)) {
        $ruleName = $StackRuleMap[$stack][0]
        $ruleDesc = $StackRuleMap[$stack][1]
        $StackRules += @"

<rule activation="stack-conditional" applies_phases="planning,implementation,verification,code_review,debugging" stack="$stack">
<name>$ruleName</name>
<description>Use when the task scope includes $stack — $ruleDesc.</description>
<path>.sumela/rules/$ruleName.md</path>
</rule>
"@
    }
}

# Build phase matrix
$PhaseMatrix = @"
| ``ideation`` | engineering_philosophy, identity_and_behavior | architecture_patterns | (load matching stack rules) |
| ``specification`` | engineering_philosophy, identity_and_behavior | architecture_patterns | (load matching stack rules) |
| ``planning`` | engineering_philosophy, identity_and_behavior | architecture_patterns, operational_excellence_maintenance | (load matching stack rules) |
| ``implementation`` | engineering_philosophy, identity_and_behavior | audit_and_output | (load matching stack rules) |
| ``verification`` | engineering_philosophy, identity_and_behavior | audit_and_output | (load matching stack rules) |
| ``code_review`` | engineering_philosophy, identity_and_behavior | audit_and_output, git_workflow_mandatory_review_protocol | (load matching stack rules) |
| ``branch_finish`` | engineering_philosophy, identity_and_behavior | git_workflow_mandatory_review_protocol, operational_excellence_maintenance | (load matching stack rules) |
| ``shipping`` | engineering_philosophy, identity_and_behavior | operational_excellence_maintenance | (load matching stack rules) |
| ``debugging`` | engineering_philosophy, identity_and_behavior | audit_and_output | (load matching stack rules) |
"@

$content = Get-Content ".sumela/RULE_REGISTRY.md.template" -Raw
$content = $content -replace '\{\{stack_scopes\}\}', $StackScopesStr
$content = $content -replace '\{\{stack_rules\}\}', $StackRules
$content = $content -replace '\{\{phase_matrix_rows\}\}', $PhaseMatrix
$content = $content -replace '\{\{example_override\}\}', "backend"
$content | Set-Content ".sumela/RULE_REGISTRY.md" -NoNewline

Write-Ok "RULE_REGISTRY.md generated"

# =============================================================================
# 4. COPY RULE TEMPLATES
# =============================================================================
Write-Info "Copying rule templates (variant: $RuleVariant)..."

$StackRuleFileMap = @{
    "backend"  = "backend_standards"
    "frontend" = "frontend_standards"
    "mobile"   = "mobile_standards"
}

foreach ($stack in $StackArray) {
    $stack = $stack.Trim()
    if ($StackRuleFileMap.ContainsKey($stack)) {
        $ruleName = $StackRuleFileMap[$stack]
        $src = ".sumela/rules/templates/$ruleName.md.$RuleVariant"
        $dst = ".sumela/rules/$ruleName.md"
        if (Test-Path $src) {
            $content = Get-Content $src -Raw
            $content = $content -replace '\{\{date_created\}\}', $DateCreated
            $content | Set-Content $dst -NoNewline
            Write-Ok "Copied $dst"
        }
        else {
            Write-Warn "Template not found: $src — skipping"
        }
    }
    else {
        Write-Warn "No rule template for stack '$stack' — skipping"
    }
}

# Copy operational_excellence_maintenance (always needed)
$OpSrc = ".sumela/rules/templates/operational_excellence_maintenance.md.$RuleVariant"
$OpDst = ".sumela/rules/operational_excellence_maintenance.md"
if (Test-Path $OpSrc) {
    $content = Get-Content $OpSrc -Raw
    $content = $content -replace '\{\{date_created\}\}', $DateCreated
    $content | Set-Content $OpDst -NoNewline
    Write-Ok "Copied $OpDst"
}
else {
    Write-Warn "Template not found: $OpSrc — skipping"
}

# =============================================================================
# 5. GENERATE IDE POINTER FILES
# =============================================================================
Write-Info "Generating IDE pointer files..."

$IDEFileMap = @{
    "claude"    = @{ Dst = "CLAUDE.md"; Tmpl = "CLAUDE.md.template" }
    "cursor"    = @{ Dst = ".cursor/rules/00-agent.md"; Tmpl = ".cursor/rules/00-agent.md.template" }
    "cline"     = @{ Dst = ".clinerules"; Tmpl = ".clinerules.template" }
    "kilo-code" = @{ Dst = ".kilocode/rules.md"; Tmpl = ".kilocode/rules.md.template" }
    "trae"      = @{ Dst = ".trae/rules/00-agent.md"; Tmpl = ".trae/rules/00-agent.md.template" }
    "opencode"  = @{ Dst = ".opencode/AGENTS.md"; Tmpl = ".opencode/AGENTS.md.template" }
}

foreach ($ide in $IDEArray) {
    $ide = $ide.Trim()
    if ($IDEFileMap.ContainsKey($ide)) {
        $dst = $IDEFileMap[$ide].Dst
        $tmpl = $IDEFileMap[$ide].Tmpl
        if (Test-Path $tmpl) {
            $parentDir = Split-Path $dst -Parent
            if ($parentDir -and -not (Test-Path $parentDir)) {
                New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
            }
            $content = Get-Content $tmpl -Raw
            $content = $content -replace '\{\{project_name\}\}', $ProjectName
            $content | Set-Content $dst -NoNewline
            Write-Ok "Generated $dst"
        }
        else {
            Write-Warn "Template not found: $tmpl — skipping"
        }
    }
    else {
        Write-Warn "Unknown IDE: $ide — skipping"
    }
}

# =============================================================================
# 6. COPY WIKI TEMPLATES
# =============================================================================
Write-Info "Copying wiki templates..."

$wikiDirs = @(
    "docs/second-brain/wiki",
    "docs/second-brain/wiki/_improvement-queue",
    "docs/second-brain/raw_sources",
    "docs/second-brain/artifacts/plans",
    "docs/second-brain/artifacts/specs"
)

foreach ($dir in $wikiDirs) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

$WikiTemplates = @(
    @{ Src = "_INDEX.md.template"; Dst = "_INDEX.md" }
    @{ Src = "_LOG.md.template"; Dst = "_LOG.md" }
    @{ Src = "_SEARCH_INDEX.md.template"; Dst = "_SEARCH_INDEX.md" }
    @{ Src = "_SCHEMA.md"; Dst = "_SCHEMA.md" }
    @{ Src = "active-project-context.md.template"; Dst = "active-project-context.md" }
    @{ Src = "_improvement-queue/README.md"; Dst = "_improvement-queue/README.md" }
)

foreach ($entry in $WikiTemplates) {
    $src = "docs/second-brain/template/wiki/$($entry.Src)"
    $dst = "docs/second-brain/wiki/$($entry.Dst)"
    if (Test-Path $src) {
        $content = Get-Content $src -Raw
        $content = $content -replace '\{\{project_name\}\}', $ProjectName
        $content = $content -replace '\{\{date_created\}\}', $DateCreated
        $content | Set-Content $dst -NoNewline
        Write-Ok "Copied $dst"
    }
    else {
        Write-Warn "Template not found: $src — skipping"
    }
}

# =============================================================================
# 6b. CONFIGURE GIT MERGE STRATEGY (append-only ledger)
# =============================================================================
Write-Info "Ensuring .gitattributes union-merge for the append-only log..."
$gitAttrLine = "docs/second-brain/wiki/_LOG.md merge=union"
if ((Test-Path .gitattributes) -and (Select-String -Path .gitattributes -SimpleMatch -Pattern $gitAttrLine -Quiet)) {
    Write-Ok ".gitattributes already has the union-merge rule"
}
else {
    if (Test-Path .gitattributes) { Add-Content .gitattributes "" }
    Add-Content .gitattributes "# SumelaOS — append-only ledger: concurrent log appends combine instead of conflicting"
    Add-Content .gitattributes $gitAttrLine
    Write-Ok ".gitattributes union-merge rule added"
}

# =============================================================================
# 6c. CONFIGURE .gitignore (per-developer / runtime artifacts — never commit)
# =============================================================================
Write-Info "Ensuring .gitignore covers per-developer / runtime artifacts..."
$gitignoreMarker = "# SumelaOS — per-developer / runtime artifacts"
# Guard on the stable entry line (not the comment) so re-runs and the framework
# repo's own .gitignore are both detected and not duplicated.
if ((Test-Path .gitignore) -and (Select-String -Path .gitignore -Pattern '^\.sumela/local\.md$' -Quiet)) {
    Write-Ok ".gitignore already ignores per-developer artifacts"
}
else {
    if ((Test-Path .gitignore) -and ((Get-Item .gitignore).Length -gt 0)) { Add-Content .gitignore "" }
    Add-Content .gitignore "$gitignoreMarker (never commit)"
    Add-Content .gitignore ".sumela/local.md"
    Add-Content .gitignore ".sumela/.memory-sync.log"
    Add-Content .gitignore ".superpowers/"
    Add-Content .gitignore "**/scripts/.superpowers/"
    Add-Content .gitignore "graphify-out/"
    Add-Content .gitignore "qdrant-storage/"
    Write-Ok ".gitignore SumelaOS block added"
}

# Secret-file baseline — never commit credentials. Idempotent via its own marker
# (not a single content line) so all patterns land even when the project already
# ignored `.env`. The pre-commit hook adds a gitleaks scan on top if it's installed.
$secretMarker = "# SumelaOS — common secret files"
if ((Test-Path .gitignore) -and (Select-String -Path .gitignore -SimpleMatch -Pattern $secretMarker -Quiet)) {
    Write-Ok ".gitignore already covers secret files"
} else {
    if ((Test-Path .gitignore) -and ((Get-Item .gitignore).Length -gt 0)) { Add-Content .gitignore "" }
    Add-Content .gitignore "$secretMarker (never commit; see .sumela/rules/security_protocol.md)"
    Add-Content .gitignore ".env"
    Add-Content .gitignore ".env.*"
    Add-Content .gitignore "!.env.example"
    Add-Content .gitignore "!.env.*.example"
    Add-Content .gitignore "*.pem"
    Add-Content .gitignore "*.key"
    Add-Content .gitignore "*.p12"
    Add-Content .gitignore "*.pfx"
    Add-Content .gitignore "*.secret"
    Add-Content .gitignore "secrets.json"
    Write-Ok ".gitignore secret-file baseline added"
}

# =============================================================================
# 7. REGISTER MEMORY PLUGINS
# =============================================================================
if ($PluginArray.Count -gt 0) {
    Write-Info "Registering memory plugins in SKILL_REGISTRY.md..."

    # Read the registry once so we can guard against re-registering (idempotent:
    # the shipped registry may already list a plugin, and a re-run must not append
    # a duplicate <skill> block — parity with setup.sh's grep guard).
    $registryText = if (Test-Path ".sumela/SKILL_REGISTRY.md") { Get-Content ".sumela/SKILL_REGISTRY.md" -Raw } else { "" }
    $PluginEntries = ""
    foreach ($plugin in $PluginArray) {
        $plugin = $plugin.Trim()
        $skillPath = ".sumela/memory-plugins/$plugin/SKILL.md"
        if (-not (Test-Path $skillPath)) {
            Write-Warn "Plugin SKILL.md not found: $skillPath"
        }
        elseif ($registryText -match "<name>$([regex]::Escape($plugin))</name>") {
            Write-Info "Plugin already registered: $plugin — skipping"
        }
        else {
            $PluginEntries += @"

<skill activation="lazy">
<name>$plugin</name>
<description>Memory plugin — see ``.sumela/memory-plugins/$plugin/SKILL.md`` for routing and prerequisites.</description>
<path>.sumela/memory-plugins/$plugin/SKILL.md</path>
</skill>
"@
            Write-Ok "Registered plugin: $plugin"
        }
    }

    if ($PluginEntries) {
        $content = Get-Content ".sumela/SKILL_REGISTRY.md" -Raw
        $content = $content -replace '(</available_skills>)', "$PluginEntries`n`$1"
        $content | Set-Content ".sumela/SKILL_REGISTRY.md" -NoNewline
        Write-Ok "Plugins appended to SKILL_REGISTRY.md"
    }
}

# =============================================================================
# 7c. INSTALL GIT HOOKS (core.hooksPath — pre-commit validation + memory sync)
# =============================================================================
# Wired whenever the project is a git repo: pre-commit validation is useful for
# everyone, and the memory hooks self-gate (no-op without Qdrant + summaries).
$HooksWired = $false

# Helpers for the multi-install (monorepo) dispatcher — core.hooksPath holds ONE path,
# so a second SumelaOS install in the same repo is handled by a root dispatcher that
# fans each git event out to every registered install (see .sumela/git-hooks/_dispatch.sh).
function Register-SumelaInstall($gitRoot, $installRel) {   # $installRel "" => repo root
    $reg = Join-Path $gitRoot ".sumela-hooks/installs"
    $entry = if ([string]::IsNullOrEmpty($installRel)) { "." } else { $installRel }
    if (-not (Test-Path $reg)) { New-Item -ItemType File -Path $reg -Force | Out-Null }
    # Whole-line match (parity with bash `grep -qxF`): a substring match would wrongly
    # skip "packages/app" when "packages/app-extra" is already listed.
    if (-not (@(Get-Content $reg) -contains $entry)) { Add-Content $reg $entry }
}
function Setup-SumelaDispatch($gitRoot, $installAbs) {     # copy _dispatch.sh as the 3 hooks
    $dh = Join-Path $gitRoot ".sumela-hooks"
    New-Item -ItemType Directory -Path $dh -Force | Out-Null
    foreach ($hk in @("pre-commit", "post-merge", "post-checkout")) {
        Copy-Item (Join-Path $installAbs ".sumela/git-hooks/_dispatch.sh") (Join-Path $dh $hk) -Force
    }
}

if (Test-Path ".sumela/git-hooks") {
    Write-Info "Wiring git hooks (pre-commit validation + memory sync)..."
    $isGitRepo = $false
    try { $null = & git rev-parse --is-inside-work-tree 2>$null; if ($LASTEXITCODE -eq 0) { $isGitRepo = $true } } catch { $isGitRepo = $false }
    if ($isGitRepo) {
        $gitRoot = (& git rev-parse --show-toplevel 2>$null | Out-String).Trim()
        $installAbs = (Get-Location).Path
        # --show-prefix gives cwd relative to the repo root ("packages/app/" or "" at root).
        $installRel = (& git rev-parse --show-prefix 2>$null | Out-String).Trim().TrimEnd('/')
        $hooksRel = if ($installRel) { "$installRel/.sumela/git-hooks" } else { ".sumela/git-hooks" }
        # .Trim() because `& git` keeps the trailing newline that bash $(...) strips.
        $existingHooksPath = (& git config --local --get core.hooksPath 2>$null | Out-String).Trim()

        if ((-not $existingHooksPath) -or ($existingHooksPath -eq $hooksRel)) {
            & git config core.hooksPath $hooksRel
            $HooksWired = $true
            Write-Ok "Git hooks enabled (core.hooksPath = $hooksRel) — pre-commit validation active (bypass: git commit --no-verify)"
        }
        elseif ($existingHooksPath -eq ".sumela-hooks" -or $existingHooksPath -like "*/.sumela-hooks") {
            Setup-SumelaDispatch $gitRoot $installAbs   # refresh dispatcher scripts
            Register-SumelaInstall $gitRoot $installRel
            $HooksWired = $true
            Write-Ok "Registered this install with the existing SumelaOS hook dispatcher (.sumela-hooks/)."
        }
        elseif ($existingHooksPath -like "*.sumela/git-hooks") {
            # Another SumelaOS install owns core.hooksPath → promote to a dispatcher running BOTH.
            $otherRel = $existingHooksPath -replace '/?\.sumela/git-hooks$', ''
            Setup-SumelaDispatch $gitRoot $installAbs
            Register-SumelaInstall $gitRoot $otherRel
            Register-SumelaInstall $gitRoot $installRel
            & git config core.hooksPath ".sumela-hooks"
            $HooksWired = $true
            Write-Ok "Multiple SumelaOS installs detected — installed a hook dispatcher at .sumela-hooks/ that runs all of them."
            Write-Info "Commit .sumela-hooks/ so teammates share the dispatcher (each runs setup once to wire core.hooksPath)."
        }
        else {
            Write-Warn "core.hooksPath already set to '$existingHooksPath' (non-SumelaOS) — not overriding."
            Write-Warn "To enable SumelaOS hooks, merge .sumela/git-hooks/{pre-commit,post-merge,post-checkout} into '$existingHooksPath', or unset it and re-run setup."
        }
    }
    else {
        Write-Warn "Not a git repository — skipping git hook setup."
        Write-Warn "After 'git init', run setup again (it wires core.hooksPath automatically)."
    }
}

# =============================================================================
# 7d. GOVERNANCE — CODEOWNERS for the agent-control surface (team mode only)
# =============================================================================
if ($Governance -eq "team") {
    Write-Info "Ensuring CODEOWNERS covers the agent-control surface (team mode)..."
    $codeownersFile = ".github/CODEOWNERS"
    $codeownersMarker = "# SumelaOS agent-control surface"
    if ((Test-Path $codeownersFile) -and (Select-String -Path $codeownersFile -SimpleMatch -Pattern $codeownersMarker -Quiet)) {
        Write-Ok "CODEOWNERS already covers the agent-control surface"
    }
    else {
        if (-not (Test-Path ".github")) { New-Item -ItemType Directory -Path ".github" -Force | Out-Null }
        if ((Test-Path $codeownersFile) -and ((Get-Item $codeownersFile).Length -gt 0)) { Add-Content $codeownersFile "" }
        Add-Content $codeownersFile "$codeownersMarker — changes here alter every developer's agent."
        Add-Content $codeownersFile "# Replace @OWNER with your team/maintainer handle (e.g. @org/maintainers)."
        Add-Content $codeownersFile "/.sumela/rules/                     @OWNER"
        Add-Content $codeownersFile "/.sumela/skills/                    @OWNER"
        Add-Content $codeownersFile "/.sumela/sumela-prompt.md           @OWNER"
        Add-Content $codeownersFile "/.sumela/RULE_REGISTRY.md           @OWNER"
        Add-Content $codeownersFile "/.sumela/SKILL_REGISTRY.md          @OWNER"
        Add-Content $codeownersFile "/.sumela/git-hooks/                 @OWNER"
        Add-Content $codeownersFile "/docs/second-brain/wiki/_SCHEMA.md  @OWNER"
        Write-Ok "CODEOWNERS updated ($codeownersFile) — replace @OWNER with your handle"
    }
}

# =============================================================================
# 7e. CI WORKFLOW — run validate-structure on push/PR (opt-in: -Ci / prompt)
# =============================================================================
if ($WithCi) {
    $ciFile = ".github/workflows/sumela-validate.yml"
    if (Test-Path $ciFile) {
        Write-Ok "CI workflow already present ($ciFile)"
    }
    else {
        Write-Info "Adding CI validation workflow ($ciFile)..."
        if (-not (Test-Path ".github/workflows")) { New-Item -ItemType Directory -Path ".github/workflows" -Force | Out-Null }
        $ciContent = @'
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
'@
        Set-Content -Path $ciFile -Value $ciContent
        Write-Ok "CI workflow added — GitHub Actions; delete it if you use other CI (GitLab/Azure: see ADOPTION_GUIDE)"
    }
}

# =============================================================================
# 7f. SYNC ORG-SHARED RULES (monorepo — no-op unless .sumela-shared/rules/ exists)
# =============================================================================
$syncShared = "scripts/sync-shared-rules.py"
if ((Test-Path $syncShared) -and (Get-Command python3 -ErrorAction SilentlyContinue)) {
    $shrOut = & python3 $syncShared --check 2>&1 | Out-String
    if ($shrOut -notmatch 'no \.sumela-shared/rules') {
        Write-Info "Syncing org-shared rules from .sumela-shared/rules/ ..."
        & python3 $syncShared | ForEach-Object { Write-Host "  $_" }
        Write-Ok "Org-shared rules synced + registered (universal)."
    }
}

# =============================================================================
# 8. RUN VALIDATION
# =============================================================================
Write-Host ""
Write-Info "Running structure validation..."
Write-Host ""

# Check if bash is available (Git Bash, WSL, etc.)
$bashAvailable = $false
try {
    $null = Get-Command bash -ErrorAction Stop
    $bashAvailable = $true
} catch {
    $bashAvailable = $false
}

if ($bashAvailable) {
    & bash scripts/validate-structure.sh --check-placeholders
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Ok "Validation passed"
    }
    else {
        Write-Host ""
        Write-Warn "Validation had failures — review output above"
    }
}
else {
    Write-Warn "bash not available — skipping validation. Run manually: bash scripts/validate-structure.sh --check-placeholders"
}

# =============================================================================
# 9. SUMMARY
# =============================================================================
Write-Host ""
Write-Host "=== Setup Complete ===" -ForegroundColor White
Write-Host ""
Write-Host "  Project:    $ProjectName"
Write-Host "  Purpose:    $ProjectPurpose"
Write-Host "  Governance: $Governance"
Write-Host "  Stacks:     $(if ($StackArray.Count) { $StackArray -join ', ' } else { 'none' })"
Write-Host "  Rule variant: $RuleVariant"
Write-Host "  Plugins:    $(if ($PluginArray.Count) { $PluginArray -join ', ' } else { 'none' })"
Write-Host "  IDEs:       $(if ($IDEArray.Count) { $IDEArray -join ', ' } else { 'none' })"
Write-Host ""
Write-Host "  Files generated:"
Write-Host "    - AGENTS.md"
Write-Host "    - .sumela/RULE_REGISTRY.md"
Write-Host "    - .sumela/rules/ (stack-specific rules)"
Write-Host "    - docs/second-brain/wiki/ (6 wiki pages)"
if ($IDEArray.Count) { Write-Host "    - IDE pointer files" }
if ($PluginArray.Count) { Write-Host "    - SKILL_REGISTRY.md (plugins appended)" }
if ($HooksWired) { Write-Host "    - git hooks wired (core.hooksPath = .sumela/git-hooks; pre-commit validation)" }
if ($Governance -eq "team") { Write-Host "    - .github/CODEOWNERS (agent-control surface — replace @OWNER)" }
if ($WithCi) { Write-Host "    - .github/workflows/sumela-validate.yml (CI structure check)" }
Write-Host ""
Write-Host "  Next steps:"
Write-Host "    1. Edit AGENTS.md — fill in project-specific commands and conventions"
Write-Host "    2. Edit .sumela/rules/*.md — customize stack standards"
Write-Host "    3. Edit docs/second-brain/wiki/active-project-context.md — add current sprint"
Write-Host "    4. Review .sumela/RULE_REGISTRY.md — adjust stack scopes if needed"
if ($PluginArray.Count) { Write-Host "    5. Install plugin dependencies: pip install -r .sumela/memory-plugins/*/requirements.txt" }
Write-Host ""
