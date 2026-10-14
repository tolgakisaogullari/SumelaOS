# tests/test_provenance.ps1 - the provenance record, PowerShell twin (R1-03).
#
# The Windows-native half of tests/test_provenance.sh: Write-SumelaRecord and
# Add-SumelaRecordFiles must write the record without a BOM (Windows PowerShell 5.1's
# Set-Content -Encoding UTF8 adds one), keep "files" to what the developer did not write, carry
# what the run's tools added earlier while HEAD and the content are unchanged and nothing an
# earlier run vendored or a developer edited [RU-M4], read "files" only as an array of strings,
# name a git failure, refuse bad input with the bash twin's exit codes, compare and order paths
# by UTF-8 bytes under any culture, and write the same bytes as the bash twin (run through Git
# Bash on Windows when it is there, else SKIP).
#
# Labels are ASCII: Windows PowerShell 5.1 reads a BOM-less script in the ANSI code page.
#
# Run:  pwsh -NoProfile -File tests/test_provenance.ps1   (or: powershell -NoProfile -File ...)
# Exit 0 = all assertions passed, 1 = a failure (printed above).

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repoRoot = Split-Path -Parent $PSScriptRoot
$libPs = Join-Path $repoRoot 'scripts/lib/sumela-provenance.ps1'
$libSh = Join-Path $repoRoot 'scripts/lib/sumela-provenance.sh'
. $libPs

$script:pass = 0
$script:fail = 0
function Ok([string]$m) { Write-Host "  PASS  $m"; $script:pass++ }
function Bad([string]$m) { Write-Host "  FAIL  $m"; $script:fail++ }
function Skip([string]$m) { Write-Host "  SKIP  $m" }
function Same([string]$label, $expected, $got) {
    # Ordinal: -ceq would call 'a.md' and 'a<U+00AD>.md' equal.
    if ([string]::Equals([string]$expected, [string]$got, [StringComparison]::Ordinal)) { Ok $label } else { Bad "$label (expected '$expected', got '$got')" }
}
function Has([string]$label, [string]$text, [string]$want) {
    if ($text.IndexOf($want, [StringComparison]::Ordinal) -ge 0) { Ok $label } else { Bad "$label (wanted '$want' in '$text')" }
}
function tgit {
    $ErrorActionPreference = 'Continue'
    $out = & git @args 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git $($args -join ' ') failed: $out" }
    return $out
}
$utf8 = New-Object System.Text.UTF8Encoding $false
$onWindows = $env:OS -ceq 'Windows_NT'
$TAB = [string][char]9

function New-Install([string]$dir, [string]$sub = '.') {
    # A repository with one commit and an install at the subdir; the record is gitignored, as in
    # a consumer.
    $at = $dir
    if ($sub -cne '.') { $at = Join-Path $dir $sub }
    foreach ($d in @('.sumela/rules', '.sumela/migrations-applied', 'scripts')) { [void][IO.Directory]::CreateDirectory((Join-Path $at $d)) }
    tgit -C $dir init -q -b main | Out-Null
    tgit -C $dir config user.email t@example.com | Out-Null
    tgit -C $dir config user.name Test | Out-Null
    [IO.File]::WriteAllText((Join-Path $dir '.gitignore'), ".last-update.json`n", $utf8)
    [IO.File]::WriteAllText((Join-Path $at '.sumela/VERSION'), "0.19.0`n", $utf8)
    [IO.File]::WriteAllText((Join-Path $at '.sumela/rules/a.md'), "a`n", $utf8)
    [IO.File]::WriteAllText((Join-Path $at 'scripts/b.sh'), "b`n", $utf8)
    [IO.File]::WriteAllText((Join-Path $at '.sumela/SKILL_REGISTRY.md'), "reg`n", $utf8)
    tgit -C $dir add -A | Out-Null
    tgit -C $dir commit -qm init | Out-Null
    return $at
}
function Set-Text([string]$path, [string]$text) { [IO.File]::WriteAllText($path, $text, $utf8) }
function Rec([string]$at) { return (Join-Path $at '.sumela/.last-update.json') }
function Files([string]$rec) { return ((@(Get-SumelaRecordFiles -Record $rec 3>$null)) -join '|') }
function Value([string]$rec, [string]$key) { return ((@(Get-SumelaRecordValue -Key $key -Record $rec)) -join '|') }
function Head([string]$dir) { return [string](tgit -C $dir rev-parse HEAD) }
function Blob([string]$dir, [string]$path) { return [string](tgit -C $dir hash-object --no-filters -- $path) }
function Commit-All([string]$dir, [string]$msg) {
    tgit -C $dir add -A . | Out-Null
    tgit -C $dir commit -qm $msg | Out-Null
}
function Invoke-Coded([scriptblock]$block) {
    # 0 when the block succeeds, else the exception's SumelaExitCode (9 when it has none)
    try { & $block 3>$null | Out-Null; return 0 }
    catch { $c = $_.Exception.Data['SumelaExitCode']; if ($null -eq $c) { return 9 }; return [int]$c }
}
function Get-Warnings([scriptblock]$block) {
    # The warnings a block writes, one per line (the bash twin's stderr).
    $w = & { & $block | Out-Null } 3>&1 | ForEach-Object { [string]$_ }
    return ((@($w)) -join "`n")
}
function Get-Masked([string]$rec) {
    $text = [IO.File]::ReadAllText($rec, $utf8)
    return [regex]::Replace($text, '"updated_at": "[^"]*"', '"updated_at": "T"')
}
function Get-Head([string]$rec) {
    $b = [IO.File]::ReadAllBytes($rec)
    if ($b.Length -eq 0) { return '' }
    return ('{0:x2}' -f $b[0])
}
function Find-Bash {
    if ($onWindows) {
        $ErrorActionPreference = 'Continue'
        $exec = [string](& git --exec-path)
        foreach ($rel in @('../../../bin/bash.exe', '../../../usr/bin/bash.exe', '../../bin/bash.exe', '../../usr/bin/bash.exe')) {
            $p = [IO.Path]::GetFullPath((Join-Path $exec $rel))
            if ([IO.File]::Exists($p)) { return $p }
        }
        return $null
    }
    $cmd = Get-Command bash -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    return $null
}

