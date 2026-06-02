<#
.SYNOPSIS
    Refresh the SumelaOS framework CORE in an adopting project, without touching the
    project's OVERLAY. PowerShell parity of scripts/update.sh.

.DESCRIPTION
    CORE (refreshed, with per-file diff + consent when locally changed):
      .sumela/sumela-prompt.md, .sumela/skills/, .sumela/git-hooks/,
      universal rules (engineering_philosophy, identity_and_behavior,
      architecture_patterns, audit_and_output, security_protocol,
      git_workflow_mandatory_review_protocol, self_improvement_protocol),
      docs/second-brain/template/, .sumela/memory-plugins/<installed-plugin>/, scripts/*
    OVERLAY (never touched): AGENTS.md, RULE_REGISTRY.md, SKILL_REGISTRY.md, stack rules,
      docs/second-brain/wiki/* (except the live _SCHEMA.md, refreshed as a derived pair
      with diff + consent), .sumela/local.md,
      .gitignore, .gitattributes, IDE pointers, CODEOWNERS, CI workflow.

.PARAMETER SourceDir   Use a local framework checkout instead of cloning.
.PARAMETER RepoUrl     Repo to clone when SourceDir is not given.
.PARAMETER DryRun      Show what would change; change nothing.
.PARAMETER Yes         Apply all changed core files without prompting.
.PARAMETER Force       Run even if versions match.
#>
param(
    [string]$SourceDir = "",
    [string]$RepoUrl = "https://github.com/tolgakisaogullari/SumelaOS.git",
    [switch]$DryRun,
    [switch]$Yes,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
function Write-Info($m) { Write-Host "[INFO] $m" -ForegroundColor Cyan }
function Write-Ok($m)   { Write-Host "[OK] $m" -ForegroundColor Green }
function Write-Warn($m) { Write-Host "[WARN] $m" -ForegroundColor Yellow }
function Write-Err($m)  { Write-Host "[ERROR] $m" -ForegroundColor Red }

# Anchor to the nearest ancestor that contains .sumela/ (NOT git toplevel — so a
# monorepo subdir adoption updates the right install).
$root = (Get-Location).Path
while ((-not (Test-Path (Join-Path $root ".sumela"))) -and ($root -ne (Split-Path $root -Parent)) -and $root) {
    $root = Split-Path $root -Parent
}
if (-not (Test-Path (Join-Path $root ".sumela"))) {
    Write-Err "No .sumela/ found from $(Get-Location) upward — run update.ps1 inside a SumelaOS project."
    exit 1
}
Set-Location $root

# --- Acquire the framework source ---
$cloneTmp = ""
try {
    if ($SourceDir) {
        $src = $SourceDir
        if (-not (Test-Path (Join-Path $src ".sumela"))) { Write-Err "--SourceDir '$src' is not a SumelaOS checkout"; exit 1 }
    }
    else {
        $cloneTmp = Join-Path ([System.IO.Path]::GetTempPath()) ("sumela-" + [System.Guid]::NewGuid().ToString())
        Write-Info "Cloning $RepoUrl ..."
        & git clone --depth 1 $RepoUrl $cloneTmp 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Err "clone failed"; exit 1 }
        $src = $cloneTmp
    }

    function Read-Ver($base) {
        $p = Join-Path $base ".sumela/VERSION"
        if (Test-Path $p) { return ((Get-Content $p -Raw).Trim()) } else { return "unknown" }
    }
    $srcVer = Read-Ver $src
    $localVer = Read-Ver $root
    Write-Info "Local core version: $localVer    Upstream: $srcVer"
    if (($srcVer -eq $localVer) -and (-not $Force)) {
        Write-Ok "Already on core version $localVer. (Use -Force to re-check files anyway.)"
        exit 0
    }

    $coreFiles = @(
        ".sumela/sumela-prompt.md",
        ".sumela/rules/engineering_philosophy.md",
        ".sumela/rules/identity_and_behavior.md",
        ".sumela/rules/architecture_patterns.md",
        ".sumela/rules/audit_and_output.md",
        ".sumela/rules/security_protocol.md",
        ".sumela/rules/git_workflow_mandatory_review_protocol.md",
        ".sumela/rules/self_improvement_protocol.md"
    )
    $coreDirs = @(".sumela/skills", ".sumela/git-hooks", ".sumela/memory-plugins", "docs/second-brain/template", "scripts")
    $selfDefer = @("scripts/update.sh", "scripts/update.ps1")

    # Flatten core dirs from the SOURCE into relative paths.
    $candidates = New-Object System.Collections.Generic.List[string]
    foreach ($f in $coreFiles) { if (Test-Path (Join-Path $src $f)) { $candidates.Add($f) } }
    foreach ($d in $coreDirs) {
        $abs = Join-Path $src $d
        if (Test-Path $abs) {
            $prefix = ((Resolve-Path $src).Path.TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar)
            Get-ChildItem -Path $abs -Recurse -File | ForEach-Object {
                $candidates.Add($_.FullName.Substring($prefix.Length).Replace('\','/'))
            }
        }
    }

    function Same-File($a, $b) { (Get-FileHash $a).Hash -eq (Get-FileHash $b).Hash }
    function Plugin-Absent($rel) {
        # Only gate files UNDER a plugin dir (two+ nested segments); top-level files
        # like memory-plugins/README.md are not plugin-gated.
        if ($rel -like ".sumela/memory-plugins/*/*") {
            $rest = $rel.Substring(".sumela/memory-plugins/".Length)
            $plugin = $rest.Split('/')[0]
            return (-not (Test-Path (Join-Path $root ".sumela/memory-plugins/$plugin")))
        }
        return $false
    }

    $newList = New-Object System.Collections.Generic.List[string]
    $changedList = New-Object System.Collections.Generic.List[string]
    $deferredList = New-Object System.Collections.Generic.List[string]
    foreach ($f in $candidates) {
        if (Plugin-Absent $f) { continue }
        $localPath = Join-Path $root $f
        $srcPath = Join-Path $src $f
        if (-not (Test-Path $localPath)) { $newList.Add($f) }
        elseif (Same-File $srcPath $localPath) { }
        elseif ($selfDefer -contains $f) { $deferredList.Add($f) }
        else { $changedList.Add($f) }
    }

    # Derived file: the LIVE wiki/_SCHEMA.md is generated from the template at setup
    # (framework-authored schema in the overlay zone) — refresh it here too, with consent.
    $schemaLive = "docs/second-brain/wiki/_SCHEMA.md"
    $schemaSrc = "docs/second-brain/template/wiki/_SCHEMA.md"
    $schemaChanged = $false
    $schemaLivePath = Join-Path $root $schemaLive
    $schemaSrcPath = Join-Path $src $schemaSrc
    if ((Test-Path $schemaLivePath) -and (Test-Path $schemaSrcPath) -and (-not (Same-File $schemaSrcPath $schemaLivePath))) {
        $schemaChanged = $true
    }

    Write-Host ""
    Write-Host "=== SumelaOS core update: $localVer -> $srcVer ===" -ForegroundColor White
    Write-Host "  New core files:      $($newList.Count)"
    Write-Host "  Changed core files:  $($changedList.Count)"
    if ($schemaChanged) { Write-Host "  Derived (live _SCHEMA): 1 (from refreshed template)" }
    if ($deferredList.Count -gt 0) { Write-Host "  Updater self-changed: $($deferredList.Count) (re-run after this; not auto-applied)" }
    Write-Host "  Overlay (AGENTS.md, registries, stack rules, wiki, governance/CI): left untouched"

    if (($newList.Count -eq 0) -and ($changedList.Count -eq 0) -and (-not $schemaChanged)) {
        Write-Ok "No core file changes to apply."
        if (-not $DryRun) { Set-Content -Path (Join-Path $root ".sumela/VERSION") -Value $srcVer }
        exit 0
    }
    if ($DryRun) {
        Write-Host ""; Write-Info "--DryRun: the following would change (nothing written):"
        foreach ($f in $newList) { Write-Host "  + $f (new)" }
        foreach ($f in $changedList) { Write-Host "  ~ $f (changed)" }
        if ($schemaChanged) { Write-Host "  ~ $schemaLive (changed; derived from template)" }
        exit 0
    }

    function Apply-File($rel) {
        $dest = Join-Path $root $rel
        New-Item -ItemType Directory -Path (Split-Path $dest -Parent) -Force | Out-Null
        Copy-Item -Path (Join-Path $src $rel) -Destination $dest -Force
    }

    foreach ($f in $newList) { Apply-File $f; Write-Ok "added  $f" }

    $nSkipped = 0
    if ($changedList.Count -gt 0) {
        $mode = "a"
        if (-not $Yes) {
            Write-Host ""
            Write-Host "$($changedList.Count) core file(s) differ from upstream. [a]pply all / [r]eview each / [s]kip all:"
            $ans = Read-Host
            if ($ans) { $mode = $ans }
        }
        foreach ($f in $changedList) {
            switch -Regex ($mode) {
                '^[sS]' { Write-Host "  skip   $f"; $nSkipped++ }
                '^[rR]' {
                    Write-Host ""; Write-Host "--- $f ---" -ForegroundColor White
                    & git --no-pager diff --no-index (Join-Path $root $f) (Join-Path $src $f) 2>$null
                    $yn = Read-Host "Update this file? [y/N]"
                    if ($yn -match '^[yY]') { Apply-File $f; Write-Ok "updated $f" } else { Write-Host "  skip   $f"; $nSkipped++ }
                }
                default { Apply-File $f; Write-Ok "updated $f" }
            }
        }
    }

    # Derived live _SCHEMA.md (sourced from the refreshed template) — diff + consent.
    if ($schemaChanged) {
        $doSchema = $true
        if (-not $Yes) {
            Write-Host ""; Write-Host "--- $schemaLive (derived from template) ---" -ForegroundColor White
            & git --no-pager diff --no-index $schemaLivePath $schemaSrcPath 2>$null
            $yn = Read-Host "Update your live _SCHEMA from the refreshed template? [Y/n]"
            if ($yn -match '^[nN]') { $doSchema = $false }
        }
        if ($doSchema) {
            New-Item -ItemType Directory -Path (Split-Path $schemaLivePath -Parent) -Force | Out-Null
            Copy-Item -Path $schemaSrcPath -Destination $schemaLivePath -Force
            Write-Ok "updated $schemaLive (from template)"
        } else { Write-Host "  skip   $schemaLive"; $nSkipped++ }
    }

    # Skill registry: auto-register newly-added on-disk skills (with consent);
    # orphans reported, not deleted. Rules are NOT auto-reconciled.
    $reconcile = Join-Path $root "scripts/reconcile-registry.py"
    if ((Test-Path $reconcile) -and (Get-Command python3 -ErrorAction SilentlyContinue)) {
        $regOut = & python3 $reconcile --check 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host ""; $regOut | ForEach-Object { Write-Host "  $_" }
            $doReg = $true
            if (-not $Yes) {
                $yn = Read-Host "Reconcile SKILL_REGISTRY.md now (register new skills; orphans only reported)? [Y/n]"
                if ($yn -match '^[nN]') { $doReg = $false }
            }
            if ($doReg) { & python3 $reconcile | ForEach-Object { Write-Host "  $_" } }
        }
    }

    Set-Content -Path (Join-Path $root ".sumela/VERSION") -Value $srcVer

    Write-Host ""
    $validator = Join-Path $root "scripts/validate-structure.sh"
    if ((Test-Path $validator) -and (Get-Command bash -ErrorAction SilentlyContinue)) {
        Write-Info "Validating structure..."
        & bash $validator
    }
    Write-Host ""
    Write-Ok "Core updated to $srcVer."
    if ($nSkipped -gt 0) { Write-Warn "$nSkipped changed core file(s) were SKIPPED and still differ from upstream $srcVer. Re-run with -Force to revisit them." }
    Write-Warn "Overlay was untouched. Skills were auto-reconciled into SKILL_REGISTRY.md; if RULES"
    Write-Warn "changed, reconcile RULE_REGISTRY.md via /initSumela's registry step or /evolve (rules need phase/stack metadata)."
    if ($deferredList.Count -gt 0) { Write-Warn "The updater itself changed upstream — re-run scripts/update.ps1 to pick up the new version." }
    Write-Host "Review changes with 'git diff' before committing."
}
finally {
    if ($cloneTmp -and (Test-Path $cloneTmp)) { Remove-Item -Recurse -Force $cloneTmp }
}
