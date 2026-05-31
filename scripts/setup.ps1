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
    Language for code/technical output (default: English).

.PARAMETER Stacks
    Comma-separated list of tech stacks: backend, frontend, mobile, ai, infra.

.PARAMETER RuleVariant
    Rule template variant: empty or best-practice (default: best-practice).

.PARAMETER Plugins
    Comma-separated list of plugins: qdrant-session-memory, graphify-code-graph.

.PARAMETER IDEs
    Comma-separated list of IDEs: claude, cursor, cline, kilo-code, trae.

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
    [string]$Stacks = "",
    [string]$RuleVariant = "best-practice",
    [string]$Plugins = "",
    [string]$IDEs = ""
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
    "docs/second-brain/template/wiki/_INDEX.md.template",
    "docs/second-brain/template/wiki/_LOG.md.template",
    "docs/second-brain/template/wiki/_SEARCH_INDEX.md.template",
    "docs/second-brain/template/wiki/_IMPROVEMENT_QUEUE.md.template",
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
    $InteractionLanguage = Read-WithDefault "Interaction language (for chat/explanations)" "English"
    $CodeLanguage = Read-WithDefault "Code language (for comments/commits)" "English"

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
    $IDEArray = Read-MultiSelect "IDEs to generate pointer files for:" @("claude", "cursor", "cline", "kilo-code", "trae")
}

$DateCreated = Get-Date -Format "yyyy-MM-dd"

Write-Info "Project: $ProjectName"
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
$content = $content -replace '\{\{code_language\}\}', $CodeLanguage
$content = $content -replace '\{\{backend_commands\}\}', $BackendCmds
$content = $content -replace '\{\{frontend_commands\}\}', $FrontendCmds
$content = $content -replace '\{\{mobile_commands\}\}', $MobileCmds
$content = $content -replace '\{\{infrastructure_commands\}\}', $InfraCmds
$content = $content -replace '\{\{dependency_flow\}\}', $DepFlow
$content = $content -replace '\{\{package_boundaries\}\}', $PkgBoundariesStr
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
    @{ Src = "_IMPROVEMENT_QUEUE.md.template"; Dst = "_IMPROVEMENT_QUEUE.md" }
    @{ Src = "_SCHEMA.md"; Dst = "_SCHEMA.md" }
    @{ Src = "active-project-context.md.template"; Dst = "active-project-context.md" }
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
# 7. REGISTER MEMORY PLUGINS
# =============================================================================
if ($PluginArray.Count -gt 0) {
    Write-Info "Registering memory plugins in SKILL_REGISTRY.md..."

    $PluginEntries = ""
    foreach ($plugin in $PluginArray) {
        $plugin = $plugin.Trim()
        $skillPath = ".sumela/memory-plugins/$plugin/SKILL.md"
        if (Test-Path $skillPath) {
            $PluginEntries += @"

<skill activation="lazy">
<name>$plugin</name>
<description>Memory plugin — see ``.sumela/memory-plugins/$plugin/SKILL.md`` for routing and prerequisites.</description>
<path>.sumela/memory-plugins/$plugin/SKILL.md</path>
</skill>
"@
            Write-Ok "Registered plugin: $plugin"
        }
        else {
            Write-Warn "Plugin SKILL.md not found: $skillPath"
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
Write-Host ""
Write-Host "  Next steps:"
Write-Host "    1. Edit AGENTS.md — fill in project-specific commands and conventions"
Write-Host "    2. Edit .sumela/rules/*.md — customize stack standards"
Write-Host "    3. Edit docs/second-brain/wiki/active-project-context.md — add current sprint"
Write-Host "    4. Review .sumela/RULE_REGISTRY.md — adjust stack scopes if needed"
if ($PluginArray.Count) { Write-Host "    5. Install plugin dependencies: pip install -r .sumela/memory-plugins/*/requirements.txt" }
Write-Host ""
