<#
.SYNOPSIS
    Keep verbatim IDE mirrors of .sumela/sumela-prompt.md in sync (PowerShell parity
    of scripts/sync-mirrors.sh). Only the content between the
    <!-- SUMELA-MIRROR:BEGIN --> / <!-- SUMELA-MIRROR:END --> markers is rewritten.
.PARAMETER Check  Exit 1 if any listed mirror has drifted (for CI / pre-commit).
.PARAMETER Init   Scaffold any listed-but-missing mirror file.
#>
param([switch]$Check, [switch]$Init)

$mode = if ($Check) { "check" } elseif ($Init) { "init" } else { "sync" }

$root = (Get-Location).Path
while ((-not (Test-Path (Join-Path $root ".sumela"))) -and ($root -ne (Split-Path $root -Parent)) -and $root) {
    $root = Split-Path $root -Parent
}
if (-not (Test-Path (Join-Path $root ".sumela"))) { Write-Host "sync-mirrors: no .sumela/ found."; exit 0 }

$promptPath = Join-Path $root ".sumela/sumela-prompt.md"
$confPath = Join-Path $root ".sumela/mirrors.conf"
if (-not (Test-Path $promptPath)) { Write-Host "sync-mirrors: sumela-prompt.md missing — nothing to mirror."; exit 0 }
if (-not (Test-Path $confPath)) {
    if ($mode -eq "check") { exit 0 }
    Write-Host "sync-mirrors: no .sumela/mirrors.conf (copy .sumela/mirrors.conf.example) — nothing to do."; exit 0
}

$mirrors = @()
foreach ($raw in Get-Content $confPath) {
    $line = ($raw -replace '#.*', '').Trim()
    if ($line) { $mirrors += $line }
}
if ($mirrors.Count -eq 0) {
    if ($mode -eq "check") { exit 0 }
    Write-Host "sync-mirrors: .sumela/mirrors.conf has no entries — nothing to do."; exit 0
}

$BEGIN = "SUMELA-MIRROR:BEGIN"; $END = "SUMELA-MIRROR:END"
$BEGIN_LINE = "<!-- SUMELA-MIRROR:BEGIN — auto-generated from .sumela/sumela-prompt.md; do not edit between the markers. Run scripts/sync-mirrors.sh to regenerate. -->"
$END_LINE = "<!-- SUMELA-MIRROR:END -->"
$prompt = ((Get-Content $promptPath -Raw) -replace "(`r?`n)+$", "")
$promptLines = $prompt -split "`r?`n"

$rc = 0
foreach ($rel in $mirrors) {
    $norm = $rel -replace '\\', '/'
    if ([System.IO.Path]::IsPathRooted($rel) -or $norm.StartsWith('/') -or ($norm -split '/') -contains '..') {
        Write-Host "  REFUSED $rel (absolute or '..' path not allowed)"; $rc = 1; continue
    }
    $path = Join-Path $root $rel
    if ($mode -eq "init") {
        if (Test-Path $path) { Write-Host "  exists  $rel (left as-is)"; continue }
        $dir = Split-Path $path -Parent
        if ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $hdr = "<!-- This file mirrors .sumela/sumela-prompt.md for an IDE that needs the prompt body`n     verbatim. Put any IDE-specific frontmatter/wrapper OUTSIDE the markers. -->`n`n"
        # Trailing "`n" (kept via -NoNewline) so the file ends in a single LF, byte-matching update.sh — avoids cross-OS EOF churn.
        Set-Content -Path $path -Value ($hdr + $BEGIN_LINE + "`n" + $prompt + "`n" + $END_LINE + "`n") -NoNewline
        Write-Host "  created $rel"; continue
    }
    if (-not (Test-Path $path)) { Write-Host "  MISSING $rel (run: scripts/sync-mirrors.ps1 -Init)"; $rc = 1; continue }

    $lines = @(Get-Content $path)
    $bi = -1; $ei = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if (($lines[$i] -like "*$BEGIN*") -and ($bi -eq -1)) { $bi = $i }
        elseif (($lines[$i] -like "*$END*") -and ($bi -ne -1) -and ($ei -eq -1)) { $ei = $i }
    }
    if (($bi -eq -1) -or ($ei -eq -1) -or ($ei -le $bi)) {
        Write-Host "  NO-MARKERS $rel (add SUMELA-MIRROR:BEGIN/END, or run -Init)"; $rc = 1; continue
    }
    $innerArr = if ($ei - 1 -ge $bi + 1) { $lines[($bi + 1)..($ei - 1)] } else { @() }
    $inner = (($innerArr -join "`n") -replace "(`r?`n)+$", "")
    if ($inner -eq $prompt) {
        Write-Host "  ok      $rel"
    }
    elseif ($mode -eq "check") {
        Write-Host "  DRIFT   $rel (mirror block differs — run scripts/sync-mirrors.ps1)"; $rc = 1
    }
    else {
        $pre = if ($bi -gt 0) { $lines[0..($bi - 1)] } else { @() }
        $post = if ($ei -lt $lines.Count - 1) { $lines[($ei + 1)..($lines.Count - 1)] } else { @() }
        $new = @($pre) + @($BEGIN_LINE) + @($promptLines) + @($END_LINE) + @($post)
        Set-Content -Path $path -Value (($new -join "`n") + "`n") -NoNewline
        Write-Host "  synced  $rel"
    }
}
exit $rc
