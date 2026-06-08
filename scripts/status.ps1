<#
.SYNOPSIS
    SumelaOS health report (read-only) — PowerShell parity of scripts/status.sh.
    Answers "is my SumelaOS install healthy, and what needs attention?" without
    modifying anything. Every finding routes to the automated fixer that resolves
    it (update, setup, or /evolve): one diagnosis, then one fixer, no hand-editing.
.NOTES
    Exit 0 = all healthy, 1 = one or more items need attention.
#>

$root = (Get-Location).Path
while ((-not (Test-Path (Join-Path $root ".sumela"))) -and ($root -ne (Split-Path $root -Parent)) -and $root) {
    $root = Split-Path $root -Parent
}
if (-not (Test-Path (Join-Path $root ".sumela"))) { Write-Host "status: no .sumela/ found from here upward."; exit 0 }
Set-Location $root

$scriptsDir = Join-Path $root "scripts"
$wikiPath = if ($env:WIKI_PATH) { $env:WIKI_PATH } else { "docs/second-brain/wiki" }
$havePy3 = [bool](Get-Command python3 -ErrorAction SilentlyContinue)
$haveBash = [bool](Get-Command bash -ErrorAction SilentlyContinue)

$script:attention = 0
function Ok($m)        { Write-Host "  ok        $m" -ForegroundColor Green }
function Info($m)      { Write-Host "  info      $m" -ForegroundColor Cyan }
function Attn($m)      { Write-Host "  attention $m" -ForegroundColor Yellow; $script:attention++ }
function Section($m)   { Write-Host ""; Write-Host $m -ForegroundColor White }

Write-Host "SumelaOS status  ($root)"

# --- 1. Version + governance ------------------------------------------------
Section "Framework"
$verPath = Join-Path $root ".sumela/VERSION"
if (Test-Path $verPath) {
    $ver = (Get-Content $verPath | Select-Object -First 1).Trim()
    Info "version $ver  (check for upgrades: pwsh scripts/update.ps1)"
} else {
    Attn ".sumela/VERSION missing — reinstall the core (setup) or run update.ps1"
}
$agents = Join-Path $root "AGENTS.md"
if (Test-Path $agents) {
    $gm = Select-String -Path $agents -Pattern '^\s*governance:\s*(solo|team)' -AllMatches | Select-Object -First 1
    if ($gm) { Info ("governance: " + $gm.Matches[0].Groups[1].Value + "  (AGENTS.md " + [char]0xA7 + "8)") }
    else { Info "governance mode not declared in AGENTS.md" }
}

# --- 2. Structure -----------------------------------------------------------
Section "Structure"
$validator = Join-Path $scriptsDir "validate-structure.sh"
if ((Test-Path $validator) -and $haveBash) {
    $out = & bash $validator 2>&1
    $rc = $LASTEXITCODE
    $summary = ($out | Select-String -Pattern 'All .* checks passed|check.* failed|FAIL' | Select-Object -Last 1)
    if ($rc -eq 0) { Ok ($(if ($summary) { $summary.Line.Trim() } else { "structure valid" })) }
    else { Attn (($(if ($summary) { $summary.Line.Trim() } else { "structure invalid" })) + " — see: bash scripts/validate-structure.sh  (fix: update)") }
} else {
    Info "validate-structure.sh / bash unavailable — skipped"
}

# --- 3. Skill registry drift ------------------------------------------------
Section "Skill registry"
$reconcile = Join-Path $scriptsDir "reconcile-registry.py"
if ((Test-Path $reconcile) -and $havePy3) {
    $regOut = & python3 $reconcile --check 2>&1
    if ($LASTEXITCODE -eq 0) {
        Ok "SKILL_REGISTRY.md in sync with skills on disk"
    } else {
        $regOut | Select-String -Pattern 'unregistered|ORPHAN' | ForEach-Object { Write-Host "  $($_.Line.Trim())" }
        Attn "registry out of sync — fix: python3 scripts/reconcile-registry.py  (also run by update)"
    }
} else {
    Info "reconcile-registry.py / python3 unavailable — skipped"
}

# --- Shared rules (monorepo / org) ------------------------------------------
Section "Shared rules"
$shr = Join-Path $scriptsDir "sync-shared-rules.py"
if ((Test-Path $shr) -and $havePy3) {
    $shrOut = & python3 $shr --check 2>&1 | Out-String
    if ($shrOut -match 'no \.sumela-shared/rules') {
        Info "no org-shared rules configured (.sumela-shared/rules/ above this install)"
    } elseif ($LASTEXITCODE -eq 0) {
        Ok "in sync with .sumela-shared/rules/"
    } else {
        $shrOut -split "`n" | Select-String -Pattern 'out of date|not registered|ORPHAN' | ForEach-Object { Write-Host "  $($_.Line.Trim())" }
        Attn "org-shared rules drifted — fix: python3 scripts/sync-shared-rules.py"
    }
} else {
    Info "sync-shared-rules.py / python3 unavailable — skipped"
}

