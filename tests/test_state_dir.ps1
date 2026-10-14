# tests/test_state_dir.ps1 - the per-developer state directory, PowerShell twin (R1-03).
#
# The Windows-native half of tests/test_state_dir.sh. Get-SumelaStateDir must print
# %LOCALAPPDATA%\sumela\<key> on Windows (the XDG path elsewhere) with the key bash and Python
# compute: the first 16 hex characters of sha256("<main checkout>/<install prefix>"), the prefix
# taken from the install root [RU-M6]. Runs under Windows PowerShell 5.1 and pwsh 7, and under
# the tr-TR culture (the CI runner sets it); bash (Git Bash on Windows, never WSL) and Python are
# used when present, else SKIP.
#
# Run:  pwsh -NoProfile -File tests/test_state_dir.ps1   (or: powershell -NoProfile -File ...)
# Exit 0 = all assertions passed, 1 = a failure (printed above).

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repoRoot = Split-Path -Parent $PSScriptRoot
$libPs = Join-Path $repoRoot 'scripts/lib/sumela-state.ps1'
$libSh = Join-Path $repoRoot 'scripts/lib/sumela-state.sh'
. $libPs

$script:pass = 0
$script:fail = 0
function Ok([string]$m) { Write-Host "  PASS  $m"; $script:pass++ }
function Bad([string]$m) { Write-Host "  FAIL  $m"; $script:fail++ }
function Skip([string]$m) { Write-Host "  SKIP  $m" }
function Same([string]$label, $expected, $got) {
    # Ordinal: -ceq compares linguistically and ignores characters such as U+00AD.
    if ([string]::Equals([string]$expected, [string]$got, [StringComparison]::Ordinal)) { Ok $label } else { Bad "$label (expected '$expected', got '$got')" }
}
function Has([string]$label, [string]$text, [string]$want) {
    if ($text.IndexOf($want, [StringComparison]::Ordinal) -ge 0) { Ok $label } else { Bad "$label (wanted '$want' in '$text')" }
}
function Get-Warnings([scriptblock]$block) {
    # The warnings a block writes, one per line, and its output discarded.
    $w = & { & $block | Out-Null } 3>&1 | ForEach-Object { [string]$_ }
    return ((@($w)) -join "`n")
}
function tgit {
    # git for fixtures; stderr is progress chatter, not an error
    $ErrorActionPreference = 'Continue'
    $out = & git @args 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git $($args -join ' ') failed: $out" }
}
$utf8 = New-Object System.Text.UTF8Encoding $false
$onWindows = $env:OS -ceq 'Windows_NT'