$work = Join-Path ([IO.Path]::GetTempPath()) ('sumela-prov-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($work)
$work = (Resolve-Path -LiteralPath $work).ProviderPath
$envNames = @('GIT_DIR', 'GIT_AUTHOR_DATE', 'GIT_COMMITTER_DATE', 'GIT_TEST_ASSUME_DIFFERENT_OWNER', 'GIT_CONFIG_GLOBAL', 'GIT_CONFIG_NOSYSTEM')
$savedEnv = @{}
foreach ($n in $envNames) { $savedEnv[$n] = [Environment]::GetEnvironmentVariable($n) }
try {
    [Environment]::SetEnvironmentVariable('GIT_DIR', [NullString]::Value)
    # Fixed commit dates: two fixtures built the same way get the same HEAD (the parity steps
    # compare "carry_head" bytes).
    $env:GIT_AUTHOR_DATE = '2026-10-14T00:00:00 +0000'
    $env:GIT_COMMITTER_DATE = '2026-10-14T00:00:00 +0000'

    Write-Host '== written without a BOM, LF only'
    $t = New-Install (Join-Path $work 't1')
    Push-Location -LiteralPath $t
    try {
        Write-SumelaRecord -Version 0.20.0 -State complete -Files @('b.md', 'a.md') -Merged 'm.md' -Kept "k.md${TAB}fork"
        Add-SumelaRecordFiles -Path 'c.md'
    } finally { Pop-Location }
    $r = Rec $t
    Same 'the first byte is "{" (no BOM)' '7b' (Get-Head $r)
    Same 'no CR byte' 'False' ([string]([IO.File]::ReadAllText($r, $utf8).Contains("`r")))
    Same 'files holds only the files rows, sorted' 'a.md|b.md|c.md' (Files $r)
    Same 'merged and kept are not in files' 'm.md|k.md' ((Value $r 'merged') + '|' + ((Value $r 'kept').Split([char]9)[0]))
    Same 'a number' '2' (Value $r 'updater_schema')
    Same 'an absent key is $null' 'True' ([string]($null -eq (Get-SumelaRecordValue -Key nope -Record $r)))
    Same 'the add binds c.md to HEAD and to no file (-)' ((Head $t) + ' - c.md') ((Value $r 'carry_head') + ' ' + (Value $r 'carry'))

    Write-Host '== v0.19''s Windows PowerShell 5.1 record (BOM, blank line, no final newline)'
    $v1 = Join-Path $work 'v1.json'
    [IO.File]::WriteAllBytes($v1, [byte[]](0xEF, 0xBB, 0xBF) + $utf8.GetBytes("{`n  `"version`": `"0.19.0`",`n  `"pending_rerun`": false,`n  `"files`": [`n`n  ]`n}"))
    Same 'its version reads' '0.19.0' (Value $v1 'version')
    Add-SumelaRecordFiles -Path 'x.md' -Record $v1 3>$null    # no git above the temp directory: a warning, still written
    Same 'Add drops the BOM' '7b' (Get-Head $v1)
    Same '...keeps the record v1 (no updater_schema)' 'True' ([string]($null -eq (Get-SumelaRecordValue -Key updater_schema -Record $v1)))
    Same '...and records the path' 'x.md' (Files $v1)
    [IO.File]::WriteAllText($v1, "{`r`n  `"version`": `"0.19.0`",`r`n  `"files`": [`r`n    `"a.md`"`r`n  ]`r`n}`r`n", $utf8)
    Same 'a CRLF record reads, without CRs' '0.19.0|a.md' ((Value $v1 'version') + '|' + (Files $v1))
    $bom2 = Join-Path $work 'bom2.json'
    [IO.File]::WriteAllBytes($bom2, [byte[]](0xEF, 0xBB, 0xBF, 0xEF, 0xBB, 0xBF) + $utf8.GetBytes("{`n  `"files`": [`n    `"a.md`"`n  ]`n}`n"))
    Same 'two BOMs: unreadable, as in bash (vouches for nothing)' '' (Files $bom2)
    Same '...and add refuses it: code 3' 3 (Invoke-Coded { Add-SumelaRecordFiles -Record $bom2 -Path 'b.md' })

    Write-Host '== what a write carries [RU-M4]'
    # (a) a fresh upgrade worktree: the run's earlier tool paths are kept
    $t = New-Install (Join-Path $work 't3a'); $r = Rec $t
    Set-Text (Join-Path $t '.sumela/migrations-applied/upgrade-01@0.20.0') "status: done`n"
    Set-Text (Join-Path $t '.sumela/SKILL_REGISTRY.md') "reg2`n"
    Add-SumelaRecordFiles -Record $r -Path '.sumela/migrations-applied/upgrade-01@0.20.0'
    Add-SumelaRecordFiles -Record $r -Path '.sumela/SKILL_REGISTRY.md'
    Write-SumelaRecord -Record $r -Version 0.20.0 -State complete -Files '.sumela/rules/a.md'
    Same 'the ledger and the registry are kept beside the vendored file' '.sumela/SKILL_REGISTRY.md|.sumela/migrations-applied/upgrade-01@0.20.0|.sumela/rules/a.md' (Files $r)
    Same 'a finished run''s record has no carry list' 'True True' ([string]($null -eq (Get-SumelaRecordValue -Key carry -Record $r)) + ' ' + [string]($null -eq (Get-SumelaRecordValue -Key carry_head -Record $r)))
    # (b) the next run in place: nothing committed by the earlier run is carried
    Set-Text (Join-Path $t '.sumela/migrations-applied/upgrade-04@0.20.0') "status: done`n"
    Add-SumelaRecordFiles -Record $r -Path '.sumela/migrations-applied/upgrade-04@0.20.0'
    Commit-All $t 'upgrade to v0.20.0'
    Set-Text (Join-Path $t '.sumela/migrations-applied/upgrade-01@0.20.1') "status: done`n"
    Add-SumelaRecordFiles -Record $r -Path '.sumela/migrations-applied/upgrade-01@0.20.1'
    Write-SumelaRecord -Record $r -Version 0.20.1 -State complete -Files 'scripts/b.sh'
    Same 'only this run''s uncommitted tool path is carried' '.sumela/migrations-applied/upgrade-01@0.20.1|scripts/b.sh' (Files $r)
    # (c) partial, then complete in another call; the partial pass applied a.md (uncommitted)
    $t = New-Install (Join-Path $work 't3c'); $r = Rec $t
    Set-Text (Join-Path $t '.sumela/rules/a.md') "a2`n"
    Write-SumelaRecord -Record $r -Version 0.19.0 -State partial -BaseVersion 0.19.0 -UpstreamCommit 0a1b -Files '.sumela/rules/a.md' -Merged 'scripts/b.sh' -Kept ".sumela/k.md${TAB}fork"
    Same 'a partial record lists its files in carry, at HEAD' ((Head $t) + ' ' + (Blob $t '.sumela/rules/a.md') + ' .sumela/rules/a.md') ((Value $r 'carry_head') + ' ' + (Value $r 'carry'))
    Write-SumelaRecord -Record $r -Version 0.20.0 -State complete -TheirsOverFork '.sumela/t.md'
    $got = (Files $r) + ' ' + (Value $r 'merged') + ' ' + (Value $r 'theirs_over_fork') + ' ' + (Value $r 'base_version') + ' ' + (Value $r 'partial_upgrade')
    Same 'completing a partial run keeps every row and the base' '.sumela/rules/a.md scripts/b.sh .sumela/t.md 0.19.0 false' $got
    Same '...but not 0.19.0''s upstream_commit in a 0.20.0 record' '' (Value $r 'upstream_commit')
    # (c2) upstream_commit stays paired with its version
    $t = New-Install (Join-Path $work 't3c2'); $r = Rec $t
    Write-SumelaRecord -Record $r -Version 0.19.0 -State partial -BaseVersion 0.19.0 -UpstreamCommit 0a1b2c -Kept ".sumela/x.md${TAB}conflict:local"
    Write-SumelaRecord -Record $r -Version 0.19.0 -State partial
    Same 'a partial write at the same version keeps upstream_commit and the rows' ('0a1b2c .sumela/x.md' + $TAB + 'conflict:local') ((Value $r 'upstream_commit') + ' ' + (Value $r 'kept'))
    Write-SumelaRecord -Record $r -Version 0.20.0 -State complete -UpstreamCommit 9f8e7d
    Same 'the completing write records the commit it is given' '9f8e7d' (Value $r 'upstream_commit')
    # (d) pending_rerun: the first pass installed the updater (uncommitted)
    $t = New-Install (Join-Path $work 't3d'); $r = Rec $t
    Set-Text (Join-Path $t 'scripts/update.sh') "new updater`n"
    Write-SumelaRecord -Record $r -Version 0.19.0 -State complete -PendingRerun -Files 'scripts/update.sh'
    Write-SumelaRecord -Record $r -Version 0.20.0 -State complete -Files '.sumela/rules/a.md'
    Same 'the re-run carries the first pass' '.sumela/rules/a.md|scripts/update.sh' (Files $r)
    # (d2) an abandoned partial run whose file was restored: the next write does not vouch for it
    $t = New-Install (Join-Path $work 't3i'); $r = Rec $t
    Set-Text (Join-Path $t '.sumela/rules/a.md') "a2`n"
    Set-Text (Join-Path $t 'scripts/b.sh') "b2`n"
    Write-SumelaRecord -Record $r -Version 0.19.0 -State partial -Files @('.sumela/rules/a.md', 'scripts/b.sh') -Merged '.sumela/m.md'
    tgit -C $t checkout -q -- .sumela/rules/a.md | Out-Null
    Write-SumelaRecord -Record $r -Version 0.20.0 -State complete -Files '.sumela/VERSION'
    Same 'an abandoned run''s restored file is not carried; its still-applied one is' '.sumela/VERSION|scripts/b.sh' (Files $r)
    # (e) a dirty file of an earlier run's record never starts vouching
    $t = New-Install (Join-Path $work 't3f'); $r = Rec $t
    Set-Text (Join-Path $t '.sumela/rules/a.md') "a2`n"
    Write-SumelaRecord -Record $r -Version 0.20.0 -State complete -Files @('.sumela/rules/a.md', 'scripts/b.sh')
    Commit-All $t 'c'
    Set-Text (Join-Path $t '.sumela/rules/a.md') "hand edit`n"
    Write-SumelaRecord -Record $r -Version 0.20.1 -State partial -Files '.sumela/VERSION'
    Same 'an uncommitted hand-edit is not vouched' '.sumela/VERSION' (Files $r)
    # (f) a monorepo install with spaces and non-ASCII names; a directory entry is not expanded
    $sub = 'svc/a b'
    $t = New-Install (Join-Path $work 't3g') $sub; $r = Rec $t
    $ledger = '.sumela/migrations-applied/x y/' + [char]0x00F6 + ' ' + [char]0x015F
    [void][IO.Directory]::CreateDirectory((Join-Path $t '.sumela/migrations-applied/x y'))
    Set-Text (Join-Path $t $ledger) "done`n"
    [void][IO.Directory]::CreateDirectory((Join-Path $t '.sumela/newdir'))
    Set-Text (Join-Path $t '.sumela/newdir/inner.md') "n`n"
    Push-Location -LiteralPath (Join-Path $t 'scripts')
    try {
        Add-SumelaRecordFiles -Path @($ledger, '.sumela/migrations-applied/missing', '.sumela/newdir')
        Write-SumelaRecord -Version 0.20.0 -State complete -Files 'scripts/b.sh'
    } finally { Pop-Location }
    Same 'monorepo: the untracked ledger is carried; the missing one and the directory are not' ($ledger + '|scripts/b.sh') (Files $r)
    # (j) a tool path recorded after a finished write, committed, then hand-edited
    $t = New-Install (Join-Path $work 't3j'); $r = Rec $t
    Set-Text (Join-Path $t '.sumela/rules/a.md') "a2`n"
    Set-Text (Join-Path $t '.sumela/VERSION') "0.20.0`n"
    Write-SumelaRecord -Record $r -Version 0.20.0 -State complete -BaseVersion 0.19.0 -Files @('.sumela/rules/a.md', '.sumela/VERSION')
    Set-Text (Join-Path $t '.sumela/SKILL_REGISTRY.md') "reg + synced skill`n"
    Add-SumelaRecordFiles -Record $r -Path '.sumela/SKILL_REGISTRY.md'
    Commit-All $t 'upgrade to v0.20.0'
    Set-Text (Join-Path $t '.sumela/SKILL_REGISTRY.md') "reg + HAND-LOOSENED ENTRY`n"
    Set-Text (Join-Path $t 'scripts/b.sh') "b2`n"
    Write-SumelaRecord -Record $r -Version 0.20.1 -State complete -BaseVersion 0.20.0 -Files 'scripts/b.sh'
    Same 'a committed tool path, hand-edited later, is not carried by the next run' 'scripts/b.sh' (Files $r)
    # (k) the same at one HEAD: edited after it was recorded
    $t = New-Install (Join-Path $work 't3k'); $r = Rec $t
    Set-Text (Join-Path $t '.sumela/SKILL_REGISTRY.md') "reg2`n"
    Add-SumelaRecordFiles -Record $r -Path '.sumela/SKILL_REGISTRY.md'
    Set-Text (Join-Path $t '.sumela/SKILL_REGISTRY.md') "reg2 + HAND-LOOSENED ENTRY`n"
    $warn = Get-Warnings { Write-SumelaRecord -Record $r -Version 0.20.0 -State complete -Files 'scripts/b.sh' }
    Same 'a tool path edited after it was recorded is not carried' 'scripts/b.sh' (Files $r)
    Has '...and the write names it' $warn '.sumela/SKILL_REGISTRY.md changed after it was recorded'
    # (l) a partial run's file edited before the run completes
    $t = New-Install (Join-Path $work 't3l'); $r = Rec $t
    Set-Text (Join-Path $t '.sumela/rules/a.md') "a2`n"
    Set-Text (Join-Path $t 'scripts/b.sh') "b2`n"
    Write-SumelaRecord -Record $r -Version 0.19.0 -State partial -Files @('.sumela/rules/a.md', 'scripts/b.sh')
    Set-Text (Join-Path $t '.sumela/rules/a.md') "a2 + hand edit`n"
    Write-SumelaRecord -Record $r -Version 0.20.0 -State complete -Files '.sumela/VERSION' 3>$null
    Same 'a partial run''s file edited before completion is not carried; the untouched one is' '.sumela/VERSION|scripts/b.sh' (Files $r)
    # (m) recorded paths gone by the write: deleted (untracked or tracked), git rm'd, or deleted
    #     before they were recorded ("-", an uncommitted deletion when the write runs)
    $t = New-Install (Join-Path $work 't3m'); $r = Rec $t
    Set-Text (Join-Path $t '.sumela/migrations-applied/s1') "done`n"
    Set-Text (Join-Path $t '.sumela/migrations-applied/s2') "done`n"
    Set-Text (Join-Path $t 'scripts/b.sh') "b2`n"
    Set-Text (Join-Path $t '.sumela/SKILL_REGISTRY.md') "reg2`n"
    [IO.File]::Delete((Join-Path $t '.sumela/rules/a.md'))
    Add-SumelaRecordFiles -Record $r -Path @('.sumela/migrations-applied/s1', '.sumela/migrations-applied/s2', 'scripts/b.sh', '.sumela/SKILL_REGISTRY.md', '.sumela/rules/a.md')
    [IO.File]::Delete((Join-Path $t '.sumela/migrations-applied/s1'))
    [IO.File]::Delete((Join-Path $t 'scripts/b.sh'))
    tgit -C $t rm -q -f .sumela/SKILL_REGISTRY.md | Out-Null
    Write-SumelaRecord -Record $r -Version 0.20.0 -State complete -Files '.sumela/VERSION'
    Same 'deleted and git rm''d paths are not carried; the present one is' '.sumela/VERSION|.sumela/migrations-applied/s2' (Files $r)
    # (n) a finished run's record lends nothing
    $t = New-Install (Join-Path $work 't3n'); $r = Rec $t
    Write-SumelaRecord -Record $r -Version 0.20.0 -State complete -BaseVersion 0.19.0 -UpstreamCommit 0a1b2c -Files '.sumela/rules/a.md' -Merged '.sumela/m.md' -Kept ".sumela/k.md${TAB}fork" -TheirsOverFork '.sumela/t.md' -Removed '.sumela/r.md'
    Write-SumelaRecord -Record $r -Version 0.20.0 -State complete -Files 'scripts/b.sh'
    foreach ($k in @('merged', 'kept', 'theirs_over_fork', 'removed', 'base_version', 'upstream_commit')) {
        Same "a finished record's $k is not carried" '' (Value $r $k)
    }
    Same '...nor its files' 'scripts/b.sh' (Files $r)
    # (o) a pre-0.20 pending_rerun record binds no content
    $t = New-Install (Join-Path $work 't3o'); $r = Rec $t
    Set-Text (Join-Path $t 'scripts/b.sh') "new b`n"
    Set-Text $r "{`n  `"version`": `"0.19.0`",`n  `"pending_rerun`": true,`n  `"files`": [`n    `"scripts/b.sh`"`n  ]`n}`n"
    Write-SumelaRecord -Record $r -Version 0.20.0 -State complete -Files '.sumela/VERSION'
    Same 'a v1 pending_rerun record binds no content, so none of its files is carried' '.sumela/VERSION' (Files $r)
    # (p) an entry recorded before a commit is not carried, even with its content unchanged
    $t = New-Install (Join-Path $work 't3p'); $r = Rec $t
    Set-Text (Join-Path $t '.sumela/migrations-applied/x') "status: done`n"
    Add-SumelaRecordFiles -Record $r -Path '.sumela/migrations-applied/x'
    Set-Text (Join-Path $t 'other.txt') "c`n"
    tgit -C $t add other.txt | Out-Null
    tgit -C $t commit -qm other | Out-Null
    Write-SumelaRecord -Record $r -Version 0.20.0 -State complete -Files 'scripts/b.sh'
    Same 'an unchanged entry recorded before a commit is not carried' 'scripts/b.sh' (Files $r)
    # (q) a name holding a line break never poses as another status entry
    if ($onWindows) {
        Skip 'a line break in a name (Windows file systems refuse it)'
    } else {
        $t = New-Install (Join-Path $work 't3q'); $r = Rec $t
        Add-SumelaRecordFiles -Record $r -Path '.sumela/SKILL_REGISTRY.md'     # clean: HEAD's content
        $weird = Join-Path $t (".sumela/x`n?? .sumela")
        [void][IO.Directory]::CreateDirectory($weird)
        Set-Text (Join-Path $weird 'SKILL_REGISTRY.md') "z`n"
        Write-SumelaRecord -Record $r -Version 0.20.0 -State complete -Files 'scripts/b.sh'
        Same 'a name with a line break does not make a clean recorded path look uncommitted' 'scripts/b.sh' (Files $r)
    }

    Write-Host '== refusals carry the bash exit codes'
    $t = New-Install (Join-Path $work 't4'); $r = Rec $t
    Write-SumelaRecord -Record $r -Version 0.20.0 -State complete -Files 'a.md'
    $before = Get-Masked $r
    $cases = @(
        @('one path in two classes', { Write-SumelaRecord -Record $r -Version 0.20.1 -State complete -Files 'x.md' -Merged 'x.md' }),
        @('a quote in a path', { Write-SumelaRecord -Record $r -Version 0.20.1 -State complete -Files 'q"x.md' }),
        @('a backslash in a path', { Write-SumelaRecord -Record $r -Version 0.20.1 -State complete -Files 'b\x.md' }),
        @('a TAB in a path', { Write-SumelaRecord -Record $r -Version 0.20.1 -State complete -Files "t${TAB}x.md" }),
        @('a kept row without a reason', { Write-SumelaRecord -Record $r -Version 0.20.1 -State complete -Kept 'k.md' }),
        @('a version that is not one', { Write-SumelaRecord -Record $r -Version '-rf' -State complete }),
        @('a version with a line break', { Write-SumelaRecord -Record $r -Version "0.20.1`nx" -State complete }),
        @('a version with a line break before a row-shaped line', { Write-SumelaRecord -Record $r -Version "0.20.1`npath${TAB}x" -State complete }),
        @('a version ending in a line break', { Write-SumelaRecord -Record $r -Version "0.20.1`n" -State complete }),
        @('a base version with a line break', { Write-SumelaRecord -Record $r -Version 0.20.1 -State complete -BaseVersion "0.20.0`nversion${TAB}1" }),
        @('an upstream commit with a line break', { Write-SumelaRecord -Record $r -Version 0.20.1 -State complete -UpstreamCommit "abc`nwhy${TAB}fork" }),
        @('an upstream commit that is not lowercase hex', { Write-SumelaRecord -Record $r -Version 0.20.1 -State complete -UpstreamCommit 'HEAD~1' }),
        @('a state that is neither', { Write-SumelaRecord -Record $r -Version 0.20.1 -State done }),
        @('a state that is complete plus a soft hyphen', { Write-SumelaRecord -Record $r -Version 0.20.1 -State ('complete' + [char]0xAD) }),
        @('add: a quote', { Add-SumelaRecordFiles -Record $r -Path 'q"x' }),
        @('add: a line break', { Add-SumelaRecordFiles -Record $r -Path "n`nx" }),
        @('add: an empty path', { Add-SumelaRecordFiles -Record $r -Path '' })
    )
    foreach ($c in $cases) {
        Same "$($c[0]): code 2" 2 (Invoke-Coded $c[1])
        Same "$($c[0]): the record is unchanged" $before (Get-Masked $r)
    }
    Set-Text $r "{`n  `"files`": [`n    `"a.md`",`n  `"oops`"`n}`n"
    Same 'add to an unreadable record: code 3' 3 (Invoke-Coded { Add-SumelaRecordFiles -Record $r -Path 'b.md' })
    Same 'Get-SumelaRecordFiles on an unreadable record: nothing' '' (Files $r)
    Same 'the updater''s write replaces it' 0 (Invoke-Coded { Write-SumelaRecord -Record $r -Version 0.20.0 -State complete -Files 'c.md' })
    Same '...with its own content' 'c.md' (Files $r)
    Same 'an invalid key: code 2' 2 (Invoke-Coded { Get-SumelaRecordValue -Key 'Bad-Key' -Record $r })

    Write-Host '== "files" only as an array of strings'
    $shapeRec = Join-Path $work 'shape.json'
    foreach ($shape in @('"a.md"', '[{"path": "a.md", "why": "fork"}]', '1', 'true', '["a.md", 1]')) {
        Set-Text $shapeRec "{`n  `"version`": `"0.20.0`",`n  `"files`": $shape`n}`n"
        Same "files as $shape vouches for nothing" '' (Files $shapeRec)
        Same '...and Get-SumelaRecordValue -Key files agrees' '' ((@(Get-SumelaRecordValue -Key files -Record $shapeRec 3>$null)) -join '|')
        $beforeShape = [IO.File]::ReadAllText($shapeRec, $utf8)
        Same "add to a record whose files is ${shape}: code 3" 3 (Invoke-Coded { Add-SumelaRecordFiles -Record $shapeRec -Path 'b.md' })
        Same '...and it is left unchanged' $beforeShape ([IO.File]::ReadAllText($shapeRec, $utf8))
    }
    Has 'the reader says why it vouches for nothing' (Get-Warnings { Get-SumelaRecordFiles -Record $shapeRec }) 'is not an array of strings'
    Set-Text $shapeRec "{`n  `"files`": [`"a.md`", `"b.md`"]`n}`n"
    Same 'a one-line array of strings is read' 'a.md|b.md' (Files $shapeRec)
    $t = New-Install (Join-Path $work 't7b'); $r = Rec $t
    Set-Text (Join-Path $t '.sumela/SKILL_REGISTRY.md') "reg2`n"
    Set-Text $r ("{`n  `"files`": [],`n  `"carry_head`": `"" + (Head $t) + "`",`n  `"carry`": [`"XYZ .sumela/SKILL_REGISTRY.md`"]`n}`n")
    $warn = Get-Warnings { Write-SumelaRecord -Record $r -Version 0.20.0 -State complete -Files '.sumela/VERSION' }
    Same 'an invalid carry entry is not carried' '.sumela/VERSION' (Files $r)
    Has '...and the write says it dropped it' $warn 'dropped an invalid carry entry'

    Write-Host '== a git failure is named, never silent'
    # First a git that fails one command: a script-scope function named git shadows the
    # executable for the library's calls.
    $t = New-Install (Join-Path $work 't11b'); $r = Rec $t
    Set-Text (Join-Path $t '.sumela/migrations-applied/u1') "status: done`n"
    Add-SumelaRecordFiles -Record $r -Path '.sumela/migrations-applied/u1'
    $savedRec = [IO.File]::ReadAllText($r, $utf8)
    $script:realGit = (Get-Command git -CommandType Application | Select-Object -First 1).Source
    foreach ($cmd in @('status', 'hash-object')) {
        Set-Text $r $savedRec
        $script:failCmd = $cmd
        function script:git {
            $hit = @($args | Where-Object { [string]::Equals([string]$_, $script:failCmd, [StringComparison]::Ordinal) }).Count -gt 0
            if ($hit) { Write-Error "fatal: simulated $($script:failCmd) failure"; $global:LASTEXITCODE = 128; return }
            & $script:realGit @args
        }
        try { $warn = Get-Warnings { Write-SumelaRecord -Record $r -Version 0.20.0 -State complete -Files '.sumela/VERSION' } }
        finally { Remove-Item -LiteralPath 'Function:\git' }
        Same "a failing git ${cmd}: nothing is carried" '.sumela/VERSION' (Files $r)
        Has '...and a warning names git''s reason and the count' $warn "(fatal: simulated $cmd failure); 1 earlier path(s) not carried"
    }
    Same 'the shadow is gone' 'Application' ([string](Get-Command git | Select-Object -First 1).CommandType)
    # Then a git that refuses the whole repository ("dubious ownership").
    $t = New-Install (Join-Path $work 't11'); $r = Rec $t
    Set-Text (Join-Path $t '.sumela/migrations-applied/upgrade-01@0.20.0') "status: done`n"
    Add-SumelaRecordFiles -Record $r -Path '.sumela/migrations-applied/upgrade-01@0.20.0'
    $env:GIT_TEST_ASSUME_DIFFERENT_OWNER = '1'
    $env:GIT_CONFIG_GLOBAL = '/dev/null'
    $env:GIT_CONFIG_NOSYSTEM = '1'
    try {
        $ErrorActionPreference = 'Continue'
        & git -C $t rev-parse --git-dir *> $null
        $refused = $LASTEXITCODE -ne 0
        $ErrorActionPreference = 'Stop'
        if (-not $refused) {
            Skip 'this git does not refuse a repository owned by another user (git 2.35.2 or later does)'
        } else {
            $warn = Get-Warnings { Write-SumelaRecord -Record $r -Version 0.20.0 -State complete -Files '.sumela/VERSION' }
            Same '...nothing is carried' '.sumela/VERSION' (Files $r)
            Has '...and a warning says so' $warn 'cannot read the git state of'
            Has '...counting what was not carried' $warn '1 earlier path(s) not carried'
            if ($warn.Contains('git gave no reason')) { Bad "...with git's reason ($warn)" } else { Ok "...with git's reason" }
            $warn = Get-Warnings { Add-SumelaRecordFiles -Record $r -Path '.sumela/x.md' }
            Same 'add under a git failure still records the path' '.sumela/VERSION|.sumela/x.md' (Files $r)
            Has '...and says the next write will not carry it' $warn 'the next write will not carry them'
            $warn = Get-Warnings { Write-SumelaRecord -Record $r -Version 0.20.1 -State partial -Files '.sumela/VERSION' }
            Same 'a partial write under a git failure has no carry list' 'True' ([string]($null -eq (Get-SumelaRecordValue -Key carry -Record $r)))
            Has '...and it says the completing write will not carry its files' $warn 'will not carry its files'
        }
    } finally {
        foreach ($n in @('GIT_TEST_ASSUME_DIFFERENT_OWNER', 'GIT_CONFIG_GLOBAL', 'GIT_CONFIG_NOSYSTEM')) { [Environment]::SetEnvironmentVariable($n, [NullString]::Value) }
        $ErrorActionPreference = 'Stop'
    }

    Write-Host '== byte order and comparison under the tr-TR culture'
    $order = & {
        $prevCulture = [Threading.Thread]::CurrentThread.CurrentCulture
        try {
            [Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::GetCultureInfo('tr-TR')
            $tr = Join-Path $work 'tr.json'
            Add-SumelaRecordFiles -Record $tr -Path @(([string][char]0x0131 + '.md'), 'i.md', ([string][char]0x0130 + '.md'), 'I.md', 'i.md') 3>$null
            (@(Get-SumelaRecordFiles -Record $tr)) -join '|'
        } finally { [Threading.Thread]::CurrentThread.CurrentCulture = $prevCulture }
    }
    Same 'I < i < (dotted capital I) < (dotless i), once each' ('I.md|i.md|' + [char]0x0130 + '.md|' + [char]0x0131 + '.md') $order
    $softRec = Join-Path $work 'soft.json'
    $soft = 'a' + [char]0x00AD + '.md'
    # The re-read checks every requested path, so a linguistic dedupe fails the add (code 1).
    Same 'adding two paths that differ only by a soft hyphen (U+00AD) succeeds' 0 (Invoke-Coded { Add-SumelaRecordFiles -Record $softRec -Path @('a.md', $soft, 'b.md') })
    Same '...and they stay two paths, in byte order' ('a.md|' + $soft + '|b.md') (Files $softRec)
    Same 'GIT_DIR stays unset after the calls' 'True' ([string]($null -eq [Environment]::GetEnvironmentVariable('GIT_DIR')))

    Write-Host '== the bash twin writes the same bytes'
    $bash = Find-Bash
    if (-not $bash) {
        Skip 'no bash (Git Bash on Windows)'
    } else {
        $tpl = New-Install (Join-Path $work 'tpl')
        Set-Text (Join-Path $tpl '.sumela/migrations-applied/upgrade-01@0.20.0') "status: done`n"
        Set-Text (Join-Path $tpl '.sumela/rules/a.md') "a2`n"     # what the partial pass applied
        Set-Text (Join-Path $tpl 'scripts/b.sh') "b2`n"
        $B = Join-Path $work 'b'; $P = Join-Path $work 'p'
        Copy-Item -LiteralPath $tpl -Destination $B -Recurse -Force
        Copy-Item -LiteralPath $tpl -Destination $P -Recurse -Force
        $script:step = 0
        function Test-Parity([string]$label, [string]$shCode, [scriptblock]$psCode) {
            $script:step++
            $drv = Join-Path $work ("step$($script:step).sh")
            [IO.File]::WriteAllText($drv, ". `"`$1`"`ncd `"`$2`" || exit 99`n" + $shCode + "`n", $utf8)
            # (PowerShell names are case-insensitive: the exit codes and record paths need distinct names.)
            $ErrorActionPreference = 'Continue'
            & $bash $drv.Replace('\', '/') $libSh.Replace('\', '/') $B.Replace('\', '/') 2>$null | Out-Null
            $codeBash = $LASTEXITCODE
            $ErrorActionPreference = 'Stop'
            Push-Location -LiteralPath $P
            try { $codePs = Invoke-Coded $psCode } finally { Pop-Location }
            if ($codeBash -ne $codePs) { Bad "step $($script:step) ($label): exit codes differ (bash $codeBash, PowerShell $codePs)"; return }
            $recBash = Rec $B; $recPs = Rec $P
            if ([string]::Equals((Get-Masked $recBash), (Get-Masked $recPs), [StringComparison]::Ordinal) -and
                [string]::Equals((Get-Head $recBash), (Get-Head $recPs), [StringComparison]::Ordinal)) { Ok "step $($script:step) ($label): exit $codeBash, same bytes" }
            else { Bad "step $($script:step) ($label): the records differ"; Write-Host (Get-Masked $recBash); Write-Host (Get-Masked $recPs) }
        }
        $uniPath = '.sumela/skills/' + [char]0x00F6 + ' ' + [char]0x015F + '/SKILL.md'
        Test-Parity 'add to a missing record' 'sumela_record_add_files .sumela/migrations-applied/upgrade-01@0.20.0' { Add-SumelaRecordFiles -Path '.sumela/migrations-applied/upgrade-01@0.20.0' }
        Test-Parity 'add non-ASCII, spaces and a case pair' ("sumela_record_add_files `"$uniPath`" .sumela/skills/a.md .sumela/skills/A.md") { Add-SumelaRecordFiles -Path @($uniPath, '.sumela/skills/a.md', '.sumela/skills/A.md') }
        Test-Parity 'add two paths that differ only by a soft hyphen' 'sumela_record_add_files .sumela/skills/sh.md "$(printf ''.sumela/skills/s\302\255h.md'')"' { Add-SumelaRecordFiles -Path @('.sumela/skills/sh.md', ('.sumela/skills/s' + [char]0xAD + 'h.md')) }
        Test-Parity 'partial write with every array' 'sumela_record_write 0.19.0 partial --base-version 0.19.0 --upstream-commit 0a1b --files "$(printf ''.sumela/rules/a.md\nscripts/b.sh'')" --merged .sumela/skills/m.md --kept "$(printf ''.sumela/skills/k.md\tfork'')"' { Write-SumelaRecord -Version 0.19.0 -State partial -BaseVersion 0.19.0 -UpstreamCommit 0a1b -Files @('.sumela/rules/a.md', 'scripts/b.sh') -Merged '.sumela/skills/m.md' -Kept ".sumela/skills/k.md${TAB}fork" }
        Test-Parity 'complete: a carried path classified anew' 'sumela_record_write 0.20.0 complete --theirs-over-fork .sumela/skills/t.md --kept "$(printf ''.sumela/rules/a.md\tdeclined'')"' { Write-SumelaRecord -Version 0.20.0 -State complete -TheirsOverFork '.sumela/skills/t.md' -Kept ".sumela/rules/a.md${TAB}declined" }
        Test-Parity 'a post-update add' 'sumela_record_add_files .sumela/SKILL_REGISTRY.md' { Add-SumelaRecordFiles -Path '.sumela/SKILL_REGISTRY.md' }
        foreach ($x in @($B, $P)) {
            Commit-All $x 'upgrade to v0.20.0'
            Set-Text (Join-Path $x '.sumela/migrations-applied/upgrade-01@0.20.1') "status: done`n"
            Set-Text (Join-Path $x '.sumela/SKILL_REGISTRY.md') "reg + HAND-LOOSENED ENTRY`n"   # recorded at the old HEAD: never carried
        }
        Same 'the fixed commit dates give both fixtures one HEAD' (Head $B) (Head $P)
        Test-Parity 'the next run''s ledger' 'sumela_record_add_files .sumela/migrations-applied/upgrade-01@0.20.1' { Add-SumelaRecordFiles -Path '.sumela/migrations-applied/upgrade-01@0.20.1' }
        Test-Parity 'the next run''s write' 'sumela_record_write 0.20.1 complete --files scripts/b.sh' { Write-SumelaRecord -Version 0.20.1 -State complete -Files 'scripts/b.sh' }
        Same '...carries the ledger, not the hand-edited registry' '.sumela/migrations-applied/upgrade-01@0.20.1|scripts/b.sh' (Files (Rec $P))
        foreach ($x in @($B, $P)) { Set-Text (Join-Path $x 'scripts/p.sh') "applied`n" }
        Test-Parity 'a partial write lists its files in carry' 'sumela_record_write 0.20.1 partial --files scripts/p.sh' { Write-SumelaRecord -Version 0.20.1 -State partial -Files 'scripts/p.sh' }
        foreach ($x in @($B, $P)) { Set-Text (Join-Path $x 'scripts/p.sh') "applied + hand edit`n" }
        Test-Parity 'completing after a hand edit does not carry the edited file' 'sumela_record_write 0.20.2 complete --upstream-commit abc' { Write-SumelaRecord -Version 0.20.2 -State complete -UpstreamCommit 'abc' }
        Test-Parity 'refused: one path in two classes' 'sumela_record_write 0.20.1 complete --files c.md --merged c.md' { Write-SumelaRecord -Version 0.20.1 -State complete -Files 'c.md' -Merged 'c.md' }
        foreach ($x in @($B, $P)) {
            [IO.File]::WriteAllBytes((Rec $x), [byte[]](0xEF, 0xBB, 0xBF) + $utf8.GetBytes("{`n  `"version`": `"0.19.0`",`n  `"pending_rerun`": false,`n  `"files`": [`n`n  ]`n}"))
        }
        Test-Parity 'add to v0.19''s BOM record' 'sumela_record_add_files b.md' { Add-SumelaRecordFiles -Path 'b.md' }
        foreach ($x in @($B, $P)) { Set-Text (Rec $x) "{`n  `"files`": [`n    `"a.md`",`n  `"oops`"`n}`n" }
        Test-Parity 'refused: add to an unreadable record' 'sumela_record_add_files b.md' { Add-SumelaRecordFiles -Path 'b.md' }
        foreach ($x in @($B, $P)) { Set-Text (Rec $x) "{`n  `"version`": `"0.20.0`",`n  `"files`": `"a.md`"`n}`n" }
        Test-Parity 'refused: add to a record whose files is a string' 'sumela_record_add_files b.md' { Add-SumelaRecordFiles -Path 'b.md' }
    }
} finally {
    foreach ($n in $envNames) {
        if ($null -eq $savedEnv[$n]) { [Environment]::SetEnvironmentVariable($n, [NullString]::Value) }
        else { [Environment]::SetEnvironmentVariable($n, [string]$savedEnv[$n]) }
    }
    try { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction Stop } catch { Write-Host "  (could not remove $work)" }
}

Write-Host ''
Write-Host "  $($script:pass) passed, $($script:fail) failed  (PowerShell $($PSVersionTable.PSVersion))"
if ($script:fail -gt 0) { exit 1 }
exit 0
