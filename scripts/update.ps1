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

# Single source for the upstream URL (fork-overridable, shared with the pull-time
# update check): honor .sumela/upstream.conf unless -SourceDir/-RepoUrl was given.
# NOTE: upstream.conf is NOT a CORE file, so once a fork sets it, updates never
# overwrite it — to re-sync to the original upstream, edit/delete it manually.
if ((-not $SourceDir) -and ($RepoUrl -eq "https://github.com/tolgakisaogullari/SumelaOS.git") -and (Test-Path (Join-Path $root ".sumela/upstream.conf"))) {
    $cfgUrl = (Get-Content (Join-Path $root ".sumela/upstream.conf") | Where-Object { $_ -notmatch '^\s*(#|$)' } | Select-Object -First 1)
    if ($cfgUrl) { $RepoUrl = $cfgUrl.Trim() }
}

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
        # Restrict transports so a poisoned .sumela/upstream.conf can't run code via
        # git's ext::/file:: transport (framework is only fetched over https/ssh/git).
        $env:GIT_ALLOW_PROTOCOL = "https:ssh:git"
        & git clone --depth 1 $RepoUrl $cloneTmp 2>$null | Out-Null
        $env:GIT_ALLOW_PROTOCOL = $null
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

    # --- Reconcile the SumelaOS-managed .gitignore patterns ------------------
    # Runs BEFORE the version gate, so even an already-current install backfills any
    # newly-shipped managed pattern. .gitignore is OVERLAY (never overwritten), so new
    # managed runtime-artifact patterns would otherwise reach only fresh installs, not
    # upgrades. Backfill any missing pattern from the single source
    # (scripts/lib/sumela-gitignore.list in the new $src). Idempotent; only ADDS absent
    # patterns; never touches the user's lines.
    $giListFile = Join-Path $src "scripts/lib/sumela-gitignore.list"
    if (Test-Path $giListFile) {
        $giPatterns = Get-Content $giListFile | Where-Object { $_ -notmatch '^\s*(#|$)' } | ForEach-Object { $_.Trim() }
        $giFile = Join-Path $root ".gitignore"
        $giExisting = if (Test-Path $giFile) { Get-Content $giFile } else { @() }
        $giMissing = @($giPatterns | Where-Object { $giExisting -cnotcontains $_ })
        if ($giMissing.Count -gt 0) {
            Write-Host ""
            Write-Info ".gitignore is missing $($giMissing.Count) SumelaOS runtime-artifact pattern(s):"
            foreach ($ln in $giMissing) { Write-Host "  + $ln" }
            if ($DryRun) {
                Write-Warn "--DryRun: would add the above to $giFile (nothing written)"
            }
            else {
                $doGi = $true
                if (-not $Yes) {
                    $ans = Read-Host "Add these to .gitignore? [Y/n]"
                    if ($ans -match '^(n|N)') { $doGi = $false; Write-Info "skipped .gitignore reconcile" }
                }
                if ($doGi) {
                    if ((Test-Path $giFile) -and ((Get-Item $giFile).Length -gt 0)) { Add-Content $giFile "" }
                    Add-Content $giFile "# SumelaOS — runtime artifacts (reconciled by update.ps1)"
                    foreach ($ln in $giMissing) { Add-Content $giFile $ln }
                    Write-Ok ".gitignore reconciled (+$($giMissing.Count))"
                }
            }
        }
    }

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
        ".sumela/rules/self_improvement_protocol.md",
        # NOT covered by $coreDirs: that entry is .sumela/rules/templates/, one
        # level BELOW this file. init-sumela copies it to a LIVE rule, so an edit
        # here only reaches an existing install if it is named explicitly.
        ".sumela/rules/operational_excellence_maintenance.md.template",
        # Same trap one directory up: .sumela/ itself is not a $coreDirs entry, so anything
        # at its ROOT reached fresh installs only. The RENDERED RULE_REGISTRY.md stays
        # OVERLAY and is still never overwritten; only this template is upstream-managed.
        ".sumela/RULE_REGISTRY.md.template"
    )
    $coreDirs = @(".sumela/skills", ".sumela/git-hooks", ".sumela/memory-plugins", ".sumela/rules/templates", "docs/second-brain/template", "scripts")
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
    if ($deferredList.Count -gt 0) { Write-Host "  Updater self-changed: $($deferredList.Count) (installed during this run; re-run with -Force to finish)" }
    Write-Host "  Overlay (AGENTS.md, registries, stack rules, wiki, governance/CI): left untouched"

    # See update.sh: an updater only knows the CORE list IT shipped with, so when
    # scripts/update.* change upstream this run may have skipped files that became CORE
    # after this copy was written. Install the new updater rather than asking for a manual copy.
    # Mirrors update.sh: the self-modification guard reads this to tell a vendored upgrade
    # from a hand-edited file. Without it every Windows upgrade is classified as authored.
    function Write-Provenance([string[]]$Paths, [string]$Version = $null, [bool]$PendingRerun = $false) {
        if (-not $Version) { $Version = $srcVer }
        if ($DryRun) { return }
        $rec = Join-Path $root ".sumela/.last-update.json"
        $all = @($Paths | Where-Object { $_ })
        if (Test-Path $rec) {
            try {
                # See update.sh: only a record left by the FIRST pass of a two-pass upgrade is
                # merged, and it says so itself via pending_rerun. Carrying every past record
                # forward would make a file vendored once satisfy the self-modification guard
                # forever, so a later hand-edit would be announced as a verified upgrade.
                $prev = Get-Content $rec -Raw | ConvertFrom-Json
                if ($prev.pending_rerun -eq $true) { $all += @($prev.files) }
            } catch { }
        }
        $all = @($all | Sort-Object -Unique)
        # Emit the JSON by hand. ConvertTo-Json UNWRAPS a single-element array, so a one-file
        # release would write  "files": "path"  where update.sh always writes a list — and the
        # guard that reads this expects a list on both platforms.
        $esc = { param($x) $x -replace '\\', '\\\\' -replace '"', '\"' }
        $items = ($all | ForEach-Object { '    "' + (& $esc $_) + '"' }) -join ",`n"
        $pending = if ($PendingRerun) { "true" } else { "false" }
        $json  = "{`n  `"version`": `"$Version`",`n" +
                 "  `"updated_at`": `"$((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))`",`n" +
                 "  `"pending_rerun`": $pending,`n" +
                 "  `"files`": [`n$items`n  ]`n}`n"
        try { Set-Content -Path $rec -Value $json -Encoding UTF8 -NoNewline } catch { }
    }

    function Install-Self {
        if ($deferredList.Count -eq 0 -or $DryRun) { return @() }
        # See update.sh: "[s]kip all" is a statement about vendored overwrites in general,
        # so silently replacing a fork's patched updater would contradict it.
        if ($script:applyMode -eq 's') { return @() }
        # ...and so is reviewing each file and declining all of them.
        if ($changedList.Count -gt 0 -and $script:appliedChanged.Count -eq 0) { return @() }
        $done = @()
        foreach ($selfFile in $selfDefer) {
            $selfSrc = Join-Path $src $selfFile
            if (-not (Test-Path $selfSrc)) { continue }
            $dest = Join-Path $root $selfFile
            # Only the ones that actually differ — otherwise an unchanged twin gets a .bak
            # and is recorded as vendored when nothing about it changed.
            if ((Test-Path $dest) -and (Same-File $selfSrc $dest)) { continue }
            $tmp  = "$dest.sumela-new"
            try {
                # Keep the outgoing copy: this is the one file the user cannot diff during the run.
                if (Test-Path $dest) { Copy-Item -Path $dest -Destination "$dest.bak" -Force -ErrorAction SilentlyContinue }
                # Stage then rename: never rewrite a script that may be executing, and only
                # report success when the file actually landed.
                Copy-Item -Path $selfSrc -Destination $tmp -Force -ErrorAction Stop
                Move-Item -Path $tmp -Destination $dest -Force -ErrorAction Stop
                $done += $selfFile
            } catch {
                Remove-Item -Path $tmp -Force -ErrorAction SilentlyContinue
                Write-Warn "Could not install $selfFile - re-run the updater after fixing: $($_.Exception.Message)"
            }
        }
        return $done
    }

    if (($newList.Count -eq 0) -and ($changedList.Count -eq 0) -and (-not $schemaChanged)) {
        Write-Ok "No core file changes to apply."
        if ($deferredList.Count -gt 0) {
            # Updater-only release. Exiting here with a "copy it yourself" note stranded the old
            # updater permanently. Install it — and deliberately do NOT stamp VERSION: "no core
            # changes" was computed from the OLD updater's CORE list, which is exactly what we
            # just replaced, so declaring the install current could lose a newly-CORE file.
            $installed = Install-Self
            if ($installed.Count -gt 0) {
                Write-Ok "Updater refreshed: $($installed -join ' ')"
                Write-Warn "Version NOT stamped: the new updater must re-check the file set it knows about."
                Write-Warn "  RE-RUN NOW to finish:  pwsh scripts/update.ps1"
                if (-not $DryRun) {
                    Remove-Item -Path (Join-Path $root ".sumela/.update-check") -Force -ErrorAction SilentlyContinue
                    Write-Provenance $installed -Version $localVer -PendingRerun $true
                }
                exit 0
            }
            elseif (-not $DryRun) {
                # The copy failed. Stamping VERSION below would declare the install current and
                # strand the old updater permanently, silently. See update.sh.
                Write-Warn "Could not install the new updater. Version NOT stamped — fix the cause and re-run."
                exit 1
            }
        }
        if (-not $DryRun) {
            # Re-stamp a record an earlier updater-only pass left at the OLD version:
            # advancing VERSION without it breaks record.version == VERSION.
            $carry = @()
            $recPath = Join-Path $root ".sumela/.last-update.json"
            if (Test-Path $recPath) {
                try {
                    $prevRec = Get-Content $recPath -Raw | ConvertFrom-Json
                    if ($prevRec.pending_rerun -eq $true) { $carry = @($prevRec.files) }
                } catch { }
            }
            Set-Content -Path (Join-Path $root ".sumela/VERSION") -Value $srcVer
            if ($carry.Count -gt 0) { Write-Provenance $carry -Version $srcVer }
            Remove-Item -Path (Join-Path $root ".sumela/.update-check") -Force -ErrorAction SilentlyContinue
        }
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
    # Only APPLIED files go into the provenance record: one that vouches for a file the user
    # declined would let a later hand-edit of it pass the self-modification guard as vendored.
    $script:appliedChanged = @()
    $script:applyMode = 'a'
    if ($changedList.Count -gt 0) {
        $mode = "a"
        if (-not $Yes) {
            Write-Host ""
            Write-Host "$($changedList.Count) core file(s) differ from upstream. [a]pply all / [r]eview each / [s]kip all:"
            $ans = Read-Host
            if ($ans) { $mode = $ans }
        }
        if ($mode -match '^[sS]') { $script:applyMode = 's' }
        foreach ($f in $changedList) {
            switch -Regex ($mode) {
                '^[sS]' { Write-Host "  skip   $f"; $nSkipped++ }
                '^[rR]' {
                    Write-Host ""; Write-Host "--- $f ---" -ForegroundColor White
                    & git --no-pager diff --no-index (Join-Path $root $f) (Join-Path $src $f) 2>$null
                    $yn = Read-Host "Update this file? [y/N]"
                    if ($yn -match '^[yY]') { Apply-File $f; $script:appliedChanged += $f; Write-Ok "updated $f" } else { Write-Host "  skip   $f"; $nSkipped++ }
                }
                default { Apply-File $f; $script:appliedChanged += $f; Write-Ok "updated $f" }
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

    # Install the new updater BEFORE the record is written: those paths are vendored content
    # too, and the self-modification guard treats anything absent from the record as authored.
    $selfInstalled = Install-Self
    # See update.sh: a failed self-install must not be locked in behind the version gate, and
    # the record must carry the version that actually ends up in .sumela/VERSION.
    $declinedSelf = ($script:applyMode -eq 's') -or
                    ($changedList.Count -gt 0 -and $script:appliedChanged.Count -eq 0)
    $selfFailed = ($deferredList.Count -gt 0) -and ($selfInstalled.Count -eq 0) -and (-not $declinedSelf)
    $recordVer = if ($selfFailed) { $localVer } else { $srcVer }
    $vendored = @($newList) + @($script:appliedChanged)
    if ($doSchema) { $vendored += $schemaLive }
    if ($selfInstalled.Count -gt 0) { $vendored += $selfInstalled }
    Write-Provenance $vendored -Version $recordVer

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

    # Org-shared rules (monorepo): refresh synced copies + register new ones. No-op
    # unless .sumela-shared/rules/ exists above this install.
    $syncShared = Join-Path $root "scripts/sync-shared-rules.py"
    if ((Test-Path $syncShared) -and (Get-Command python3 -ErrorAction SilentlyContinue)) {
        $shrOut = & python3 $syncShared --check 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host ""; $shrOut | ForEach-Object { Write-Host "  $_" }
            $doShr = $true
            if (-not $Yes) {
                $yn = Read-Host "Sync org-shared rules into this install now? [Y/n]"
                if ($yn -match '^[nN]') { $doShr = $false }
            }
            if ($doShr) { & python3 $syncShared | ForEach-Object { Write-Host "  $_" } }
        }
    }

    if ($selfFailed) {
        Write-Warn "The new updater could not be installed; VERSION left at $localVer so a re-run retries."
    } else {
        Set-Content -Path (Join-Path $root ".sumela/VERSION") -Value $srcVer
    }
    # See update.sh: the update-check cache still holds the PRE-upgrade version, so the next
    # pull would announce an upgrade that already happened. Delete it; _lib.sh re-probes.
    Remove-Item -Path (Join-Path $root ".sumela/.update-check") -Force -ErrorAction SilentlyContinue

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
    # Domain-scope migration notice (overlay RULE_REGISTRY.md is untouched; a pre-domain
    # project won't have <domain_scopes>, which the refreshed prompt STEP 4 expects).
    $rr = Join-Path $root ".sumela/RULE_REGISTRY.md"
    if ((Test-Path $rr) -and -not (Select-String -Path $rr -Pattern '^<domain_scopes>$' -Quiet)) {
        Write-Warn "Business-domain support arrived in this core, but your RULE_REGISTRY.md has no <domain_scopes> section yet."
        Write-Warn "  To enable domains: add the <domain_scopes> block (see RULE_REGISTRY.md.template) — fastest via /onboardSumela or /evolve. Until then domains are simply inactive (no breakage)."
    }
    if ($deferredList.Count -gt 0) {
        # See update.sh: an updater only knows the CORE list IT shipped with, so this run may
        # have skipped files that became CORE after this copy was written. Install the new
        # updater and make the re-run instruction impossible to miss.
        if ($selfInstalled.Count -eq 0 -and ($script:applyMode -eq 's' -or
            ($changedList.Count -gt 0 -and $script:appliedChanged.Count -eq 0))) {
            Write-Warn "The updater also changed upstream; left in place because you declined the changes."
            Write-Warn "  Apply it when you want to:  pwsh scripts/update.ps1 -Force"
        } elseif ($selfInstalled.Count -eq 0) {
            Write-Warn "The updater changed upstream but could NOT be installed — replace"
            Write-Warn "  scripts/update.ps1 by hand, then re-run:  pwsh scripts/update.ps1 -Force"
        } else {
        Write-Warn "The updater itself changed upstream. The NEW scripts/update.ps1 has been installed."
        Write-Warn "  This run was executed by the OLD one, which cannot know about files that became"
        Write-Warn "  CORE in a release between your previous version and $srcVer."
        Write-Warn "  RE-RUN NOW to finish the upgrade:  pwsh scripts/update.ps1 -Force"
        Write-Warn "  (-Force is required: this run already stamped VERSION, so a plain re-run"
        Write-Warn "   would stop at the version gate without applying anything.)"
        }
    }
    Write-Host "Review changes with 'git diff' before committing."
}
finally {
    if ($cloneTmp -and (Test-Path $cloneTmp)) { Remove-Item -Recurse -Force $cloneTmp }
}