function New-Fixture([string]$dir, [string[]]$installs) {
    [void][IO.Directory]::CreateDirectory($dir)
    tgit -C $dir init -q -b main
    tgit -C $dir config user.email t@example.com
    tgit -C $dir config user.name Test
    foreach ($i in $installs) {
        $at = $dir
        if ($i -cne '.') { $at = Join-Path $dir $i }
        [void][IO.Directory]::CreateDirectory((Join-Path $at '.sumela'))
        [void][IO.Directory]::CreateDirectory((Join-Path $at 'src/deep'))
        [IO.File]::WriteAllText((Join-Path $at '.sumela/VERSION'), "0.20.0`n", $utf8)
        [IO.File]::WriteAllText((Join-Path $at 'src/deep/f.txt'), "x`n", $utf8)
    }
    tgit -C $dir add -A
    tgit -C $dir commit -qm init
}
function Get-FormulaKey([string]$root) {
    # The contract, written out independently of the library.
    $ErrorActionPreference = 'Continue'
    $prev = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = $utf8
        $common = [string](& git -C $root rev-parse --path-format=absolute --git-common-dir)
        $prefix = [string](& git -C $root rev-parse --show-prefix)
    } finally { [Console]::OutputEncoding = $prev }
    if ($common.EndsWith('/.git', [StringComparison]::Ordinal)) { $common = $common.Substring(0, $common.Length - 5) }
    if ($prefix.EndsWith('/', [StringComparison]::Ordinal)) { $prefix = $prefix.Substring(0, $prefix.Length - 1) }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $h = $sha.ComputeHash($utf8.GetBytes($common + '/' + $prefix)) } finally { $sha.Dispose() }
    return ([BitConverter]::ToString($h).Replace('-', '')).ToLowerInvariant().Substring(0, 16)
}
function Get-KeyFrom([string]$dir) {
    Push-Location -LiteralPath $dir
    try { $d = Get-SumelaStateDir } finally { Pop-Location }
    if (-not $d) { return '' }
    return (Split-Path -Leaf $d)
}
function Find-Bash {
    # Git Bash on Windows (never bash from PATH: that may be WSL); bash from PATH elsewhere.
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
function Find-Python {
    $ErrorActionPreference = 'Continue'
    foreach ($cand in @(@('python3'), @('py', '-3'), @('python'))) {
        $exe = $cand[0]
        if (-not (Get-Command $exe -CommandType Application -ErrorAction SilentlyContinue)) { continue }
        $rest = @()
        if ($cand.Count -gt 1) { $rest = @($cand[1]) }
        $v = & $exe @rest -c 'import sys; print(sys.version_info[0])' 2>$null
        if ($LASTEXITCODE -eq 0 -and [string]$v -ceq '3') { return ,$cand }
    }
    return $null
}

$work = Join-Path ([IO.Path]::GetTempPath()) ('sumela-state-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($work)
$work = (Resolve-Path -LiteralPath $work).ProviderPath
$savedEnv = @{}
foreach ($n in @('XDG_STATE_HOME', 'LOCALAPPDATA', 'GIT_DIR', 'GIT_WORK_TREE')) { $savedEnv[$n] = [Environment]::GetEnvironmentVariable($n) }
try {
    foreach ($n in @('GIT_DIR', 'GIT_WORK_TREE')) { [Environment]::SetEnvironmentVariable($n, [NullString]::Value) }
    if ($onWindows) {
        $env:LOCALAPPDATA = Join-Path $work 'localappdata'
        [void][IO.Directory]::CreateDirectory($env:LOCALAPPDATA)
        $base = Join-Path $env:LOCALAPPDATA 'sumela'
    } else {
        $env:XDG_STATE_HOME = Join-Path $work 'state'
        $base = $env:XDG_STATE_HOME + '/sumela'
    }
    $main = Join-Path $work 'main'; New-Fixture $main @('.')
    $wt = Join-Path $work 'wt'; tgit -C $main worktree add -q -b topic $wt
    $mono = Join-Path $work 'mono'; New-Fixture $mono @('svc/a', 'svc/b')
    $uni = Join-Path $work ([string][char]0x00F6 + ' ' + [char]0x015F + ' dir'); New-Fixture $uni @('.')

    Write-Host '== main checkout and linked worktree share one directory'
    $kMain = Get-KeyFrom $main
    Same 'the key follows the formula' (Get-FormulaKey $main) $kMain
    Same 'a linked worktree gets the main checkout''s key' $kMain (Get-KeyFrom $wt)
    Push-Location -LiteralPath $wt
    try { $dWt = Get-SumelaStateDir } finally { Pop-Location }
    if ($onWindows) { Same 'the directory is %LOCALAPPDATA%\sumela\<key>' (Join-Path $base $kMain) $dWt }
    else { Same 'the directory is <XDG_STATE_HOME>/sumela/<key>' ($base + '/' + $kMain) $dWt }
    if ($kMain -cmatch '^[0-9a-f]{16}\z') { Ok 'the key is 16 lowercase hex characters' } else { Bad "the key is 16 lowercase hex characters (got '$kMain')" }

    Write-Host '== monorepo installs are distinct; the prefix comes from the install root'
    $kA = Get-KeyFrom (Join-Path $mono 'svc/a'); $kB = Get-KeyFrom (Join-Path $mono 'svc/b')
    if ($kA -and $kB -and ($kA -cne $kB)) { Ok 'two installs in one repository get two directories' } else { Bad "two installs get two directories ($kA / $kB)" }
    Same 'an install in a subdirectory hashes <main>/<prefix>' (Get-FormulaKey (Join-Path $mono 'svc/a')) $kA
    Same 'a session in a subdirectory of the install' $kMain (Get-KeyFrom (Join-Path $main 'src/deep'))
    Same 'a session in a subdirectory of a linked worktree' $kMain (Get-KeyFrom (Join-Path $wt 'src/deep'))
    Same 'a session deep inside a monorepo install keeps its prefix' $kA (Get-KeyFrom (Join-Path $mono 'svc/a/src/deep'))
    $viaRoot = Split-Path -Leaf (Get-SumelaStateDir -Root $main)
    Same '-Root names the install from anywhere' $kMain $viaRoot

    Write-Host '== no install root, no work tree'
    $plain = Join-Path $work 'plain/sub'; [void][IO.Directory]::CreateDirectory($plain)
    Push-Location -LiteralPath $plain
    try { $none = Get-SumelaStateDir } finally { Pop-Location }
    Same 'no .sumela/ above the location: $null' '' ([string]$none)
    $nogit = Join-Path $work 'nogit'; [void][IO.Directory]::CreateDirectory((Join-Path $nogit '.sumela'))
    Same 'an install outside any git work tree: $null' '' ([string](Get-SumelaStateDir -Root $nogit 3>$null))
    Has '...and a warning names git''s reason' (Get-Warnings { Get-SumelaStateDir -Root $nogit }) 'git cannot read the repository at'
    Same 'no install root is not warned about (callers probe)' '' (Get-Warnings { Push-Location -LiteralPath $plain; try { Get-SumelaStateDir } finally { Pop-Location } })

    Write-Host '== a repository git refuses (dubious ownership) is named, never silent'
    $savedOwner = @{}
    foreach ($n in @('GIT_TEST_ASSUME_DIFFERENT_OWNER', 'GIT_CONFIG_GLOBAL', 'GIT_CONFIG_NOSYSTEM')) { $savedOwner[$n] = [Environment]::GetEnvironmentVariable($n) }
    try {
        $env:GIT_TEST_ASSUME_DIFFERENT_OWNER = '1'
        $env:GIT_CONFIG_GLOBAL = '/dev/null'
        $env:GIT_CONFIG_NOSYSTEM = '1'
        $ErrorActionPreference = 'Continue'
        & git -C $main rev-parse --git-dir *> $null
        $refused = $LASTEXITCODE -ne 0
        $ErrorActionPreference = 'Stop'
        if (-not $refused) {
            Skip 'this git does not refuse a repository owned by another user (git 2.35.2 or later does)'
        } else {
            Same 'Get-SumelaStateDir: $null' '' ([string](Get-SumelaStateDir -Root $main 3>$null))
            $warn = Get-Warnings { Get-SumelaStateDir -Root $main }
            Has '...and a warning says git cannot read the repository' $warn 'git cannot read the repository at'
            if ($warn.Contains('gave no reason')) { Bad "...with git's reason ($warn)" } else { Ok "...with git's reason" }
            try { Write-SumelaStateFile -Root $main -Name 'x.txt' -Content 'x' 3>$null; Bad 'Write-SumelaStateFile refuses to write' }
            catch { Ok 'Write-SumelaStateFile refuses to write' }
        }
    } finally {
        foreach ($n in $savedOwner.Keys) {
            if ($null -eq $savedOwner[$n]) { [Environment]::SetEnvironmentVariable($n, [NullString]::Value) }
            else { [Environment]::SetEnvironmentVariable($n, [string]$savedOwner[$n]) }
        }
        $ErrorActionPreference = 'Stop'
    }

    Write-Host '== a hook''s GIT_DIR neither changes the key nor survives the call'
    $env:GIT_DIR = Join-Path $mono '.git'
    Push-Location -LiteralPath $mono
    try { $hooked = Get-SumelaStateDir -Root (Join-Path $mono 'svc/a') } finally { Pop-Location }
    Same 'GIT_DIR from a hook does not change a monorepo install''s key' $kA (Split-Path -Leaf ([string]$hooked))
    Same 'GIT_DIR is restored after the call' (Join-Path $mono '.git') $env:GIT_DIR
    [Environment]::SetEnvironmentVariable('GIT_DIR', [NullString]::Value)
    Same 'an unset variable stays unset (not set to empty)' 'True' ([string]($null -eq [Environment]::GetEnvironmentVariable('GIT_DIR')))
    Get-SumelaStateDir -Root $main | Out-Null
    Same '...also after a call' 'True' ([string]($null -eq [Environment]::GetEnvironmentVariable('GIT_DIR')))

    Write-Host '== the key under the tr-TR culture'
    $trKey = & {
        $prevCulture = [Threading.Thread]::CurrentThread.CurrentCulture
        try {
            [Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::GetCultureInfo('tr-TR')
            Split-Path -Leaf (Get-SumelaStateDir -Root $uni)
        } finally { [Threading.Thread]::CurrentThread.CurrentCulture = $prevCulture }
    }
    Same 'tr-TR changes nothing (non-ASCII path)' (Get-FormulaKey $uni) $trKey

    Write-Host '== -Create and Write-SumelaStateFile'
    $d = Get-SumelaStateDir -Create -Root $main
    if ([IO.Directory]::Exists($d)) { Ok '-Create makes the directory' } else { Bad '-Create makes the directory' }
    Write-SumelaStateFile -Root $main -Name 'note.txt' -Content ("one " + [char]0x00F6 + "`n")
    Write-SumelaStateFile -Root $wt -Name 'note.txt' -Content ("two " + [char]0x00F6 + "`n")
    $bytes = [IO.File]::ReadAllBytes((Join-Path $d 'note.txt'))
    Same 'a replace from a worktree writes the shared file, UTF-8 without BOM' ('74-77-6F-20-C3-B6-0A') ([BitConverter]::ToString($bytes))
    Write-SumelaStateFile -Root $main -Name 'log' -Content "a`n" -Append
    Write-SumelaStateFile -Root $main -Name 'log' -Content "b`n" -Append
    Same '-Append appends' "a`nb`n" ([IO.File]::ReadAllText((Join-Path $d 'log'), $utf8))
    $leftovers = @(Get-ChildItem -LiteralPath $d -Force | Where-Object { $_.Name -clike '*sumela-tmp*' })
    Same 'no temporary file is left behind' 0 $leftovers.Count
    if ($onWindows) {
        Skip 'POSIX modes (Windows: %LOCALAPPDATA% is per-user)'
    } else {
        $modeType = 'System.IO.UnixFileMode' -as [type]
        if ($null -eq $modeType) {
            Skip 'POSIX modes (this pwsh has no UnixFileMode API)'
        } else {
            Same 'the directory is 0700' 448 ([int][IO.File]::GetUnixFileMode($d))
            Same 'a written file is 0600' 384 ([int][IO.File]::GetUnixFileMode((Join-Path $d 'note.txt')))
            Same 'an appended file is 0600' 384 ([int][IO.File]::GetUnixFileMode((Join-Path $d 'log')))
        }
    }
    # "note`n": in .NET a pattern ending in $ also matches before a final line feed.
    foreach ($badName in @('../x', 'a/b', '.', '..', '', 'a b', ([string][char]0x00F6 + '.txt'), "note`n", "note`r", ('no' + [char]0xAD + 'te'))) {
        $shown = $badName.Replace("`n", '\n').Replace("`r", '\r')
        try { Write-SumelaStateFile -Root $main -Name $badName -Content 'x'; Bad "an invalid name is refused: '$shown'" }
        catch { Ok "an invalid name is refused: '$shown'" }
    }
    $names = @(Get-ChildItem -LiteralPath $d -Force | ForEach-Object { $_.Name } | Where-Object { $_.Contains("`n") -or $_.Contains("`r") })
    Same 'no file name with a line break was created' 0 $names.Count

    Write-Host '== bash and Python compute the same key'
    $bash = Find-Bash
    $python = Find-Python
    $driverSh = Join-Path $work 'key.sh'
    [IO.File]::WriteAllText($driverSh, ". `"`$1`"`ncd `"`$2`" && d=`"`$(sumela_state_dir)`" && basename `"`$d`"`n", $utf8)
    $driverPy = Join-Path $work 'key.py'
    $pySource = @'
import hashlib, os, subprocess, sys
root = sys.argv[1]
env = {k: v for k, v in os.environ.items()
       if k not in ("GIT_DIR", "GIT_WORK_TREE", "GIT_COMMON_DIR", "GIT_INDEX_FILE", "GIT_PREFIX")}
def git(*args):
    out = subprocess.run(["git", "-C", root, *args], capture_output=True, check=True, env=env).stdout
    return out.decode("utf-8").rstrip("\r\n")
common = git("rev-parse", "--path-format=absolute", "--git-common-dir")
prefix = git("rev-parse", "--show-prefix")
if common.endswith("/.git"):
    common = common[:-len("/.git")]
if prefix.endswith("/"):
    prefix = prefix[:-1]
print(hashlib.sha256((common + "/" + prefix).encode("utf-8")).hexdigest()[:16])
'@
    [IO.File]::WriteAllText($driverPy, $pySource.Replace("`r`n", "`n"), $utf8)   # a CRLF checkout must not reach Python as CRLF
    $cases = @($main, (Join-Path $wt 'src/deep'), (Join-Path $mono 'svc/a/src/deep'), (Join-Path $uni 'src'))
    foreach ($c in $cases) {
        $label = $c.Substring($work.Length + 1)
        $kPs = Get-KeyFrom $c
        $prevEnc = [Console]::OutputEncoding
        [Console]::OutputEncoding = $utf8
        try {
            if ($bash) {
                $ErrorActionPreference = 'Continue'
                $kSh = [string](& $bash $driverSh.Replace('\', '/') $libSh.Replace('\', '/') $c.Replace('\', '/') 2>$null)
                $ErrorActionPreference = 'Stop'
                Same "bash computes PowerShell's key ($label)" $kPs $kSh
            } else { Skip "bash key ($label): no bash" }
            if ($python) {
                $rootOf = $c
                while (-not [IO.Directory]::Exists((Join-Path $rootOf '.sumela'))) { $rootOf = [IO.Path]::GetDirectoryName($rootOf) }
                $exe = $python[0]
                $pyArgs = @()
                if ($python.Count -gt 1) { $pyArgs += $python[1] }
                $pyArgs += @('-I', $driverPy, $rootOf)
                $ErrorActionPreference = 'Continue'
                $kPy = [string](& $exe @pyArgs 2>$null)
                $ErrorActionPreference = 'Stop'
                Same "a Python reference computes PowerShell's key ($label)" $kPs $kPy
            } else { Skip "Python key ($label): no Python 3" }
        } finally { [Console]::OutputEncoding = $prevEnc }
    }
} finally {
    foreach ($n in $savedEnv.Keys) {
        if ($null -eq $savedEnv[$n]) { [Environment]::SetEnvironmentVariable($n, [NullString]::Value) }
        else { [Environment]::SetEnvironmentVariable($n, [string]$savedEnv[$n]) }
    }
    try { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction Stop } catch { Write-Host "  (could not remove $work)" }
}

Write-Host ''
Write-Host "  $($script:pass) passed, $($script:fail) failed  (PowerShell $($PSVersionTable.PSVersion))"
if ($script:fail -gt 0) { exit 1 }
exit 0