# --- 4. IDE mirror drift ----------------------------------------------------
Section "IDE mirrors"
$conf = Join-Path $root ".sumela/mirrors.conf"
$syncPs = Join-Path $scriptsDir "sync-mirrors.ps1"
if ((Test-Path $conf) -and (Test-Path $syncPs)) {
    & $syncPs -Check *> $null
    if ($LASTEXITCODE -eq 0) { Ok "all configured mirrors match .sumela/sumela-prompt.md" }
    else { Attn "a mirror has drifted — fix: pwsh scripts/sync-mirrors.ps1  (also enforced by pre-commit)" }
} else {
    Info "no .sumela/mirrors.conf — no IDE mirrors configured"
}

# --- 5. Improvement queue ---------------------------------------------------
Section "Improvement queue"
$qdir = Join-Path $root "$wikiPath/_improvement-queue"
if (Test-Path $qdir) {
    $pending = @(Get-ChildItem -Path $qdir -Filter 'IMP-*.md' -File -ErrorAction SilentlyContinue).Count
    if ($pending -gt 0) { Attn "$pending pending signal(s) — review with /evolve" }
    else { Ok "no pending signals" }
} else {
    Info "no _improvement-queue/ under $wikiPath — second-brain not initialized here"
}

# --- 6. Git hooks -----------------------------------------------------------
Section "Git hooks"
$isGit = $false
if (Get-Command git -ErrorAction SilentlyContinue) {
    git -C $root rev-parse --git-dir *> $null; if ($LASTEXITCODE -eq 0) { $isGit = $true }
}
if ($isGit) {
    # Recognize ALL three wiring forms setup produces (root / subdir / dispatcher),
    # not just the root one — else a monorepo install is mis-flagged as "not wired"
    # and the old fix would break it. The one correct fixer is rerunning setup.
    $hp = (git -C $root config --get core.hooksPath 2>$null)
    $gitRoot = (git -C $root rev-parse --show-toplevel 2>$null)
    $instRel = (git -C $root rev-parse --show-prefix 2>$null)
    if ($instRel) { $instRel = $instRel.TrimEnd('/') }
    $expected = if ($instRel) { "$instRel/.sumela/git-hooks" } else { ".sumela/git-hooks" }
    $regEntry = if ($instRel) { $instRel } else { "." }
    $hpLeaf = if ($hp) { ($hp -split '/')[-1] } else { "" }
    if (-not (Test-Path (Join-Path $root ".sumela/git-hooks"))) {
        Info "no .sumela/git-hooks present — skipped"
    } elseif ($hp -eq $expected) {
        Ok "core.hooksPath = $hp (validation + memory-sync active)"
    } elseif ($hpLeaf -eq ".sumela-hooks") {
        $installsFile = Join-Path $gitRoot ".sumela-hooks/installs"
        if ((Test-Path $installsFile) -and ((Get-Content $installsFile) -contains $regEntry)) {
            Ok "core.hooksPath = $hp (multi-install dispatcher; this install registered)"
        } else {
            Attn "dispatcher active but this install isn't registered — fix: pwsh scripts/setup.ps1 -HooksOnly (or run /onboardSumela)"
        }
    } elseif ($hp) {
        Attn "core.hooksPath = '$hp' (not this install) — fix: pwsh scripts/setup.ps1 -HooksOnly (or run /onboardSumela)"
    } else {
        Attn "hooks not wired — fix: pwsh scripts/setup.ps1 -HooksOnly (or run /onboardSumela)"
    }
} else {
    Info "not a git repository — hooks skipped"
}

# --- 7. Secret scanning -----------------------------------------------------
Section "Secret scanning"
if (Get-Command gitleaks -ErrorAction SilentlyContinue) {
    Ok "gitleaks installed — pre-commit scans staged changes for secrets"
} else {
    Info "no secret scanner — install gitleaks to auto-scan commits (see .sumela/rules/security_protocol.md)"
}

# --- 8. Memory plugins ------------------------------------------------------
Section "Memory plugins"
$plugDir = Join-Path $root ".sumela/memory-plugins"
if (Test-Path $plugDir) {
    $names = @(Get-ChildItem -Path $plugDir -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
    if ($names.Count -gt 0) { Info ("installed: " + ($names -join " ")) }
    else { Info "no memory plugins installed (optional)" }
} else {
    Info "no memory-plugins directory (optional)"
}

# Extra documentation ingest dirs (project-configured; default none).
$resolver = Join-Path $plugDir "qdrant-session-memory/scripts/resolve-ingest-dirs.py"
$py = Get-Command python3 -ErrorAction SilentlyContinue
if ((Test-Path $resolver) -and $py) {
    Push-Location $root
    $extra = @(& $py.Source $resolver 2>$null | Where-Object { $_ -ne "" })
    Pop-Location
    if ($extra.Count -gt 0) { $extra | ForEach-Object { Ok "extra ingest dir: $_" } }
    else { Info "no extra ingest dirs configured (.sumela/ingest.conf — optional)" }
}

# --- Summary ----------------------------------------------------------------
Write-Host ""
if ($script:attention -eq 0) {
    Write-Host "Healthy. Nothing needs attention." -ForegroundColor Green
    exit 0
} else {
    Write-Host "$($script:attention) item(s) need attention — each line above lists the one command that fixes it." -ForegroundColor Yellow
    exit 1
}
