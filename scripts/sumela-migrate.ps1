<#
.SYNOPSIS
    Run a SumelaOS release's migration steps, in order (v0.20.0+). The PowerShell twin of
    scripts/sumela-migrate.sh, which holds the full contract; scripts/sumela-migrations/README.md
    is the agent procedure and the notes format.

.DESCRIPTION
    Usage (from inside the project's checkout; the runner may live in the release clone):
      powershell -NoProfile -File <clone>/scripts/sumela-migrate.ps1 plan -Source <clone> [-Scope repo|developer] [-TrustOrigin <url>]
      ... plan [-Scope repo|developer]                       resume, or the developer steps
      ... set <key>=<value>...                               prefix, base, branch, worktree
      ... show <id>
      ... run <id> [-ConfirmedByUser]
      ... verify <id>
      ... record <id> done|declined|not-applicable
      ... rollback <id> -ConfirmedByUser
      ... status [-Scope repo|developer]
      ... lint [<notes.md>...]
    -TrustOrigin <url> (plan -Source only) names a release clone's origin the user confirmed,
    which is not the project's upstream. -AllowUntagged (maintainer tests only, and only with
    SUMELA_MIGRATE_ALLOW_UNTAGGED=1 in the environment) accepts a clone that is not at a release
    tag. The bash runner's forms (--source, --scope, --trust-origin, --confirmed-by-user,
    --allow-untagged) work too.

    The release clone is trusted, the selection made and every step guarded exactly as the bash
    runner does it (see its header): a clean checkout with a plain path at an annotated release
    tag of the project's upstream (or the -TrustOrigin URL), which that URL confirms through git
    ls-remote run outside every repository; none of the clone's own git configuration trusted;
    notes read from the HEAD blobs, regular files only; requires met only by steps recorded
    done; repo steps run only in the upgrade worktree, on a branch that tracks nothing but its
    own remote branch; a consent other than none or confirm needs -ConfirmedByUser, run: - steps
    included; read-only lines (consent: none, the pre-satisfied gate) only in plain ASCII words;
    rollback removes the ledger entry first and restores it when the line fails; plan removes
    the state once the merge reaches the main checkout.

    A step uses its run.ps1 / verify.ps1 / rollback.ps1 when it has one and PowerShell scripts
    may run; otherwise its bash line runs through Git Bash, found at
    <git --exec-path>/../../../bin/bash.exe or .../usr/bin/bash.exe (never bash from PATH on
    Windows, which may be WSL). Scripts count as blocked when PSExecutionPolicyPreference (which
    a step's process inherits) or, on Windows, the effective execution policy is Restricted or
    AllSigned [RU-I13]. A PowerShell line that calls `powershell` on a host without Windows
    PowerShell runs it with this host instead.

    The state file, the ledgers and every output line are the bash runner's, byte for byte.

.NOTES
    Exit 0 ok; 1 error; 2 consent required; 3 verify failed; 4 invalid notes.
    Windows PowerShell 5.1 and pwsh 7; invariant culture; ordinal comparisons; files read and
    written as UTF-8 without BOM through [IO.File], LF line ends; git blobs reach disk byte for
    byte from git cat-file through a .NET stream, never through a PowerShell pipeline. Never
    -ExecutionPolicy Bypass.
    Keep this file ASCII-only: Windows PowerShell 5.1 reads a script without a BOM as ANSI.
#>
param(
    [Parameter(Position = 0)][string]$Command,
    [Parameter(Position = 1, ValueFromRemainingArguments = $true)][string[]]$Rest,
    [string]$Scope,
    [string]$Source,
    [string]$TrustOrigin,
    [switch]$ConfirmedByUser,
    [switch]$AllowUntagged
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$invariant = [Globalization.CultureInfo]::InvariantCulture
[Threading.Thread]::CurrentThread.CurrentCulture = $invariant
[Threading.Thread]::CurrentThread.CurrentUICulture = $invariant
$script:utf8 = New-Object System.Text.UTF8Encoding $false
try { [Console]::OutputEncoding = $script:utf8 } catch { }
$ord = [StringComparison]::Ordinal
$ordI = [StringComparison]::OrdinalIgnoreCase

$script:prog = 'sumela-migrate'
$script:scriptDir = $PSScriptRoot
$script:notesRel = 'scripts/sumela-migrations'
# The framework's own repository: the upstream when .sumela/upstream.conf names none.
$script:defaultUpstream = 'https://github.com/tolgakisaogullari/SumelaOS.git'
$script:stateKeys = @('from', 'target', 'tag', 'commit', 'clone', 'url', 'prefix', 'base', 'branch', 'worktree', 'procedural')
$script:phases = @('pre-update', 'update', 'post-update', 'finalize', 'quiet-window', 'first-session')
$script:onWindows = [string]::Equals([string]$env:OS, 'Windows_NT', $ord)
# The characters a word of a read-only line may hold (see Get-Words), and the shapes, as the lint names them
$script:wordChars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_./:=@%+-'
$script:roSh = 'bash <script.sh> [--source <dir>] with one of --plan, --plan-check, --status, --check, --verify-applied or --has-baseline <name>; bash <path>/validate-structure.sh; or git [-C <dir>] config [--local] --get <key>, in plain words and whole double-quoted strings of [A-Za-z0-9_./:=@%+-]'
$script:roPs = 'powershell -NoProfile -File <script.ps1> [-SourceDir <dir>] with one of -Plan, -PlanCheck, -Status, -Check, -VerifyApplied or -HasBaseline <name>; or git [-C <dir>] config [--local] --get <key>, in plain words and whole double-quoted strings of [A-Za-z0-9_./:=@%+-]'

function Eq([string]$a, [string]$b) { return [string]::Equals($a, $b, [StringComparison]::Ordinal) }
function EqI([string]$a, [string]$b) { return [string]::Equals($a, $b, [StringComparison]::OrdinalIgnoreCase) }
# The comma keeps an empty collection from being unrolled into $null on return.
function New-Dict { return ,(New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::Ordinal)) }
function New-List { return ,(New-Object System.Collections.Generic.List[object]) }
function Out-Line([string]$s) { [Console]::Out.WriteLine($s) }
function Say([string]$s) { [Console]::Out.WriteLine($script:prog + ': ' + $s) }
function Warn([string]$s) { [Console]::Error.WriteLine($script:prog + ': ' + $s) }
function Stop-Mig([int]$code, [string]$msg) { if ($msg) { Warn $msg }; exit $code }
function Die([string]$msg) { Stop-Mig 1 $msg }
function Slash([string]$p) { if ($null -eq $p) { return '' }; return $p.Replace('\', '/') }
function Clear-ReadOnlyTree([IO.DirectoryInfo]$dir) {
    # Every entry under <dir> loses the read-only attribute; a link or junction is neither
    # changed nor followed.
    $ro = [int][IO.FileAttributes]::ReadOnly; $rp = [int][IO.FileAttributes]::ReparsePoint
    foreach ($e in $dir.GetFileSystemInfos()) {
        $a = [int]$e.Attributes
        if (($a -band $rp) -ne 0) { continue }
        if (($a -band $ro) -ne 0) { $e.Attributes = [IO.FileAttributes]($a -bxor $ro) }
        if ($e -is [IO.DirectoryInfo]) { Clear-ReadOnlyTree $e }
    }
}
function Remove-Tree([string]$path) {
    # Deletes a directory tree. Windows will not delete a read-only file (git writes its objects
    # read-only), so every entry loses that attribute first; a file another process still holds
    # gets a few retries. Throws when the tree cannot be removed.
    for ($try = 1; [IO.Directory]::Exists($path); $try++) {
        try {
            $d = New-Object IO.DirectoryInfo $path
            $a = [int]$d.Attributes; $ro = [int][IO.FileAttributes]::ReadOnly
            if (($a -band $ro) -ne 0) { $d.Attributes = [IO.FileAttributes]($a -bxor $ro) }
            Clear-ReadOnlyTree $d
            [IO.Directory]::Delete($path, $true)
        } catch {
            if ($try -ge 5) { throw }
            Start-Sleep -Milliseconds 200
        }
    }
}

function Show-Usage {
    $u = @(
        'usage: sumela-migrate.ps1 <command> [arguments] [options]'
        '  plan [-Scope repo|developer] [-Source <clone> [-TrustOrigin <url>]]   list the pending steps in order'
        '  set <key>=<value>...                                record confirmed values (prefix, base, branch, worktree)'
        '  show <id>                                           print a step, placeholders substituted'
        '  run <id> [-ConfirmedByUser]                         run a step''s command from {ROOT}'
        '  verify <id>                                         exit 0 only when verify exits 0 and expect holds'
        '  record <id> done|declined|not-applicable            write the ledger entry (done re-runs verify first)'
        '  rollback <id> -ConfirmedByUser                      run a step''s rollback line; the step is pending again'
        '  status [-Scope repo|developer]                      print pending_repo=<n> pending_developer=<n>'
        '  lint [<notes.md>...]                                check notes files (default: the shipped ones)'
        'options: -ConfirmedByUser (run, rollback: the user typed the confirmation),'
        '         -TrustOrigin <url> (plan -Source: the user confirmed a clone of <url>, which is not'
        '         the project''s upstream), -AllowUntagged (maintainer tests only, with'
        '         SUMELA_MIGRATE_ALLOW_UNTAGGED=1)'
        'exit: 0 ok; 1 error; 2 consent required; 3 verify failed; 4 invalid notes'
        'See scripts/sumela-migrations/README.md.'
    )
    foreach ($l in $u) { Out-Line $l }
}

# --- Arguments ------------------------------------------------------------------------------
$script:args2 = New-List
$script:confirmed = [bool]$ConfirmedByUser
$script:allowUntagged = [bool]$AllowUntagged
$script:scope = [string]$Scope
$script:source = [string]$Source
$script:trustOrigin = [string]$TrustOrigin
$restItems = @()
if ($null -ne $Rest) { $restItems = @($Rest) }
for ($i = 0; $i -lt $restItems.Count; $i++) {
    $a = [string]$restItems[$i]
    if ((Eq $a '--scope') -or (Eq $a '-Scope')) {
        if ($i + 1 -ge $restItems.Count) { Die '--scope needs repo or developer' }
        $i++; $script:scope = [string]$restItems[$i]
    } elseif ($a.StartsWith('--scope=', $ord)) { $script:scope = $a.Substring(8) }
    elseif ((Eq $a '--source') -or (Eq $a '-Source')) {
        if ($i + 1 -ge $restItems.Count) { Die '--source needs a directory' }
        $i++; $script:source = [string]$restItems[$i]
    } elseif ($a.StartsWith('--source=', $ord)) { $script:source = $a.Substring(9) }
    elseif ((Eq $a '--trust-origin') -or (Eq $a '-TrustOrigin')) {
        if ($i + 1 -ge $restItems.Count) { Die '--trust-origin needs the URL the user confirmed' }
        $i++; $script:trustOrigin = [string]$restItems[$i]
    } elseif ($a.StartsWith('--trust-origin=', $ord)) { $script:trustOrigin = $a.Substring(15) }
    elseif ((Eq $a '--confirmed-by-user') -or (Eq $a '-ConfirmedByUser')) { $script:confirmed = $true }
    elseif ((Eq $a '--allow-untagged') -or (Eq $a '-AllowUntagged')) { $script:allowUntagged = $true }
    elseif ((Eq $a '-h') -or (Eq $a '--help')) { Show-Usage; exit 0 }
    elseif (Eq $a '--') { for ($j = $i + 1; $j -lt $restItems.Count; $j++) { [void]$script:args2.Add([string]$restItems[$j]) }; break }
    elseif ($a.StartsWith('-', $ord) -and $a.Length -gt 1) { Warn "unknown option: $a"; Show-Usage; exit 1 }
    else { [void]$script:args2.Add($a) }
}
if ($script:scope -and -not ((Eq $script:scope 'repo') -or (Eq $script:scope 'developer'))) { Die "--scope must be repo or developer, not '$($script:scope)'" }
$cmd = [string]$Command
if ($cmd.StartsWith('-', $ord) -and ((Eq $cmd '-h') -or (Eq $cmd '--help'))) { Show-Usage; exit 0 }
if ($script:source -and -not (Eq $cmd 'plan')) { Die 'only plan takes --source: the other commands read the release clone that plan --source recorded' }
if ($script:trustOrigin -and ((-not (Eq $cmd 'plan')) -or (-not $script:source))) { Die '--trust-origin goes with plan --source <clone>: it names the clone''s origin the user confirmed' }
if ($script:allowUntagged -and -not $env:SUMELA_MIGRATE_ALLOW_UNTAGGED) { Die '--allow-untagged is for maintainer tests only: it also takes SUMELA_MIGRATE_ALLOW_UNTAGGED=1 in the environment' }
if ($script:source -and -not [IO.Path]::IsPathRooted($script:source)) { $script:source = [IO.Path]::GetFullPath((Join-Path (Get-Location -PSProvider FileSystem).ProviderPath $script:source)) }

$script:work = Join-Path ([IO.Path]::GetTempPath()) ('sumela-migrate-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($script:work)
$script:work = Slash $script:work

# --- git -------------------------------------------------------------------------------------
function Invoke-Native {
    # & <exe> <args> with UTF-8 output; returns ExitCode, Lines (stdout), Err (stderr), CRs dropped.
    param([string]$Exe, [string[]]$ArgList, [switch]$Merge)
    $ErrorActionPreference = 'Continue'
    $all = $null; $code = 1; $failure = $null
    try {
        $all = & $Exe @ArgList 2>&1
        $code = $LASTEXITCODE
    } catch { $code = 127; $failure = $_.Exception.Message }
    $lines = New-Object System.Collections.Generic.List[string]
    $err = New-Object System.Collections.Generic.List[string]
    if ($null -ne $failure) { $err.Add([string]$failure) }
    foreach ($o in @($all)) {
        if ($null -eq $o) { continue }
        $s = ([string]$o).TrimEnd([char]13)
        if (($o -is [System.Management.Automation.ErrorRecord]) -and -not $Merge) { $err.Add($s) } else { $lines.Add($s) }
    }
    return [pscustomobject]@{ ExitCode = $code; Lines = $lines.ToArray(); Err = $err.ToArray() }
}
function Invoke-Git {
    param([string]$Dir, [string[]]$GitArgs)
    $names = @('GIT_DIR', 'GIT_WORK_TREE', 'GIT_COMMON_DIR', 'GIT_INDEX_FILE', 'GIT_PREFIX')
    foreach ($n in $names) { [Environment]::SetEnvironmentVariable($n, [NullString]::Value) }
    $a = @()
    if ($Dir) { $a += @('-C', $Dir) }
    $a += $GitArgs
    return (Invoke-Native -Exe 'git' -ArgList $a)
}
function Get-GitLine {
    # The first stdout line of a git call, or $null when git failed.
    param([string]$Dir, [string[]]$GitArgs)
    $r = Invoke-Git -Dir $Dir -GitArgs $GitArgs
    if ($r.ExitCode -ne 0) { return $null }
    if (@($r.Lines).Count -lt 1) { return '' }
    return [string]$r.Lines[0]
}
# git on the release clone, whose own configuration is not trusted (cgit in the bash runner): no
# fsmonitor hook, no untracked cache, the stat cache checked in full.
$script:cgit = @('-c', 'core.fsmonitor=false', '-c', 'core.untrackedCache=false', '-c', 'core.checkStat=default', '-c', 'core.trustctime=true', '-c', 'core.ignoreStat=false')
function Invoke-CGit { param([string]$Dir, [string[]]$GitArgs) return (Invoke-Git -Dir $Dir -GitArgs ($script:cgit + $GitArgs)) }
function Get-CGitLine { param([string]$Dir, [string[]]$GitArgs) return (Get-GitLine -Dir $Dir -GitArgs ($script:cgit + $GitArgs)) }
function Save-GitBlob([string]$dir, [string]$blob, [string]$path) {
    # git cat-file blob <blob> > <path>, byte for byte (never through a PowerShell pipeline, which
    # would decode and re-encode it); cat-file runs no filter. Returns $true when it worked.
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'git'
    $psi.Arguments = [string]::Join(' ', ($script:cgit + @('cat-file', 'blob', $blob)))
    $psi.WorkingDirectory = $dir
    $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    foreach ($n in @('GIT_DIR', 'GIT_WORK_TREE', 'GIT_COMMON_DIR', 'GIT_INDEX_FILE', 'GIT_PREFIX')) { if ($psi.EnvironmentVariables.ContainsKey($n)) { $psi.EnvironmentVariables.Remove($n) } }
    try { $proc = [Diagnostics.Process]::Start($psi) } catch { Warn "cannot run git: $($_.Exception.Message)"; return $false }
    $errTask = $proc.StandardError.ReadToEndAsync()
    $fs = [IO.File]::Create($path)
    try { $proc.StandardOutput.BaseStream.CopyTo($fs) } finally { $fs.Dispose() }
    $proc.WaitForExit()
    $err = $errTask.Result
    if ($proc.ExitCode -ne 0) { if ($err) { [Console]::Error.Write($err) }; return $false }
    return $true
}

# --- Versions --------------------------------------------------------------------------------
function Get-VKey([string]$v) {
    $v = [regex]::Replace([string]$v, '-rc\.[0-9]+\z', '')
    $p = $v.Split('.')
    $n = @(0, 0, 0)
    for ($i = 0; $i -lt 3; $i++) {
        if ($i -lt $p.Length) { $x = 0; if ([int]::TryParse($p[$i], [Globalization.NumberStyles]::None, $invariant, [ref]$x)) { $n[$i] = $x } }
    }
    return [string]::Format($invariant, '{0:D6}.{1:D6}.{2:D6}', $n[0], $n[1], $n[2])
}
function Compare-Version([string]$a, [string]$b) {
    $c = [string]::CompareOrdinal((Get-VKey $a), (Get-VKey $b))
    if ($c -lt 0) { return -1 }; if ($c -gt 0) { return 1 }; return 0
}
function Test-Version([string]$v) { return ($v -cmatch '^[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?\z') }
function Read-Version([string]$root) {
    $f = Join-Path $root '.sumela/VERSION'
    if (-not [IO.File]::Exists($f)) { return $null }
    return ([IO.File]::ReadAllText($f, $script:utf8) -replace '[ \t\r\n]', '')
}

# --- Notes: parse, check, load ---------------------------------------------------------------
function Read-NotesRows([string[]]$Files) {
    # B/S/E rows, as parse_notes in the bash runner.
    $rows = New-List
    $blk = 0
    foreach ($f in $Files) {
        $text = [IO.File]::ReadAllText($f, $script:utf8)
        $lines = $text.Split([char]10)
        $inb = $false; $bs = 0
        for ($i = 0; $i -lt $lines.Length; $i++) {
            $n = $i + 1
            $l = $lines[$i]
            if ($l.EndsWith([string][char]13, $ord)) { $l = $l.Substring(0, $l.Length - 1) }
            if (($i -eq $lines.Length - 1) -and ($l.Length -eq 0)) { break }
            if (-not $inb) {
                if ($l -cmatch '^```sumela-step[ \t]*\z') {
                    $inb = $true; $blk++; $bs = $n
                    [void]$rows.Add([pscustomobject]@{ Kind = 'B'; File = $f; Line = $n; Block = $blk; Key = ''; Value = ''; Message = '' })
                }
                continue
            }
            if ($l -cmatch '^```[ \t]*\z') { $inb = $false; continue }
            if ($l -cmatch '^[ \t]*(#|\z)') { continue }
            $p = $l.IndexOf(':')
            if ($p -lt 0) { [void]$rows.Add([pscustomobject]@{ Kind = 'E'; File = $f; Line = $n; Block = $blk; Key = ''; Value = ''; Message = "not a key: value line: $l" }); continue }
            $key = $l.Substring(0, $p)
            $val = $l.Substring($p + 1).TrimStart([char[]]@([char]32, [char]9)).TrimEnd([char[]]@([char]32, [char]9))
            if (($key.Length -eq 0) -or ($key -cmatch '[ \t]')) { [void]$rows.Add([pscustomobject]@{ Kind = 'E'; File = $f; Line = $n; Block = $blk; Key = ''; Value = ''; Message = "not a key: value line: $l" }); continue }
            if ($val.Contains([string][char]9)) { [void]$rows.Add([pscustomobject]@{ Kind = 'E'; File = $f; Line = $n; Block = $blk; Key = ''; Value = ''; Message = "a value holds a tab character (key $key)" }); continue }
            [void]$rows.Add([pscustomobject]@{ Kind = 'S'; File = $f; Line = $n; Block = $blk; Key = $key; Value = $val; Message = '' })
        }
        if ($inb) { [void]$rows.Add([pscustomobject]@{ Kind = 'E'; File = $f; Line = $bs; Block = $blk; Key = ''; Value = ''; Message = 'unterminated sumela-step block (no closing fence)' }) }
    }
    return ,$rows
}

function Get-Base([string]$f) { $i = $f.LastIndexOf('/'); if ($i -lt 0) { return $f }; return $f.Substring($i + 1) }
function Get-DirOf([string]$f) { $i = $f.LastIndexOf('/'); if ($i -lt 0) { return '.' }; return $f.Substring(0, $i) }

function Get-Words([string]$s) {
    # The words of a command line made of plain characters only, or $null for anything else
    # (words() in the bash runner): runs of $script:wordChars not starting with @, or whole
    # double-quoted strings of those, spaces and commas, separated by spaces; {SRC}, {ROOT} and
    # {TARGET} in either. A tab, #, $, a backtick, ; & | < > ( ) { }, any other quote or a
    # non-ASCII character (PowerShell reads curly quotes as quotes) makes it $null.
    $out = New-Object System.Collections.Generic.List[string]
    $w = New-Object System.Text.StringBuilder
    $st = 0; $i = 0; $n = $s.Length       # st: 0 between words, 1 in a word, 2 in a string, 3 just after one
    while ($i -lt $n) {
        $c = $s[$i]
        if ($c -eq [char]32) {
            if ($st -eq 2) { [void]$w.Append($c) }
            else { if ($st -ne 0) { $out.Add($w.ToString()); $w.Length = 0 }; $st = 0 }
            $i++; continue
        }
        if ($st -eq 3) { return $null }
        if ($c -eq [char]34) {
            if ($st -eq 0) { $st = 2 }
            elseif ($st -eq 2) { if ($w.Length -eq 0) { return $null }; $st = 3 }
            else { return $null }
            $i++; continue
        }
        if ($c -eq [char]123) {
            $pl = 0
            foreach ($p in @('{SRC}', '{ROOT}', '{TARGET}')) { if (($i + $p.Length -le $n) -and (Eq $s.Substring($i, $p.Length) $p)) { $pl = $p.Length; break } }
            if ($pl -eq 0) { return $null }
            [void]$w.Append($s.Substring($i, $pl)); $i += $pl
            if ($st -eq 0) { $st = 1 }
            continue
        }
        if (($script:wordChars.IndexOf($c) -lt 0) -and -not (($st -eq 2) -and ($c -eq [char]44))) { return $null }
        if (($st -eq 0) -and ($c -eq [char]64)) { return $null }
        [void]$w.Append($c); $i++
        if ($st -eq 0) { $st = 1 }
    }
    if ($st -eq 2) { return $null }
    if ($st -ne 0) { $out.Add($w.ToString()) }
    return ,$out.ToArray()
}
function Test-Script([string]$w, [string]$ext) {
    return ((-not $w.StartsWith('-', $ord)) -and ($w -cmatch ('^(\{(SRC|ROOT)\}/)?([A-Za-z0-9_.-]+/)*[A-Za-z0-9_.-]+\.' + $ext + '\z')))
}
function Test-RoMode([string]$w) { foreach ($m in @('--plan', '--plan-check', '--status', '--check', '--verify-applied')) { if (Eq $w $m) { return $true } }; return $false }
function Test-GitGet([string[]]$t, [int]$from) {
    # git [-C <dir>] config [--local|--global|--worktree] --get <key>, and nothing else
    $n = $t.Length; $i = $from
    if (($i -lt $n) -and (Eq $t[$i] '-C')) { if (($i + 1 -ge $n) -or $t[$i + 1].StartsWith('-', $ord)) { return $false }; $i += 2 }
    if (($i -ge $n) -or -not (Eq $t[$i] 'config')) { return $false }
    $i++
    if (($i -lt $n) -and ((Eq $t[$i] '--local') -or (Eq $t[$i] '--global') -or (Eq $t[$i] '--worktree'))) { $i++ }
    if (($i -ge $n) -or -not (Eq $t[$i] '--get')) { return $false }
    return (($i + 2 -eq $n) -and ($t[$n - 1] -cmatch '^[A-Za-z0-9._-]+\z'))
}
function Test-ReadOnlyCmd([string]$s) {
    # A read-only bash line [RU-M10] (readonly_cmd in the bash runner).
    $t = Get-Words $s
    if (($null -eq $t) -or ($t.Length -lt 1)) { return $false }
    $n = $t.Length
    if (Eq $t[0] 'git') { return (Test-GitGet $t 1) }
    if ((-not (Eq $t[0] 'bash')) -or ($n -lt 2) -or -not (Test-Script $t[1] 'sh')) { return $false }
    if (Eq (Get-Base $t[1]) 'validate-structure.sh') { return ($n -eq 2) }
    $i = 2
    if (($i -lt $n) -and (Eq $t[$i] '--source')) { if (($i + 1 -ge $n) -or $t[$i + 1].StartsWith('-', $ord)) { return $false }; $i += 2 }
    if ($i -ge $n) { return $false }
    if (Test-RoMode $t[$i]) { return ($i -eq $n - 1) }
    if (Eq $t[$i] '--has-baseline') { return (($i + 2 -eq $n) -and ($t[$n - 1] -cmatch '^[A-Za-z0-9._-]+\z')) }
    return $false
}
function Test-ReadOnlyPs([string]$s) {
    # The PowerShell twin of that shape (readonly_ps in the bash runner).
    $t = Get-Words $s
    if (($null -eq $t) -or ($t.Length -lt 1)) { return $false }
    $n = $t.Length
    if (EqI $t[0] 'git') { return (Test-GitGet $t 1) }
    if (-not ((EqI $t[0] 'powershell') -or (EqI $t[0] 'pwsh'))) { return $false }
    $i = 1
    while (($i -lt $n) -and ((EqI $t[$i] '-NoProfile') -or (EqI $t[$i] '-NonInteractive'))) { $i++ }
    if (($i -ge $n) -or -not (EqI $t[$i] '-File')) { return $false }
    $i++
    if (($i -ge $n) -or -not (Test-Script $t[$i] 'ps1')) { return $false }
    $i++
    if (($i -lt $n) -and ((EqI $t[$i] '-SourceDir') -or (EqI $t[$i] '-Source') -or (Eq $t[$i] '--source'))) {
        if (($i + 1 -ge $n) -or $t[$i + 1].StartsWith('-', $ord)) { return $false }; $i += 2
    }
    if ($i -ge $n) { return $false }
    foreach ($m in @('-Plan', '-PlanCheck', '-Status', '-Check', '-VerifyApplied')) { if (EqI $t[$i] $m) { return ($i -eq $n - 1) } }
    if (Test-RoMode $t[$i]) { return ($i -eq $n - 1) }
    if ((EqI $t[$i] '-HasBaseline') -or (Eq $t[$i] '--has-baseline')) { return (($i + 2 -eq $n) -and ($t[$n - 1] -cmatch '^[A-Za-z0-9._-]+\z')) }
    return $false
}
function Test-PlaceholderAt([string]$s, [int]$i) {
    return ((($i + 5 -le $s.Length) -and (Eq $s.Substring($i, 5) '{SRC}')) -or (($i + 6 -le $s.Length) -and (Eq $s.Substring($i, 6) '{ROOT}')))
}
function Test-DoubleQuoted([string]$s, [bool]$isPs) {
    # Every {SRC} and {ROOT} sits inside double quotes in its own quoting context (dq_ok).
    $st = 0
    $stack = New-Object System.Collections.Generic.Stack[int]
    for ($i = 0; $i -lt $s.Length; $i++) {
        $c = $s[$i]
        if ($st -eq 2) {
            if ($c -eq [char]39) { $st = 0 } elseif (Test-PlaceholderAt $s $i) { return $false }
            continue
        }
        if (((-not $isPs) -and ($c -eq [char]92)) -or ($isPs -and ($c -eq [char]96))) {
            if (Test-PlaceholderAt $s ($i + 1)) { return $false }
            $i++; continue
        }
        if (($c -eq [char]36) -and ($i + 1 -lt $s.Length) -and ($s[$i + 1] -eq [char]40)) { $stack.Push($st); $st = 0; $i++; continue }
        if (($c -eq [char]41) -and ($st -eq 0) -and ($stack.Count -gt 0)) { $st = $stack.Pop(); continue }
        if ($c -eq [char]34) {
            if ($isPs -and ($st -eq 1) -and ($i + 1 -lt $s.Length) -and ($s[$i + 1] -eq [char]34)) { $i++; continue }
            if ($st -eq 1) { $st = 0 } else { $st = 1 }
            continue
        }
        if (($st -eq 0) -and ($c -eq [char]39)) { $st = 2; continue }
        if ((Test-PlaceholderAt $s $i) -and ($st -ne 1)) { return $false }
    }
    return $true
}

function Test-NotesRows($Rows, $Report) {
    # -> @{ Defects = list of "file:line: message"; Patterns = list of @(file, line, pattern) }
    $defects = New-List; $patterns = New-List
    $known = ' id title scope when requires consent run run.ps1 verify verify.ps1 expect rollback rollback.ps1 agent ledger until '
    $reqk = @('id', 'title', 'scope', 'when', 'consent', 'run', 'verify', 'expect')
    $order = New-List; $blocks = New-Dict
    $add = { param($f, $l, $m) if ($Report.ContainsKey($f)) { [void]$defects.Add("${f}:${l}: $m") } }
    foreach ($r in $Rows) {
        if (Eq $r.Kind 'E') { & $add $r.File $r.Line $r.Message; continue }
        if (Eq $r.Kind 'B') {
            $b = [pscustomobject]@{ File = $r.File; Line = $r.Line; Val = (New-Dict); KLine = (New-Dict); Keys = (New-List); Edges = (New-List); Dup = $false }
            $blocks[[string]$r.Block] = $b; [void]$order.Add($b); continue
        }
        $b = $blocks[[string]$r.Block]
        if ($known.IndexOf(' ' + $r.Key + ' ', $ord) -lt 0) { & $add $r.File $r.Line "unknown key $($r.Key)"; continue }
        if ($b.Val.ContainsKey($r.Key)) { & $add $r.File $r.Line "duplicate key $($r.Key) in one step"; continue }
        if ($r.Value.Length -eq 0) { & $add $r.File $r.Line "empty value for $($r.Key)"; continue }
        $b.Val[$r.Key] = $r.Value; $b.KLine[$r.Key] = $r.Line; [void]$b.Keys.Add($r.Key)
    }
    $v = { param($b, $k) if ($b.Val.ContainsKey($k)) { return [string]$b.Val[$k] }; return '' }
    $kl = { param($b, $k) if ($b.KLine.ContainsKey($k)) { return $b.KLine[$k] }; return $b.Line }
    $owner = New-Dict
    foreach ($b in $order) {
        $id = & $v $b 'id'; if ($id.Length -eq 0) { continue }
        $okey = (Get-DirOf $b.File) + "`n" + $id
        if ($owner.ContainsKey($okey)) { $o = $owner[$okey]; & $add $b.File (& $kl $b 'id') "duplicate id $id (also in $($o.File):$($o.Line))"; $b.Dup = $true; continue }
        $owner[$okey] = $b
    }
    foreach ($b in $order) {
        $f = $b.File; $d = Get-DirOf $f; $bn = Get-Base $f; $l = $b.Line
        $generic = Eq $bn 'upgrade.md'; $fver = $bn; if ($fver.EndsWith('.md', $ord)) { $fver = $fver.Substring(0, $fver.Length - 3) }
        $id = & $v $b 'id'
        if ($id.Length -eq 0) { & $add $f $l 'a step without an id'; continue }
        if ($b.Dup) { continue }
        foreach ($k in $reqk) {
            if (-not $b.Val.ContainsKey($k)) {
                $extra = ''; if ((Eq $k 'verify') -and (Eq (& $v $b 'run') '-')) { $extra = ' (a run: - step must name its verify)' }
                & $add $f $l "step ${id}: missing $k$extra"
            }
        }
        if ($generic) { if ($id -cnotmatch '^upgrade-[0-9][0-9]\z') { & $add $f (& $kl $b 'id') "id $id must be upgrade-<NN> in upgrade.md" } }
        elseif (-not ($id.StartsWith($fver + '-', $ord) -and ($id.Substring($fver.Length + 1) -cmatch '^[0-9][0-9]\z'))) { & $add $f (& $kl $b 'id') "id $id must be $fver-<NN> in $bn" }
        $sc = & $v $b 'scope'; $wh = & $v $b 'when'; $co = & $v $b 'consent'; $r = & $v $b 'run'
        if ($b.Val.ContainsKey('scope') -and -not ((Eq $sc 'repo') -or (Eq $sc 'developer'))) { & $add $f (& $kl $b 'scope') "scope must be repo or developer, not $sc" }
        if ($generic -and $b.Val.ContainsKey('scope') -and -not (Eq $sc 'repo')) { & $add $f (& $kl $b 'scope') 'upgrade.md holds repo steps only' }
        if ($b.Val.ContainsKey('when') -and ($wh -cnotmatch '^(pre-update|update|post-update|finalize|first-session|quiet-window)\z')) { & $add $f (& $kl $b 'when') "when must be pre-update, update, post-update, finalize, first-session or quiet-window, not $wh" }
        if ($b.Val.ContainsKey('consent') -and ($co -cnotmatch '^(none|confirm|explicit)\z')) { & $add $f (& $kl $b 'consent') "consent must be none, confirm or explicit, not $co" }
        if ($b.Val.ContainsKey('ledger') -and -not (Eq (& $v $b 'ledger') 'none')) { & $add $f (& $kl $b 'ledger') 'ledger takes only none (leave it out for a ledger entry)' }
        if ($b.Val.ContainsKey('until')) {
            $u = & $v $b 'until'
            if ($u -cnotmatch '^[0-9]+\.[0-9]+\.[0-9]+\z') { & $add $f (& $kl $b 'until') "until must be a version X.Y.Z, not $u" }
            elseif ((-not $generic) -and ([string]::CompareOrdinal((Get-VKey $u), (Get-VKey $fver)) -le 0)) { & $add $f (& $kl $b 'until') "until $u is not above ${fver}: the step would never be selected" }
        }
        if ($b.Val.ContainsKey('expect')) {
            $e = & $v $b 'expect'
            if ((Eq $e 'exit0') -or (Eq $e 'non-empty') -or (Eq $e 'empty') -or $e.StartsWith('equals:', $ord)) { }
            elseif ($e.StartsWith('match:', $ord) -and ($e.Length -gt 6)) {
                $p = $e.Substring(6)
                if ($p.Contains('[[:') -or ($p -cmatch '\\[A-Za-z0-9]')) { & $add $f (& $kl $b 'expect') 'match: uses a POSIX class or a backslash escape; keep to the subset both runners read alike' }
                else { [void]$patterns.Add(@($f, (& $kl $b 'expect'), $p)) }
            } else { & $add $f (& $kl $b 'expect') "expect must be exit0, non-empty, empty, equals:<s> or match:<ERE>, not $e" }
        }
        if ($b.Val.ContainsKey('run')) {
            if ((-not (Eq $r '-')) -and (-not $b.Val.ContainsKey('run.ps1')) -and ($r -cnotmatch '^bash[ \t]')) { & $add $f (& $kl $b 'run') "step ${id}: a runnable step needs run.ps1, or a run line that starts with bash (the PowerShell runner sends it to Git Bash)" }
            if ((Eq $r '-') -and (-not $b.Val.ContainsKey('agent'))) { & $add $f $l "step ${id}: a run: - step needs an agent: instruction" }
        }
        # consent: none runs without asking, and so does its verify: every command line it has
        # must be one of the read-only shapes.
        if ($b.Val.ContainsKey('consent') -and (Eq $co 'none')) {
            if ($b.Val.ContainsKey('run') -and (-not (Eq $r '-')) -and -not (Test-ReadOnlyCmd $r)) { & $add $f (& $kl $b 'consent') "step ${id}: consent: none needs run: - or a read-only run: $($script:roSh)" }
            if ($b.Val.ContainsKey('run.ps1') -and -not (Test-ReadOnlyPs (& $v $b 'run.ps1'))) { & $add $f (& $kl $b 'run.ps1') "step ${id}: consent: none needs a read-only run.ps1 too: $($script:roPs)" }
            if ($b.Val.ContainsKey('verify') -and -not (Test-ReadOnlyCmd (& $v $b 'verify'))) { & $add $f (& $kl $b 'verify') "step ${id}: consent: none needs a read-only verify too (it runs without asking): $($script:roSh)" }
            if ($b.Val.ContainsKey('verify.ps1') -and -not (Test-ReadOnlyPs (& $v $b 'verify.ps1'))) { & $add $f (& $kl $b 'verify.ps1') "step ${id}: consent: none needs a read-only verify.ps1 too: $($script:roPs)" }
        }
        foreach ($k in $b.Keys) {
            $s = [string]$b.Val[$k]; $line = $b.KLine[$k]
            foreach ($m in [regex]::Matches($s, '\{[A-Za-z_][A-Za-z0-9_]*\}')) {
                $name = $m.Value.Substring(1, $m.Value.Length - 2)
                if (($m.Index -gt 0) -and ($s[$m.Index - 1] -eq [char]36)) { continue }
                if (-not ((Eq $name 'SRC') -or (Eq $name 'ROOT') -or (Eq $name 'TARGET'))) { & $add $f $line "unknown placeholder {$name} in $k (only {SRC}, {ROOT} and {TARGET})"; continue }
                if ((Eq $sc 'developer') -and (Eq $name 'SRC')) { & $add $f $line 'a developer step cannot use {SRC}: a teammate has no release clone' }
                if ((Eq $k 'expect') -and -not (Eq $name 'TARGET')) { & $add $f $line "expect cannot use {$name}" }
            }
            if (($k -cmatch '^(run|verify|rollback)(\.ps1)?\z') -and -not (Test-DoubleQuoted $s ($k.EndsWith('.ps1', $ord)))) { & $add $f $line "{SRC} and {ROOT} must sit inside double quotes in $k" }
        }
        if ($b.Val.ContainsKey('requires')) {
            foreach ($q in [regex]::Split((& $v $b 'requires'), '[ ,]+')) {
                if ($q.Length -eq 0) { continue }
                if (Eq $q $id) { & $add $f (& $kl $b 'requires') "step $id requires itself"; continue }
                $okey = $d + "`n" + $q
                if (-not $owner.ContainsKey($okey)) { & $add $f (& $kl $b 'requires') "step $id requires $q, which no notes file in $d defines"; continue }
                $o = $owner[$okey]; $osc = & $v $o 'scope'
                if (-not (Eq $osc $sc)) { & $add $f (& $kl $b 'requires') "step $id ($sc) requires $q (${osc}): requires stays within one scope"; continue }
                [void]$b.Edges.Add($o)
            }
        }
        if ((-not $generic) -and (Eq $sc 'repo') -and (Eq $wh 'pre-update') -and ((' ' + (& $v $b 'requires') + ' ') -cnotmatch '[ ,]upgrade-01[ ,]')) { & $add $f $l "step ${id}: a pre-update repo step needs requires: upgrade-01 (repo steps run in the upgrade worktree it creates)" }
    }
    # requires cycles (Kahn): whatever cannot be ordered sits on a cycle
    $live = New-List
    foreach ($b in $order) { if (((& $v $b 'id').Length -gt 0) -and -not $b.Dup) { [void]$live.Add($b) } }
    $placed = New-Object 'System.Collections.Generic.HashSet[object]'
    $changed = $true
    while ($changed) {
        $changed = $false
        foreach ($b in $live) {
            if ($placed.Contains($b)) { continue }
            $ready = $true
            foreach ($e in $b.Edges) { if (-not $placed.Contains($e)) { $ready = $false; break } }
            if ($ready) { [void]$placed.Add($b); $changed = $true }
        }
    }
    foreach ($b in $live) { if (-not $placed.Contains($b)) { & $add $b.File $b.Line "step $(& $v $b 'id'): requires forms a cycle" } }
    return [pscustomobject]@{ Defects = $defects; Patterns = $patterns }
}

function Test-NotesName([string]$bn) { return ((Eq $bn 'upgrade.md') -or ($bn -cmatch '^[0-9]+\.[0-9]+\.[0-9]+\.md\z')) }

function Invoke-Lint {
    # Prints defects as file:line: message (stdout); returns 4 on any defect, else 0.
    param([string[]]$Files, [bool]$ScanDir = $true)
    $defects = New-List; $report = New-Dict; $ctx = New-List; $ctxSet = New-Dict; $reportOrder = New-List
    foreach ($f0 in $Files) {
        $f = Slash $f0
        if ($f.IndexOf('/') -lt 0) { $f = './' + $f }
        $bn = Get-Base $f
        if (Eq $bn 'README.md') { Say "${f}: documentation, not notes (skipped)"; continue }
        if (-not (Test-NotesName $bn)) { [void]$defects.Add("${f}:1: not a notes file name (upgrade.md or <X.Y.Z>.md)"); continue }
        if (-not [IO.File]::Exists($f)) { [void]$defects.Add("${f}:1: cannot read the file"); continue }
        if (-not $report.ContainsKey($f)) { $report[$f] = $true; [void]$reportOrder.Add($f) }
        $d = Get-DirOf $f
        if ($ScanDir) {
            $names = New-Object System.Collections.Generic.List[string]
            foreach ($p in [IO.Directory]::GetFiles($d, '*.md')) { $names.Add((Get-Base (Slash $p))) }
            $sorted = $names.ToArray(); [Array]::Sort($sorted, [StringComparer]::Ordinal)
            foreach ($n in (@('upgrade.md') + $sorted)) {
                if (-not (Test-NotesName $n)) { continue }
                $p = $d + '/' + $n
                if ([IO.File]::Exists($p) -and -not $ctxSet.ContainsKey($p)) { $ctxSet[$p] = $true; [void]$ctx.Add($p) }
            }
        }
        if (-not $ctxSet.ContainsKey($f)) { $ctxSet[$f] = $true; [void]$ctx.Add($f) }
    }
    $rows = $null
    if ($ctx.Count -gt 0) {
        $rows = Read-NotesRows ([string[]]$ctx.ToArray())
        $chk = Test-NotesRows $rows $report
        foreach ($x in $chk.Defects) { [void]$defects.Add($x) }
        foreach ($pt in $chk.Patterns) {
            $pat = ([string]$pt[2]).Replace('{TARGET}', '0\.0\.0')
            try { [void](New-Object System.Text.RegularExpressions.Regex($pat)) } catch { [void]$defects.Add("$($pt[0]):$($pt[1]): match: $($pt[2]) is not a valid extended regular expression") }
        }
    }
    if ($defects.Count -gt 0) { foreach ($x in $defects) { Out-Line $x }; return 4 }
    foreach ($f in $reportOrder) {
        $n = 0; foreach ($r in $rows) { if ((Eq $r.Kind 'B') -and (Eq $r.File $f)) { $n++ } }
        if ($n -eq 1) { Say "${f}: ok (1 step)" } else { Say "${f}: ok ($n steps)" }
    }
    return 0
}

function Get-NotesFiles([string]$dir) {
    # The notes files committed at the HEAD of <dir> (upgrade.md and <X.Y.Z>.md, relative to it),
    # as @{ Mode; Blob; Path } (notes_files in the bash runner).
    $r = Invoke-CGit -Dir $dir -GitArgs @('-c', 'core.quotePath=false', 'ls-tree', '-r', 'HEAD', '--', ($script:notesRel + '/'))
    $out = New-List
    if ($r.ExitCode -ne 0) { return ,$out }
    foreach ($l in $r.Lines) {
        $t = $l.IndexOf([char]9); if ($t -lt 0) { continue }
        $path = $l.Substring($t + 1)
        if ($path -cnotmatch ('^' + [regex]::Escape($script:notesRel) + '/(upgrade|[0-9]+\.[0-9]+\.[0-9]+)\.md\z')) { continue }
        $m = [regex]::Split($l.Substring(0, $t), ' ')
        if ($m.Length -lt 3) { continue }
        [void]$out.Add([pscustomobject]@{ Mode = $m[0]; Blob = $m[2]; Path = $path })
    }
    return ,$out
}

$script:steps = New-List
$script:stepById = New-Dict
function Import-NotesSet {
    # Validates the notes committed at the HEAD of <dir> (read from their blobs) and adds that
    # set's steps (repo: scope repo; dev: scope developer). Returns 0 loaded, 1 the notes differ
    # from HEAD (developer notes) or cannot be read, 4 invalid notes.
    param([string]$Set, [string]$Dir)
    $rel = Get-NotesFiles $Dir
    if ($rel.Count -eq 0) { return 0 }
    $shown = (Slash $Dir) + '/' + $script:notesRel
    $tmpd = $script:work + '/notes-' + $Set
    Remove-Tree $tmpd
    [void][IO.Directory]::CreateDirectory($tmpd)
    $files = New-Object System.Collections.Generic.List[string]
    foreach ($x in $rel) {
        # Only regular files: a committed symlink would point outside HEAD.
        if (-not ((Eq $x.Mode '100644') -or (Eq $x.Mode '100755'))) { Warn "$($x.Path) at the HEAD of $(Slash $Dir) is not a regular file (mode $($x.Mode): a symlink?): refusing to read steps from it"; return 1 }
        $to = $tmpd + '/' + (Get-Base $x.Path)
        if (-not (Save-GitBlob $Dir $x.Blob $to)) { Warn "cannot read $($x.Path) at the HEAD of $(Slash $Dir)"; return 1 }
        $files.Add($to)
    }
    if ((Eq $Set 'dev') -and ((Invoke-CGit -Dir $Dir -GitArgs @('diff', '--quiet', '--no-ext-diff', '--no-textconv', 'HEAD', '--', ($script:notesRel + '/'))).ExitCode -ne 0)) {
        Warn "the notes in $shown/ differ from HEAD: refusing to read steps from them"
        Warn "  (restore them with: git -C `"$(Slash $Dir)`" checkout HEAD -- $($script:notesRel)/)"
        return 1
    }
    $sw = New-Object System.IO.StringWriter
    $saved = [Console]::Out
    [Console]::SetOut($sw)
    try { $rc = Invoke-Lint -Files $files.ToArray() -ScanDir $false } finally { [Console]::SetOut($saved) }
    if ($rc -ne 0) {
        [Console]::Error.Write($sw.ToString().Replace($tmpd, $shown))
        Warn "invalid migration notes in $shown/ (at HEAD): nothing runs from them"
        return 4
    }
    $want = 'developer'; if (Eq $Set 'repo') { $want = 'repo' }
    $rows = Read-NotesRows $files.ToArray()
    $cur = $null
    $blocks = New-List
    foreach ($r in $rows) {
        if (Eq $r.Kind 'B') { $cur = [pscustomobject]@{ File = $r.File; Line = $r.Line; Keys = (New-List); Map = (New-Dict) }; [void]$blocks.Add($cur); continue }
        if (Eq $r.Kind 'S') { [void]$cur.Keys.Add($r.Key); $cur.Map[$r.Key] = $r.Value }
    }
    foreach ($b in $blocks) {
        if (-not (Eq ([string]$b.Map['scope']) $want)) { continue }
        $bn = Get-Base $b.File
        $origin = 'version'; $ver = $bn.Substring(0, $bn.Length - 3)
        if (Eq $bn 'upgrade.md') { $origin = 'generic'; $ver = '' }
        $st = [pscustomobject]@{ Set = $Set; Id = [string]$b.Map['id']; Origin = $origin; Version = $ver; File = $b.File.Replace($tmpd, $shown); Line = $b.Line; Keys = $b.Keys; Map = $b.Map }
        [void]$script:steps.Add($st)
        if (-not $script:stepById.ContainsKey($st.Id)) { $script:stepById[$st.Id] = $st }
    }
    return 0
}
function Get-Field($st, [string]$k) { if ($st.Map.ContainsKey($k)) { return [string]$st.Map[$k] }; return '' }
function Find-Step([string]$id, [string]$set) {
    if ($script:stepById.ContainsKey($id)) { $s = $script:stepById[$id]; if (Eq $s.Set $set) { return $s } }
    return $null
}

# --- Substitution ----------------------------------------------------------------------------
$script:stepSrc = ''; $script:stepRoot = ''; $script:stepTarget = ''; $script:stepScope = ''; $script:stepState = ''
function Convert-Cmd([string]$s) {
    return $s.Replace('{SRC}', '${SUMELA_MIGRATE_SRC}').Replace('{ROOT}', '${SUMELA_MIGRATE_ROOT}').Replace('{TARGET}', $script:stepTarget)
}
function Convert-PsCmd([string]$s) {
    return $s.Replace('{SRC}', '${env:SUMELA_MIGRATE_SRC}').Replace('{ROOT}', '${env:SUMELA_MIGRATE_ROOT}').Replace('{TARGET}', $script:stepTarget)
}
function Convert-Expect([string]$s) {
    # Inside match:, {TARGET} is matched literally (its dots escaped).
    if ($s.StartsWith('match:', $ord)) { return $s.Replace('{TARGET}', $script:stepTarget.Replace('.', '\.')) }
    return $s.Replace('{TARGET}', $script:stepTarget)
}
function Convert-Text([string]$s) {
    return $s.Replace('{SRC}', $script:stepSrc).Replace('{ROOT}', $script:stepRoot).Replace('{TARGET}', $script:stepTarget)
}

# --- Windows paths ---------------------------------------------------------------------------
$script:cygpath = $null; $script:cygpathFound = $false
function Find-Cygpath {
    # Git for Windows' cygpath.exe, beside its Git Bash (<git --exec-path>/../../../usr/bin), never
    # from PATH; $null when there is none. Looked up once.
    if (-not $script:cygpathFound) {
        $script:cygpathFound = $true
        $exec = Get-GitLine -Dir '' -GitArgs @('--exec-path')
        if ($exec) {
            $p = [IO.Path]::GetFullPath((Join-Path $exec '../../../usr/bin/cygpath.exe'))
            if ([IO.File]::Exists($p)) { $script:cygpath = $p }
        }
    }
    return $script:cygpath
}
function ConvertTo-NativePath([string]$p) {
    # On Windows, an absolute POSIX path (an MSYS path a bash tool wrote) in the form git reads,
    # C:/x: cygpath -m when Git for Windows has it (it knows the mount table: /tmp, /usr, the
    # cygdrive prefix), else /x/rest maps to X:/rest. Any other path, and every path elsewhere,
    # is returned as it is (native_path in the bash runner).
    if ((-not $script:onWindows) -or (-not $p.StartsWith('/', $ord))) { return $p }
    $cyg = Find-Cygpath
    if ($cyg) {
        $r = Invoke-Native -Exe $cyg -ArgList @('-m', $p)
        if (($r.ExitCode -eq 0) -and (@($r.Lines).Count -eq 1) -and ([string]$r.Lines[0]).Length -gt 0) { return [string]$r.Lines[0] }
    }
    $m = [regex]::Match($p, '^/([A-Za-z])(/.*)?\z')
    if (-not $m.Success) { return $p }
    $rest = $m.Groups[2].Value; if ($rest.Length -eq 0) { $rest = '/' }
    return ($m.Groups[1].Value.ToUpperInvariant() + ':' + $rest)
}

# --- URLs ------------------------------------------------------------------------------------
function ConvertTo-AsciiLower([string]$s) {
    # A-Z to a-z and nothing else, as awk's tolower in the C locale (url_key in the bash runner).
    $c = $s.ToCharArray()
    for ($i = 0; $i -lt $c.Length; $i++) { $v = [int]$c[$i]; if (($v -ge 65) -and ($v -le 90)) { $c[$i] = [char]($v + 32) } }
    return (-join $c)
}
function Get-LocalUrlPath([string]$u) {
    # The path of a URL that names a local repository (a plain path, or a file:// URL, where
    # file:///C:/x gives C:/x), backslashes as slashes; $null for a remote URL (another scheme,
    # or an scp-style host:path) (local_url_path in the bash runner).
    $m = [regex]::Match($u, '^[A-Za-z][A-Za-z0-9+.-]*://')
    if ($m.Success) {
        if (-not (Eq (ConvertTo-AsciiLower $m.Value) 'file://')) { return $null }
        $u = $u.Substring($m.Length)
        if ($u -cmatch '^/[A-Za-z]:([/\\]|\z)') { $u = $u.Substring(1) }
    } elseif (($u -cmatch '^[^/]+:') -and ($u -cnotmatch '^[A-Za-z]:')) { return $null }
    return $u.Replace('\', '/')
}
function Remove-UserInfo([string]$u) {
    # Never store or print a credential: http(s) URLs lose their whole userinfo, other scheme URLs
    # keep the user name and lose the password (strip_userinfo in the bash runner).
    $m = [regex]::Match($u, '^[A-Za-z][A-Za-z0-9+.-]*://')
    if (-not $m.Success) { return $u }
    $s = $m.Value; $r = $u.Substring($s.Length)
    $slash = $r.IndexOf('/'); if ($slash -lt 0) { $a = $r; $rest = '' } else { $a = $r.Substring(0, $slash); $rest = $r.Substring($slash) }
    $at = $a.LastIndexOf('@')
    if ($at -ge 0) {
        $ui = $a.Substring(0, $at); $h = $a.Substring($at + 1)
        if ($s.StartsWith('http', $ordI)) { $a = $h } else { $c = $ui.IndexOf(':'); if ($c -ge 0) { $ui = $ui.Substring(0, $c) }; $a = $ui + '@' + $h }
    }
    return $s + $a + $rest
}
function Get-UrlKey([string]$u) {
    # A comparable form of a repository URL (url_key in the bash runner): on Windows a local path
    # in its native form, its drive letter in upper case (/c/x, c:\x and file:///C:/x are all C:/x).
    if ($script:onWindows) {
        $p = Get-LocalUrlPath $u
        if ($null -ne $p) {
            $u = ConvertTo-NativePath $p
            if ($u -cmatch '^[a-z]:') { $u = $u.Substring(0, 1).ToUpperInvariant() + $u.Substring(1) }
        }
    }
    $m = [regex]::Match($u, '^[A-Za-z][A-Za-z0-9+.-]*://')
    if ($m.Success) {
        $x = $u.Substring($m.Length); $slash = $x.IndexOf('/')
        if ($slash -lt 0) { $a = $x; $rest = '' } else { $a = $x.Substring(0, $slash); $rest = $x.Substring($slash) }
        $at = $a.LastIndexOf('@'); if ($at -ge 0) { $a = $a.Substring($at + 1) }
        $u = (ConvertTo-AsciiLower $a) + $rest
    } elseif (($u -cmatch '^[^/]+:') -and ($u -cnotmatch '^[A-Za-z]:')) {
        $c = $u.IndexOf(':'); $a = $u.Substring(0, $c); $rest = $u.Substring($c + 1)
        $at = $a.LastIndexOf('@'); if ($at -ge 0) { $a = $a.Substring($at + 1) }
        $u = (ConvertTo-AsciiLower $a) + '/' + $rest
    }
    $u = $u.TrimEnd('/')
    if ($u.EndsWith('.git', $ord)) { $u = $u.Substring(0, $u.Length - 4) }
    return $u.TrimEnd('/')
}
function Get-UpstreamUrl {
    $f = $script:localRoot + '/.sumela/upstream.conf'
    if ([IO.File]::Exists($f)) {
        foreach ($l in [IO.File]::ReadAllText($f, $script:utf8).Split([char]10)) {
            # Only the ends are trimmed: a local path may hold spaces (a URL holds none).
            $x = $l.Trim(); if ($x -and -not $x.StartsWith('#', $ord)) { return $x }
        }
    }
    return $script:defaultUpstream
}

# --- Where things are --------------------------------------------------------------------------
function Find-InstallRoot {
    $p = (Get-Location -PSProvider FileSystem).ProviderPath
    while ($p) {
        if ([IO.Directory]::Exists((Join-Path $p '.sumela'))) { return $p }
        $parent = [IO.Path]::GetDirectoryName($p)
        if ((-not $parent) -or (Eq $parent $p)) { break }
        $p = $parent
    }
    return $null
}
function Resolve-UserPath([string]$p) {
    # A path the user typed, made absolute against the current PowerShell location (.NET resolves
    # relative paths against the process directory, which Set-Location does not move).
    if (-not $p) { return $p }
    if ([IO.Path]::IsPathRooted($p)) { return $p }
    return [IO.Path]::GetFullPath((Join-Path (Get-Location -PSProvider FileSystem).ProviderPath $p))
}
function Join-Root([string]$a, [string]$b) { if ($b) { return ($a.TrimEnd('/') + '/' + $b) }; return $a }
$script:localRoot = ''; $script:prefix = ''; $script:mainRoot = ''; $script:stateFile = ''; $script:common = ''
function Initialize-Location {
    $lr = Find-InstallRoot
    if (-not $lr) { Die "no .sumela/ above $((Get-Location -PSProvider FileSystem).ProviderPath): run this inside a SumelaOS project's checkout" }
    $script:localRoot = Slash $lr
    # git's own message says why it failed; the probe tells a directory git cannot enter from a
    # repository it does not find or refuses (locate in the bash runner).
    $r = Invoke-Git -Dir $script:localRoot -GitArgs @('rev-parse', '--path-format=absolute', '--git-common-dir')
    if ($r.ExitCode -ne 0) {
        foreach ($l in @($r.Err)) { [Console]::Error.WriteLine($l) }
        if ((Invoke-Git -Dir $script:localRoot -GitArgs @('version')).ExitCode -ne 0) {
            Die "git cannot enter $($script:localRoot) (git's message is above): the directory is missing, unreadable, or named in a form git cannot open"
        }
        Die "$($script:localRoot) is not inside a git work tree, or git refuses the repository there (git's message is above)"
    }
    foreach ($l in @($r.Err)) { [Console]::Error.WriteLine($l) }
    # git before 2.31 does not fail on --path-format: it prints the option back, then a relative path.
    $lines = @($r.Lines)
    if (($lines.Count -ne 1) -or ([string]$lines[0] -cnotmatch '^(/|[A-Za-z]:/)')) {
        $first = ''; if ($lines.Count -gt 0) { $first = [string]$lines[0] }
        Die "git 2.31 or later is required: git rev-parse --path-format=absolute printed '$first' ($(Get-GitLine -Dir '' -GitArgs @('version')))"
    }
    $script:common = [string]$lines[0]
    $p = Get-GitLine -Dir $script:localRoot -GitArgs @('rev-parse', '--show-prefix')
    if ($null -eq $p) { Die "git cannot read $($script:localRoot)" }
    $script:prefix = $p.TrimEnd('/')
    $w = Invoke-Git -Dir $script:localRoot -GitArgs @('worktree', 'list', '--porcelain')
    $top = ''; $bare = $false
    for ($i = 0; $i -lt @($w.Lines).Count; $i++) {
        $l = [string]$w.Lines[$i]
        if (($i -gt 0) -and ($l.Length -eq 0)) { break }
        if (($i -eq 0) -and $l.StartsWith('worktree ', $ord)) { $top = $l.Substring(9) }
        if (Eq $l 'bare') { $bare = $true }
    }
    $script:mainRoot = $script:localRoot
    if ($top -and (-not $bare) -and [IO.Directory]::Exists((Join-Root $top $script:prefix) + '/.sumela')) { $script:mainRoot = Join-Root $top $script:prefix }
    $script:stateFile = $script:mainRoot + '/.sumela/.upgrade/migrate.state'
}

# --- State -------------------------------------------------------------------------------------
function Get-StateValue([string]$key) {
    # The last line for <key>, or $null when absent.
    if (-not [IO.File]::Exists($script:stateFile)) { return $null }
    $val = $null
    foreach ($l in [IO.File]::ReadAllText($script:stateFile, $script:utf8).Split([char]10)) {
        $x = $l.TrimEnd([char]13)
        $p = $x.IndexOf('=')
        if (($p -gt 0) -and (Eq $x.Substring(0, $p) $key)) { $val = $x.Substring($p + 1) }
    }
    return $val
}
function Save-StateText([string]$text) {
    $dir = [IO.Path]::GetDirectoryName($script:stateFile)
    $tmp = Join-Path $dir ('.migrate.state.tmp.' + $PID)
    try {
        [IO.File]::WriteAllText($tmp, $text, $script:utf8)
        if ([IO.File]::Exists($script:stateFile)) { [IO.File]::Replace($tmp, $script:stateFile, [NullString]::Value) } else { [IO.File]::Move($tmp, $script:stateFile) }
    } catch {
        if ([IO.File]::Exists($tmp)) { [IO.File]::Delete($tmp) }
        Die "cannot write $($script:stateFile)"
    }
}
function Write-State([string[]]$Pairs) {
    # One key=value per line: a value with a control character (a newline) could forge a key.
    foreach ($pair in $Pairs) { if (Test-Control $pair) { Die "refusing to record $($pair.Substring(0, [Math]::Max(0, $pair.IndexOf('=')))): its value holds a control character (a newline?)" } }
    $dir = [IO.Path]::GetDirectoryName($script:stateFile)
    [void][IO.Directory]::CreateDirectory($dir)
    $gi = Join-Path $dir '.gitignore'
    if (-not [IO.File]::Exists($gi)) {          # a runtime directory ignores itself [RU-M8]
        $t = $gi + '.tmp.' + $PID; [IO.File]::WriteAllText($t, "*`n", $script:utf8); [IO.File]::Move($t, $gi)
    }
    $given = New-Dict
    foreach ($pair in $Pairs) { $p = $pair.IndexOf('='); $given[$pair.Substring(0, $p)] = $pair.Substring($p + 1) }
    $sb = New-Object System.Text.StringBuilder
    foreach ($k in $script:stateKeys) {
        if ($given.ContainsKey($k)) { [void]$sb.Append($k + '=' + [string]$given[$k] + "`n") }
        else { $old = Get-StateValue $k; if ($null -ne $old) { [void]$sb.Append($k + '=' + $old + "`n") } }
    }
    Save-StateText $sb.ToString()
    foreach ($k in $given.Keys) { if (-not (Eq (Get-StateValue $k) ([string]$given[$k]))) { Die "$($script:stateFile) does not hold $k after the write" } }
}
function Remove-StateKeys([string[]]$Keys) {
    if (-not [IO.File]::Exists($script:stateFile)) { return }
    $sb = New-Object System.Text.StringBuilder
    foreach ($l in [IO.File]::ReadAllText($script:stateFile, $script:utf8).Split([char]10)) {
        $x = $l.TrimEnd([char]13); if ($x.Length -eq 0) { continue }
        $p = $x.IndexOf('='); $drop = $false
        if ($p -gt 0) { foreach ($k in $Keys) { if (Eq $x.Substring(0, $p) $k) { $drop = $true } } }
        if (-not $drop) { [void]$sb.Append($x + "`n") }
    }
    Save-StateText $sb.ToString()
}
function Remove-State([string]$why) {
    # The upgrade is complete: its per-developer state goes.
    [IO.File]::Delete($script:stateFile)
    Say "the upgrade to v$($script:target) is complete (${why}): removed $($script:stateFile)"
}
function Test-MainAtTarget {
    $v = Read-Version $script:mainRoot
    if (($null -eq $v) -or -not (Test-Version $v)) { return $false }
    return ((Compare-Version $v $script:target) -ge 0)
}

# --- The release clone -------------------------------------------------------------------------
$script:cloneTop = ''; $script:cloneTarget = ''; $script:cloneTag = ''; $script:cloneHead = ''; $script:cloneUrl = ''
function Get-CloneTag([string]$d, [string]$t) {
    $head = Get-CGitLine -Dir $d -GitArgs @('rev-parse', '-q', '--verify', 'HEAD^{commit}')
    if (-not $head) { return $null }
    $pick = $null
    $r = Invoke-CGit -Dir $d -GitArgs @('tag', '--points-at', 'HEAD')
    foreach ($tag in @($r.Lines)) {
        if (-not ((Eq $tag "v$t") -or ($tag.StartsWith("v$t-rc.", $ord) -and ($tag.Substring(("v$t-rc.").Length) -cmatch '^[0-9]+\z')))) { continue }
        if (-not (Eq (Get-CGitLine -Dir $d -GitArgs @('cat-file', '-t', "refs/tags/$tag")) 'tag')) { continue }
        if (-not (Eq (Get-CGitLine -Dir $d -GitArgs @('rev-parse', '-q', '--verify', "refs/tags/$tag^{commit}")) $head)) { continue }
        if ((Eq $tag "v$t") -or ($null -eq $pick)) { $pick = $tag }
    }
    return $pick
}
function Get-ShownUrl([string]$u) { if ($u) { return (Remove-UserInfo $u) }; return 'no origin' }
function Test-Control([string]$s) { return [regex]::IsMatch($s, '[\x00-\x1F\x7F]') }
function Invoke-LsRemote([string]$url, [string]$ref) {
    # git ls-remote <url> <ref>, from outside every repository: no clone configuration (its
    # url.<x>.insteadOf) can redirect it.
    $savedP = $env:GIT_ALLOW_PROTOCOL; $savedC = $env:GIT_CEILING_DIRECTORIES
    if (-not $env:GIT_ALLOW_PROTOCOL) { $env:GIT_ALLOW_PROTOCOL = 'https:ssh:git' }
    $env:GIT_CEILING_DIRECTORIES = [IO.Path]::GetDirectoryName($script:work)
    # A local path goes to git in its native form (ConvertTo-NativePath).
    try { return (Invoke-Git -Dir $script:work -GitArgs @('ls-remote', '--', (ConvertTo-NativePath $url), $ref)) }
    finally { $env:GIT_ALLOW_PROTOCOL = $savedP; $env:GIT_CEILING_DIRECTORIES = $savedC }
}
function Get-CloneProblem([string]$d, [string]$mode) {
    # Checks the release clone as check_clone in the bash runner does; sets cloneTop, cloneTarget,
    # cloneTag, cloneHead, cloneUrl. Returns $null, or why the clone is refused.
    if (Test-Control $d) { return "refused: the release clone's path holds a control character (a newline?): clone it to a plain path" }
    $d = ConvertTo-NativePath $d
    if (-not [IO.Directory]::Exists($d)) { return "release clone $d does not exist" }
    $top = Get-CGitLine -Dir $d -GitArgs @('rev-parse', '--show-toplevel')
    if (-not $top) { return "$d is not a git checkout of the release" }
    if (Test-Control $top) { return "refused: the release clone's path holds a control character (a newline?): clone it to a plain path" }
    $script:cloneTop = $top
    if (-not [IO.File]::Exists($top + '/.sumela/VERSION')) { return "$top is not a SumelaOS release clone (.sumela/VERSION missing)" }
    $v = Read-Version $top
    if (-not (Test-Version $v)) { return "$top/.sumela/VERSION holds '$v', not a release version" }
    $script:cloneTarget = $v
    if (Eq (Get-CGitLine -Dir $top -GitArgs @('rev-parse', '--path-format=absolute', '--git-common-dir')) $script:common) {
        return 'the release clone is this repository: run the runner from your project''s checkout, with --source <clone>'
    }
    $script:cloneHead = Get-CGitLine -Dir $top -GitArgs @('rev-parse', '-q', '--verify', 'HEAD^{commit}')
    if (-not $script:cloneHead) { return "$top has no commit checked out" }
    $st = Invoke-CGit -Dir $top -GitArgs @('status', '--porcelain', '--untracked-files=normal', '--ignore-submodules=none')
    if ($st.ExitCode -ne 0) { return "git cannot read the status of $top" }
    if (@($st.Lines).Count -gt 0) { return "refused: the release clone $top has local changes (git -C <clone> status): " + [string]::Join(' ', @($st.Lines | Select-Object -First 3)) }
    $hidden = @((Invoke-CGit -Dir $top -GitArgs @('ls-files', '-v')).Lines | Where-Object { $_ -cmatch '^[a-zSM] ' } | Select-Object -First 3)
    if ($hidden.Count -gt 0) { return "refused: the release clone $top hides local changes (assume-unchanged or skip-worktree entries): " + [string]::Join(' ', $hidden) }
    $tag = Get-CloneTag $top $v
    if ($tag) { $script:cloneTag = $tag }
    elseif ($script:allowUntagged) { $script:cloneTag = ''; Warn "--allow-untagged: $top is not at an annotated v$v tag (maintainer tests only)" }
    else { return "refused: $top is not at an annotated release tag v$v or v$v-rc.<n> (git -C <clone> checkout v$v; git -C <clone> cat-file -t v$v must print tag)" }
    $origin = Get-CGitLine -Dir $top -GitArgs @('config', '--get', 'remote.origin.url'); if ($null -eq $origin) { $origin = '' }
    if (Eq $mode 'source') {
        $up = Get-UpstreamUrl
        if ($origin -and (Eq (Get-UrlKey $origin) (Get-UrlKey $up))) { $trusted = $up }
        elseif ($origin -and $script:trustOrigin -and (Eq (Get-UrlKey $origin) (Get-UrlKey $script:trustOrigin))) {
            $trusted = $script:trustOrigin
            Warn "--trust-origin: the clone comes from $(Get-ShownUrl $origin), which the user confirmed (this project's upstream is $(Get-ShownUrl $up))"
        } elseif ($script:trustOrigin) {
            return "refused: the release clone comes from $(Get-ShownUrl $origin), not from $(Get-ShownUrl $script:trustOrigin) as --trust-origin says"
        } else {
            return "refused: the release clone comes from $(Get-ShownUrl $origin), not from this project's upstream $(Get-ShownUrl $up) (.sumela/upstream.conf, else $($script:defaultUpstream)): clone the upstream, or pass --trust-origin <url> once the user confirms that source"
        }
        if ($script:cloneTag) {
            # Asked of the trusted URL itself, without credentials (git would print them in its
            # own errors), from outside every repository.
            $lr = Invoke-LsRemote (Remove-UserInfo $trusted) ("refs/tags/$($script:cloneTag)" + '^{}')
            if ($lr.ExitCode -ne 0) { foreach ($l in $lr.Err) { [Console]::Error.WriteLine($l) }; return "refused: cannot ask $(Get-ShownUrl $trusted) for $($script:cloneTag) (git ls-remote failed; the check needs the network)" }
            $peeled = ''; if (@($lr.Lines).Count -gt 0) { $peeled = ([regex]::Split([string]$lr.Lines[0], '\s+'))[0] }
            if (-not (Eq $peeled $script:cloneHead)) {
                $said = 'absent'; if ($peeled) { $said = $peeled }
                return "refused: $(Get-ShownUrl $trusted) says $($script:cloneTag) is $said, but the clone's HEAD is $($script:cloneHead)"
            }
        }
    } else {
        $rec = [string](Get-StateValue 'url')
        if (-not (Eq (Get-UrlKey $origin) (Get-UrlKey $rec))) { return "refused: the release clone's origin is now $(Get-ShownUrl $origin), not $(Get-ShownUrl $rec) as plan --source recorded" }
        $rec = [string](Get-StateValue 'commit')
        if ($rec -and -not (Eq $rec $script:cloneHead)) { return "refused: the release clone's HEAD is $($script:cloneHead), not $rec as plan --source recorded" }
    }
    $script:cloneUrl = Remove-UserInfo $origin
    return $null
}
function Test-Clone([string]$d, [string]$mode) { $m = Get-CloneProblem $d $mode; if ($m) { Die $m } }
function Invoke-Reclone([string]$d) {
    $url = Get-StateValue 'url'
    if (-not $url) { $url = Get-UpstreamUrl }
    $tag = Get-StateValue 'tag'; if (-not $tag) { $tag = 'v' + (Get-StateValue 'target') }
    Say "the release clone $d is missing: cloning $(Remove-UserInfo $url) at $tag again"
    $saved = $env:GIT_ALLOW_PROTOCOL
    if (-not $env:GIT_ALLOW_PROTOCOL) { $env:GIT_ALLOW_PROTOCOL = 'https:ssh:git' }
    try { $r = Invoke-Git -Dir '' -GitArgs @('clone', '--branch', $tag, '--', (ConvertTo-NativePath $url), (ConvertTo-NativePath $d)) } finally { $env:GIT_ALLOW_PROTOCOL = $saved }
    foreach ($l in @($r.Err)) { if ($l) { [Console]::Error.WriteLine($l) } }
    if ($r.ExitCode -ne 0) { Die "cannot clone $(Remove-UserInfo $url) at $tag into $d" }
}

# --- Procedural steps (ledger: none) ---------------------------------------------------------------
function Get-ProcList {
    if (-not [IO.File]::Exists($script:stateFile)) { return @() }
    $v = Get-StateValue 'procedural'; if (-not $v) { return @() }
    return @([regex]::Split($v.Trim(), ' +') | Where-Object { $_ })
}
function Get-ProcStatus([string]$name) {
    $out = ''
    foreach ($e in (Get-ProcList)) { $p = $e.IndexOf(':'); if (($p -gt 0) -and (Eq $e.Substring(0, $p) $name)) { $out = $e.Substring($p + 1) } }
    return $out
}
function Set-ProcStatus([string]$name, [string]$status) {
    $keep = New-Object System.Collections.Generic.List[string]
    foreach ($e in (Get-ProcList)) { $p = $e.IndexOf(':'); if (-not (($p -gt 0) -and (Eq $e.Substring(0, $p) $name))) { $keep.Add($e) } }
    if (-not (Eq $status '-')) { $keep.Add($name + ':' + $status) }
    Write-State @('procedural=' + [string]::Join(' ', $keep.ToArray()))
}

# --- Selection -----------------------------------------------------------------------------------
$script:from = ''; $script:target = ''; $script:installed = ''; $script:src = ''; $script:runRoot = ''
$script:devLog = ''; $script:haveRepo = $false; $script:repoNote = ''; $script:withSource = $false
$script:repoLoaded = $false; $script:wtOk = $false; $script:wtGone = ''; $script:repoDone = ''
function Get-LedgerFileStatus([string]$f) {
    foreach ($l in [IO.File]::ReadAllText($f, $script:utf8).Split([char]10)) { $x = $l.TrimEnd([char]13); if ($x.StartsWith('status: ', $ord)) { return $x.Substring(8) } }
    return ''
}
function Get-Recorded([string]$scope) {
    # name -> status of every recorded entry (recorded_list in the bash runner)
    $map = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::Ordinal)
    if (Eq $scope 'repo') {
        $d = $script:runRoot + '/.sumela/migrations-applied'
        if ([IO.Directory]::Exists($d)) {
            foreach ($f in [IO.Directory]::GetFiles($d)) { $st = Get-LedgerFileStatus $f; if (-not $st) { $st = 'done' }; $map[[IO.Path]::GetFileName($f)] = $st }
        }
        foreach ($e in (Get-ProcList)) { $p = $e.IndexOf(':'); if ($p -gt 0) { $map[$e.Substring(0, $p)] = $e.Substring($p + 1) } }
    } elseif ($script:devLog -and [IO.File]::Exists($script:devLog)) {
        $last = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::Ordinal)
        foreach ($l in [IO.File]::ReadAllText($script:devLog, $script:utf8).Split([char]10)) {
            $f = $l.TrimEnd([char]13).Split([char]9)
            if ($f.Length -ge 2) { $last[$f[0]] = $f[1] }
        }
        foreach ($k in $last.Keys) { if (-not (Eq $last[$k] 'rolled-back')) { $map[$k] = $last[$k] } }
    }
    return ,$map
}
function Select-Steps([string]$scope) {
    # -> @{ Pending = ordered ids; Declined = ids; Why = id -> recorded|moot|out-of-range|unlisted; Status = id -> recorded status }
    $set = 'dev'; if (Eq $scope 'repo') { $set = 'repo' }
    $rec = Get-Recorded $scope
    $rank = New-Dict; for ($i = 0; $i -lt $script:phases.Length; $i++) { $rank[$script:phases[$i]] = $i + 1 }
    $why = New-Dict; $stat = New-Dict; $pend = New-List; $isp = New-Dict; $key = New-Dict; $dec = New-List
    $from = $script:from; if (-not $from) { $from = '0.0.0' }
    $tgt = $script:target; if (-not $tgt) { $tgt = '0.0.0' }
    $inst = $script:installed; if (-not $inst) { $inst = '0.0.0' }
    $top = $inst; if (Eq $set 'repo') { $top = $tgt }
    foreach ($st in $script:steps) {
        if (-not (Eq $st.Set $set)) { continue }
        $id = $st.Id; $v = $st.Version; if (Eq $st.Origin 'generic') { $v = $tgt }
        $u = Get-Field $st 'until'
        if ($u -and ([string]::CompareOrdinal((Get-VKey $u), (Get-VKey $top)) -le 0)) { $why[$id] = 'moot'; continue }
        $name = $id; if ((Eq $set 'repo') -and (Eq $st.Origin 'generic')) { $name = $id + '@' + $tgt }
        $r = 0; if ($rank.ContainsKey((Get-Field $st 'when'))) { $r = $rank[(Get-Field $st 'when')] }
        $key[$id] = [string]::Format($invariant, '{0}|{1}|{2}', $r, (Get-VKey $v), $id)
        $s = ''; if ($rec.ContainsKey($name)) { $s = $rec[$name] }
        if (Eq $s 'declined') { [void]$dec.Add($id); continue }
        if ($s) { $why[$id] = 'recorded'; $stat[$id] = $s; continue }
        if (Eq $set 'repo') {
            if ((Eq $st.Origin 'version') -and -not (([string]::CompareOrdinal((Get-VKey $from), (Get-VKey $v)) -lt 0) -and ([string]::CompareOrdinal((Get-VKey $v), (Get-VKey $tgt)) -le 0))) { $why[$id] = 'out-of-range'; continue }
            if ((Eq (Get-Field $st 'ledger') 'none') -and -not $script:withSource) { $why[$id] = 'unlisted'; continue }
        } elseif ([string]::CompareOrdinal((Get-VKey $v), (Get-VKey $inst)) -gt 0) { $why[$id] = 'out-of-range'; continue }
        [void]$pend.Add($st); $isp[$id] = $true
    }
    $done = New-Dict; $order = New-Object System.Collections.Generic.List[string]
    for ($out = 0; $out -lt $pend.Count; $out++) {
        $best = $null
        foreach ($st in $pend) {
            if ($done.ContainsKey($st.Id)) { continue }
            $okk = $true
            foreach ($q in [regex]::Split((Get-Field $st 'requires'), '[ ,]+')) {
                if ($q -and $isp.ContainsKey($q) -and -not $done.ContainsKey($q)) { $okk = $false; break }
            }
            if ($okk -and (($null -eq $best) -or ([string]::CompareOrdinal([string]$key[$st.Id], [string]$key[$best.Id]) -lt 0))) { $best = $st }
        }
        if ($null -eq $best) { Die 'the requires of the pending steps form a cycle' }
        $done[$best.Id] = $true; $order.Add($best.Id)
    }
    $decl = New-Object System.Collections.Generic.List[string]
    foreach ($id in (Sort-OrdinalByKey $dec $key)) { $decl.Add($id) }
    return [pscustomobject]@{ Pending = $order; Declined = $decl; Why = $why; Status = $stat }
}
function Sort-OrdinalByKey($ids, $key) {
    $arr = New-Object System.Collections.Generic.List[string]
    foreach ($i in $ids) { $arr.Add([string]$i) }
    $a = $arr.ToArray()
    for ($i = 0; $i -lt $a.Length; $i++) { for ($j = $i + 1; $j -lt $a.Length; $j++) { if ([string]::CompareOrdinal([string]$key[$a[$j]], [string]$key[$a[$i]]) -lt 0) { $x = $a[$i]; $a[$i] = $a[$j]; $a[$j] = $x } } }
    return ,$a
}

# --- Context -------------------------------------------------------------------------------------
function Initialize-Dev {
    # The developer scope reads the notes committed at this checkout's HEAD. Returns 0, 1 or 4.
    $v = Read-Version $script:localRoot
    if ($null -eq $v) { Warn "$($script:localRoot)/.sumela/VERSION is missing"; return 1 }
    if (-not (Test-Version $v)) { Warn "$($script:localRoot)/.sumela/VERSION holds '$v', not a version"; return 1 }
    $script:installed = $v
    $d = Get-SumelaStateDir -Root $script:localRoot
    if (-not $d) { Warn 'no per-developer state directory (scripts/lib/sumela-state.ps1 said why above)'; return 1 }
    $script:devLog = Join-Path $d 'migrations.log'
    return (Import-NotesSet -Set 'dev' -Dir $script:localRoot)
}
function Initialize-Repo([switch]$Offline) {
    # The repo scope reads the state and its verified release clone. $false, with repoNote, when
    # there is no upgrade in progress, when it is complete (repoDone), or (offline) when its clone
    # is unusable.
    if ($script:source) {
        $script:withSource = $true
        $script:target = $script:cloneTarget; $script:src = $script:cloneTop; $script:from = [string](Get-StateValue 'from')
    } else {
        if (-not [IO.File]::Exists($script:stateFile)) { $script:repoNote = 'no upgrade in progress (start one with: plan --source <release clone>)'; return $false }
        $script:target = Get-StateValue 'target'; if ($null -eq $script:target) { Die "$($script:stateFile) has no target: run plan --source <clone> again" }
        if (-not (Test-Version $script:target)) { Die "$($script:stateFile) holds target '$($script:target)', not a version: run plan --source <clone> again" }
        $script:from = Get-StateValue 'from'; if ($null -eq $script:from) { Die "$($script:stateFile) has no from: run plan --source <clone> again" }
        if (Test-MainAtTarget) {
            $script:repoDone = "the main checkout is at v$(Read-Version $script:mainRoot)"
            $script:repoNote = "the upgrade to v$($script:target) is complete ($($script:repoDone))"; return $false
        }
        $clone = Get-StateValue 'clone'; if ($null -eq $clone) { Die "$($script:stateFile) has no clone: run plan --source <clone> again" }
        if (-not [IO.Directory]::Exists($clone)) {
            if ($Offline) { $script:repoNote = "an upgrade to v$($script:target) is recorded, but its release clone $clone is missing (plan clones it again)"; return $false }
            Invoke-Reclone $clone
        }
        $m = Get-CloneProblem $clone 'state'
        if ($m -and $Offline) { $script:repoNote = "an upgrade to v$($script:target) is recorded, but its release clone $clone is unusable: $m"; return $false }
        if ($m) { Die $m }
        if (-not (Eq $script:cloneTarget $script:target)) { Die "the release clone $clone now says v$($script:cloneTarget), the state says v$($script:target): run plan --source <clone>" }
        $script:src = $script:cloneTop
    }
    $script:runRoot = $script:mainRoot
    $wt = Get-StateValue 'worktree'
    if ($wt) {
        $top = Join-Root $wt $script:prefix
        if ([IO.Directory]::Exists($top + '/.sumela')) { $script:runRoot = $top; $script:wtOk = $true }
        else { $script:wtGone = $wt; $script:repoNote = "the recorded upgrade worktree $wt no longer exists: repo steps neither run nor roll back without it" }
    }
    if (-not $script:repoLoaded) {
        $rc = Import-NotesSet -Set 'repo' -Dir $script:src
        if ($rc -eq 4) { if ($Offline) { $script:repoNote = "the release clone's notes are invalid (see above)"; return $false }; exit 4 }
        if ($rc -ne 0) { exit 1 }
        $script:repoLoaded = $true
    }
    $script:haveRepo = $true
    return $true
}
function Initialize-PlanState {
    # plan --source writes or refreshes the state, once the clone and its notes are verified.
    # Returns 0, or 2 when the install is at the release.
    $clonePath = Slash $script:cloneTop
    if ([IO.File]::Exists($script:stateFile)) {
        $old = [string](Get-StateValue 'target'); $oldCommit = [string](Get-StateValue 'commit'); $wt = [string](Get-StateValue 'worktree')
        if ((Eq $old $script:cloneTarget) -and ((-not $oldCommit) -or (Eq $oldCommit $script:cloneHead))) {
            if ((-not (Eq ([string](Get-StateValue 'clone')) $clonePath)) -or (-not (Eq ([string](Get-StateValue 'tag')) $script:cloneTag))) {
                $suffix = ''; if ($script:cloneTag) { $suffix = " ($($script:cloneTag))" }
                Say "the upgrade to v$($script:cloneTarget) continues from $($script:cloneTop)$suffix"
                Write-State @("clone=$clonePath", "tag=$($script:cloneTag)", "commit=$($script:cloneHead)", "url=$($script:cloneUrl)")
            }
            return 0
        }
        $script:target = $old
        if ((Test-Version $old) -and (Test-MainAtTarget)) { Remove-State "the main checkout is at v$(Read-Version $script:mainRoot)" }
        elseif ($wt -and [IO.Directory]::Exists($wt)) { Die "an upgrade to v$old is in progress in $wt ($($script:stateFile)): finish it (plan), or abandon it (rollback upgrade-01 --confirmed-by-user removes its worktree and branch); once its pull request is merged, update the main checkout and run plan --source again" }
        else {
            Say "replacing the state of the earlier upgrade to v$old (its worktree is gone)"
            [IO.File]::Delete($script:stateFile)
        }
    }
    $script:target = $script:cloneTarget
    $v = Read-Version $script:localRoot
    if ($null -eq $v) { Die "$($script:localRoot)/.sumela/VERSION is missing" }
    if (-not (Test-Version $v)) { Die "$($script:localRoot)/.sumela/VERSION holds '$v', not a version" }
    $c = Compare-Version $v $script:cloneTarget
    if ($c -eq 0) { Say "this install is already at v${v}: no repo steps (a teammate runs the developer steps: plan --scope developer)"; return 2 }
    if ($c -gt 0) { Die "the release clone (v$($script:cloneTarget)) is older than this install (v$v): refusing (a downgrade is update.sh --rollback-to)" }
    Write-State @("from=$v", "target=$($script:cloneTarget)", "tag=$($script:cloneTag)", "commit=$($script:cloneHead)", "clone=$clonePath", "url=$($script:cloneUrl)")
    Say "recorded the upgrade v$v -> v$($script:cloneTarget) in $($script:stateFile)"
    return 0
}

# --- One step --------------------------------------------------------------------------------------
$script:step = $null; $script:sel = $null
function Resolve-Step([string]$id) {
    if (-not $id) { Die "$cmd needs a step id" }
    $devrc = 0; $devErr = ''
    if (-not $id.StartsWith('upgrade-', $ord)) {
        $sw = New-Object System.IO.StringWriter; $saved = [Console]::Error
        [Console]::SetError($sw)
        try { $devrc = Initialize-Dev } finally { [Console]::SetError($saved) }
        $devErr = $sw.ToString()
    }
    $st = $null
    if ($devrc -eq 0) { $st = Find-Step $id 'dev' }
    if ($null -ne $st) {
        $script:stepScope = 'developer'; $script:stepSrc = ''; $script:stepRoot = $script:localRoot; $script:stepTarget = $script:installed
    } else {
        $okRepo = Initialize-Repo
        if ($okRepo) { $st = Find-Step $id 'repo' }
        if ($null -eq $st) {
            if ($devErr) { [Console]::Error.Write($devErr) }
            if ($devrc -ne 0) { exit $devrc }
            if ($script:repoDone) { Die "$($script:repoNote): its repo steps neither run nor roll back any more (after the merge, git revert -m 1 <merge> undoes them)" }
            if ($script:haveRepo) { Die "unknown step ${id}: not in the release clone's notes, nor a developer step installed at $($script:localRoot)" }
            Die "unknown step ${id}: not a developer step installed at $($script:localRoot), and $($script:repoNote)"
        }
        $script:stepScope = 'repo'; $script:stepSrc = $script:src; $script:stepRoot = $script:runRoot; $script:stepTarget = $script:target
    }
    $script:step = $st
    $script:sel = Select-Steps $script:stepScope
    $script:stepState = 'unknown'
    if ($script:sel.Pending.Contains($id)) { $script:stepState = 'pending' }
    elseif ($script:sel.Declined.Contains($id)) { $script:stepState = 'declined' }
    elseif ($script:sel.Why.ContainsKey($id)) { $script:stepState = [string]$script:sel.Why[$id] }
}
function Get-LedgerName($st) { if (Eq $st.Origin 'generic') { return ($st.Id + '@' + $script:target) }; return $st.Id }
function Get-LedgerStatus($st) {
    if ((Eq $script:stepScope 'repo') -and (Eq (Get-Field $st 'ledger') 'none')) { return (Get-ProcStatus (Get-LedgerName $st)) }
    if (Eq $script:stepScope 'repo') {
        $f = $script:runRoot + '/.sumela/migrations-applied/' + (Get-LedgerName $st)
        if (-not [IO.File]::Exists($f)) { return '' }
        return (Get-LedgerFileStatus $f)
    }
    if ($script:devLog -and [IO.File]::Exists($script:devLog)) {
        $s = ''
        foreach ($l in [IO.File]::ReadAllText($script:devLog, $script:utf8).Split([char]10)) { $f = $l.TrimEnd([char]13).Split([char]9); if (($f.Length -ge 2) -and (Eq $f[0] $st.Id)) { $s = $f[1] } }
        return $s
    }
    return ''
}
function Get-StateText {
    $st = $script:step
    if (Eq $script:stepState 'pending') { return 'pending' }
    if (Eq $script:stepState 'declined') { return 'declined (run it when ready)' }
    if (Eq $script:stepState 'recorded') { return ('recorded: ' + (Get-LedgerStatus $st)) }
    if (Eq $script:stepState 'moot') {
        if (Eq $script:stepScope 'repo') { return "moot (until $(Get-Field $st 'until'); the release is v$($script:target))" }
        return "moot (until $(Get-Field $st 'until'); this install is at v$($script:installed))"
    }
    if (Eq $script:stepState 'out-of-range') {
        if (Eq $script:stepScope 'repo') { return "not selected (v$($st.Version) is not in (v$($script:from), v$($script:target)])" }
        return "not selected (v$($st.Version) is above the installed v$($script:installed))"
    }
    if (Eq $script:stepState 'unlisted') { return 'listed only with --source (ledger: none)' }
    return $script:stepState
}
function Get-UnmetRequires {
    # The step's requires that are not recorded done, as "<id> (<why>)" words (unmet_requires).
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($q in [regex]::Split((Get-Field $script:step 'requires').Replace(',', ' '), ' +')) {
        if (-not $q) { continue }
        if ($script:sel.Pending.Contains($q)) { $out.Add("$q (not done yet)"); continue }
        if ($script:sel.Declined.Contains($q)) { $out.Add("$q (declined)"); continue }
        if ($script:sel.Why.ContainsKey($q)) {
            $w = [string]$script:sel.Why[$q]
            if (Eq $w 'recorded') {
                $s = [string]$script:sel.Status[$q]
                if (-not ((Eq $s 'done') -or (Eq $s 'done (pre-satisfied)'))) { $out.Add("$q ($s)") }
            } elseif (Eq $w 'unlisted') {
                $rs = Find-Step $q 'repo'; $nm = $q; if (($null -ne $rs) -and (Eq $rs.Origin 'generic')) { $nm = $q + '@' + $script:target }
                if (-not (Eq (Get-ProcStatus $nm) 'done')) { $out.Add("$q (not done yet)") }
            }
        }
    }
    return [string]::Join(' ', $out.ToArray())
}
function Assert-Worktree {
    # Repo steps run, record and roll back in the upgrade worktree, never in the main checkout,
    # and never after their worktree is gone (need_worktree in the bash runner).
    if (-not (Eq $script:stepScope 'repo')) { return }
    if ($script:wtOk) { return }
    if ($script:wtGone) { Die "the recorded upgrade worktree $($script:wtGone) no longer exists: repo steps neither run, record nor roll back without it (after the merge, git revert -m 1 <merge> undoes the repo steps; to start again, create a worktree and set worktree=<path>)" }
    Die "$($script:step.Id) runs in the upgrade worktree, which upgrade-01 creates: follow upgrade-01's agent: line (set worktree=<path>) first"
}

# --- Running commands ------------------------------------------------------------------------------
function Test-ScriptsBlocked {
    # True when a step's PowerShell process could not run a script: the policy it inherits
    # through PSExecutionPolicyPreference, or (Windows) the effective policy, is Restricted or AllSigned.
    $bad = @('Restricted', 'AllSigned')
    $p = [string]$env:PSExecutionPolicyPreference
    foreach ($b in $bad) { if ([string]::Equals($p, $b, [StringComparison]::OrdinalIgnoreCase)) { return $true } }
    if ($script:onWindows) {
        $e = [string](Get-ExecutionPolicy)
        foreach ($b in $bad) { if ([string]::Equals($e, $b, [StringComparison]::OrdinalIgnoreCase)) { return $true } }
    }
    return $false
}
function Find-GitBash {
    # Git Bash on Windows: <git --exec-path>/../../../bin/bash.exe or .../usr/bin/bash.exe, and
    # nothing else (never bash from PATH: that may be WSL) [RU-I9].
    if (-not $script:onWindows) {
        $c = Get-Command bash -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($c) { return $c.Source }
        return $null
    }
    $exec = Get-GitLine -Dir '' -GitArgs @('--exec-path')
    if (-not $exec) { return $null }
    foreach ($rel in @('../../../bin/bash.exe', '../../../usr/bin/bash.exe')) {
        $p = [IO.Path]::GetFullPath((Join-Path $exec $rel))
        if ([IO.File]::Exists($p)) { return $p }
    }
    return $null
}
function Get-HostExe { return [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName }
function Test-UsesPs([string]$key) { return ((Get-Field $script:step ($key + '.ps1')) -and -not (Test-ScriptsBlocked)) }
function Get-StepLine([string]$key) {
    # -> @{ Line; Raw; Route = powershell|git-bash } for a run/verify/rollback key
    if (Test-UsesPs $key) { $raw = Get-Field $script:step ($key + '.ps1'); return [pscustomobject]@{ Line = (Convert-PsCmd $raw); Raw = $raw; Route = 'powershell' } }
    $raw = Get-Field $script:step $key
    return [pscustomobject]@{ Line = (Convert-Cmd $raw); Raw = $raw; Route = 'git-bash' }
}
function Invoke-StepLine($sl, [switch]$Capture) {
    # Runs a step line from {ROOT} with SUMELA_MIGRATE_SRC and SUMELA_MIGRATE_ROOT set; output is
    # never filtered. The step's own shell enters {ROOT}: no process of the runner sits in it
    # meanwhile (Windows cannot remove a directory a process is in, Git Bash's bin/bash.exe launcher
    # stays where it was started, and upgrade-01's rollback removes {ROOT}); run_line in the bash
    # runner. -> @{ ExitCode; Output } (Output only with -Capture: stdout and stderr, CRs dropped)
    $savedSrc = $env:SUMELA_MIGRATE_SRC; $savedRoot = $env:SUMELA_MIGRATE_ROOT
    $env:SUMELA_MIGRATE_SRC = $script:stepSrc; $env:SUMELA_MIGRATE_ROOT = $script:stepRoot
    $tmp = $script:work + '/step-' + [guid]::NewGuid().ToString('N')
    try {
        if (Eq $sl.Route 'powershell') {
            $hostExe = Get-HostExe
            $shim = ''
            if (-not (Get-Command powershell -CommandType Application -ErrorAction SilentlyContinue)) {
                $shim = "function powershell { & '" + $hostExe.Replace("'", "''") + "' @args }"
            }
            $body = @(
                '$ErrorActionPreference = ''Continue'''
                'try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }'
                'try { Set-Location -LiteralPath $env:SUMELA_MIGRATE_ROOT -ErrorAction Stop } catch { [Console]::Error.WriteLine([string]$_); exit 1 }'
                $shim
                '$global:LASTEXITCODE = 0'
                $sl.Line
                'if (-not $?) { if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; exit 1 }'
                'exit $LASTEXITCODE'
            ) -join "`n"
            $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($body))
            $exe = $hostExe; $argv = @('-NoProfile', '-NonInteractive', '-EncodedCommand', $enc)
        } else {
            $bash = Find-GitBash
            if (-not $bash) { Die 'Git Bash was not found (git --exec-path/../../../bin/bash.exe): install Git for Windows, or run the bash runner' }
            [IO.File]::WriteAllText($tmp + '.sh', "cd `"`$SUMELA_MIGRATE_ROOT`" || exit 1`n" + $sl.Line + "`n", $script:utf8)
            $exe = $bash; $argv = @($tmp + '.sh')
        }
        Push-Location -LiteralPath $script:work
        try {
            if ($Capture) {
                $r = Invoke-Native -Exe $exe -ArgList $argv -Merge
                return [pscustomobject]@{ ExitCode = $r.ExitCode; Output = [string]::Join("`n", $r.Lines).TrimEnd([char]10) }
            }
            # Streamed line by line to stdout: native output inside a function would otherwise
            # become its return value. stderr is not redirected, so it reaches the console as is.
            $ErrorActionPreference = 'Continue'
            & $exe @argv | ForEach-Object { [Console]::Out.WriteLine([string]$_) }
            return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = '' }
        } finally { Pop-Location }
    } finally {
        $env:SUMELA_MIGRATE_SRC = $savedSrc; $env:SUMELA_MIGRATE_ROOT = $savedRoot
        if ([IO.File]::Exists($tmp + '.sh')) { [IO.File]::Delete($tmp + '.sh') }
    }
}
function Write-Env { Out-Line "  (SUMELA_MIGRATE_SRC=$($script:stepSrc) SUMELA_MIGRATE_ROOT=$($script:stepRoot))" }
$script:verifyOut = ''; $script:verifyRc = 0
function Test-Verify {
    # Sets verifyOut and verifyRc; 0 holds, 3 failed, 4 bad expect.
    $sl = Get-StepLine 'verify'
    $exp = Convert-Expect (Get-Field $script:step 'expect')
    $r = Invoke-StepLine $sl -Capture
    $script:verifyRc = $r.ExitCode; $script:verifyOut = $r.Output.Replace([string][char]13, '')
    if ($r.ExitCode -ne 0) { return 3 }
    if (Eq $exp 'exit0') { return 0 }
    if (Eq $exp 'non-empty') { if ($script:verifyOut.Length -gt 0) { return 0 }; return 3 }
    if (Eq $exp 'empty') { if ($script:verifyOut.Length -eq 0) { return 0 }; return 3 }
    if ($exp.StartsWith('equals:', $ord)) { if (Eq $script:verifyOut $exp.Substring(7)) { return 0 }; return 3 }
    if ($exp.StartsWith('match:', $ord)) {
        $re = New-Object System.Text.RegularExpressions.Regex($exp.Substring(6), [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)
        foreach ($l in $script:verifyOut.Split([char]10)) { if ($re.IsMatch($l)) { return 0 } }
        return 3
    }
    return 4
}
function Invoke-VerifyStep {
    $exp = Convert-Expect (Get-Field $script:step 'expect')
    $sl = Get-StepLine 'verify'
    Say "verify $($script:step.Id) in $($script:stepRoot)"
    Out-Line ('  $ ' + $sl.Line)
    $rc = Test-Verify
    if ($script:verifyOut.Length -gt 0) { Out-Line $script:verifyOut }
    if ($rc -eq 0) { Say "verify $($script:step.Id): ok (expect $exp)" }
    elseif ($rc -eq 4) { Warn "verify $($script:step.Id): expect '$exp' is not a valid form" }
    elseif ($script:verifyRc -ne 0) { Warn "verify $($script:step.Id): FAILED (the verify command exited $($script:verifyRc))" }
    else { Warn "verify $($script:step.Id): FAILED (expected $exp; the output is above)" }
    return $rc
}

# --- Ledgers ---------------------------------------------------------------------------------------
function Get-Utc { return [DateTime]::UtcNow.ToString("yyyy'-'MM'-'dd'T'HH':'mm':'ss'Z'", $invariant) }
function Write-Ledger($st, [string]$status) {
    $at = Get-Utc
    if (Eq $script:stepScope 'repo') {
        if (Eq (Get-Field $st 'ledger') 'none') {
            Set-ProcStatus (Get-LedgerName $st) $status
            if (-not (Eq (Get-LedgerStatus $st) $status)) { Die "$($script:stateFile) does not hold $($st.Id) $status after the write" }
            Say "recorded $($st.Id) $status in $($script:stateFile) (ledger: none: no tracked entry)"
            return
        }
        $name = Get-LedgerName $st; $dir = $script:runRoot + '/.sumela/migrations-applied'; $f = $dir + '/' + $name
        [void][IO.Directory]::CreateDirectory($dir)
        $tmp = $f + '.tmp.' + $PID
        try {
            [IO.File]::WriteAllText($tmp, "status: $status`nat: $at`nversion: $($script:target)`n", $script:utf8)
            if ([IO.File]::Exists($f)) { [IO.File]::Replace($tmp, $f, [NullString]::Value) } else { [IO.File]::Move($tmp, $f) }
        } catch { if ([IO.File]::Exists($tmp)) { [IO.File]::Delete($tmp) }; Die "cannot write $f" }
        if (-not (Eq (Get-LedgerStatus $st) $status)) { Die "$f does not hold status $status after the write" }
        try { Add-SumelaRecordFiles -Path @(".sumela/migrations-applied/$name") -Record ($script:runRoot + '/.sumela/.last-update.json') }
        catch { Die "recorded $f, but the provenance record $($script:runRoot)/.sumela/.last-update.json was not updated: $($_.Exception.Message)" }
        Say "recorded $($st.Id) $status in $f (added to the provenance record)"
    } else {
        try { Write-SumelaStateFile -Name 'migrations.log' -Content ($st.Id + "`t" + $status + "`t" + $at + "`n") -Append -Root $script:localRoot }
        catch { Die "cannot append to $($script:devLog): $($_.Exception.Message)" }
        if (-not (Eq (Get-LedgerStatus $st) $status)) { Die "$($script:devLog) does not hold $($st.Id) $status after the write" }
        Say "recorded $($st.Id) $status in $($script:devLog)"
    }
}

# --- Commands ----------------------------------------------------------------------------------------
function Write-Pending([string]$scope, $s) {
    if (Eq $scope 'repo') { $script:stepSrc = $script:src; $script:stepRoot = $script:runRoot; $script:stepTarget = $script:target }
    else { $script:stepSrc = ''; $script:stepRoot = $script:localRoot; $script:stepTarget = $script:installed }
    $set = 'dev'; if (Eq $scope 'repo') { $set = 'repo' }
    foreach ($id in $s.Pending) {
        $st = Find-Step $id $set
        Out-Line ('    ' + $id + '  ' + (Get-Field $st 'when') + '  consent=' + (Get-Field $st 'consent') + '  ' + (Convert-Text (Get-Field $st 'title')))
    }
    if ($s.Declined.Count -gt 0) { Out-Line ('  declined (still to do; run <id> when ready): ' + [string]::Join(' ', $s.Declined.ToArray())) }
}
function Invoke-Plan {
    $wantRepo = -not (Eq $script:scope 'developer'); $wantDev = -not (Eq $script:scope 'repo')
    $repoN = 0; $devN = 0; $first = ''
    Say "plan for $($script:localRoot)"
    if ($wantRepo -and $script:source) {
        Test-Clone $script:source 'source'
        # The clone's notes must pass the lint before anything is recorded.
        $rc = Import-NotesSet -Set 'repo' -Dir $script:cloneTop
        if ($rc -ne 0) { exit $rc }
        $script:repoLoaded = $true
        if ((Initialize-PlanState) -eq 2) { $wantRepo = $false }
    }
    if ($wantRepo) {
        if (Initialize-Repo) {
            $s = Select-Steps 'repo'
            $repoN = $s.Pending.Count
            $tagText = ''; if ($script:cloneTag) { $tagText = " ($($script:cloneTag))" }
            Out-Line "Repo steps: v$($script:from) -> v$($script:target) from $($script:src)$tagText"
            Out-Line "  state: $($script:stateFile)"
            $rootNote = ''; if (-not $script:wtOk) { $rootNote = ' (the main checkout: only upgrade-01 runs here)' }
            Out-Line "  root:  $($script:runRoot)$rootNote"
            if ($script:repoNote) { Out-Line "  note:  $($script:repoNote)" }
            Out-Line "  pending ($repoN, in order):"
            Write-Pending 'repo' $s
            $recd = New-Object System.Collections.Generic.List[string]
            foreach ($st in $script:steps) { if ((Eq $st.Set 'repo') -and $s.Why.ContainsKey($st.Id) -and (Eq ([string]$s.Why[$st.Id]) 'recorded')) { $recd.Add($st.Id) } }
            if ($recd.Count -gt 0) { Out-Line ('  recorded: ' + [string]::Join(' ', $recd.ToArray())) }
            if ($s.Pending.Count -gt 0) { $first = $s.Pending[0] }
            $unl = New-Object System.Collections.Generic.List[string]
            foreach ($st in $script:steps) { if ((Eq $st.Set 'repo') -and $s.Why.ContainsKey($st.Id) -and (Eq ([string]$s.Why[$st.Id]) 'unlisted')) { $unl.Add($st.Id) } }
            if ($unl.Count -gt 0) { Out-Line ('  listed with --source only (ledger: none): ' + [string]::Join(' ', $unl.ToArray())) }
            # The state outlives the last step until the merge reaches the main checkout: the repo
            # rollbacks need it before the merge.
            if (($repoN -eq 0) -and ($unl.Count -eq 0) -and ($s.Declined.Count -eq 0)) {
                if ($script:wtOk) { Out-Line "  every repo step is recorded: merge the upgrade pull request, then update the main checkout (until then, $($script:stateFile) stays for the rollbacks)" }
                else { Remove-State 'every repo step is recorded and the upgrade worktree is gone' }
            }
        } else {
            if ($script:repoDone) { Remove-State $script:repoDone }
            Out-Line "Repo steps: $($script:repoNote)"
        }
    }
    if ($wantDev) {
        $rc = Initialize-Dev
        if ($rc -ne 0) {
            Out-Line 'Developer steps: not read (see above)'
            Out-Line "pending_repo=$repoN pending_developer=?"
            exit $rc
        }
        $s = Select-Steps 'developer'
        foreach ($id in @($s.Pending)) {
            $st = Find-Step $id 'dev'
            $script:step = $st; $script:stepScope = 'developer'; $script:stepSrc = ''; $script:stepRoot = $script:localRoot; $script:stepTarget = $script:installed
            # The read-only gate applies to the line that runs: verify.ps1 when it would be used.
            $sl = Get-StepLine 'verify'
            if (Eq $sl.Route 'powershell') { $ro = Test-ReadOnlyPs $sl.Raw } else { $ro = Test-ReadOnlyCmd $sl.Raw }
            if (-not $ro) { continue }
            if ((Test-Verify) -eq 0) {
                Out-Line "  ${id}: its read-only verify already passes:"
                if ($script:verifyOut.Length -gt 0) { foreach ($l in $script:verifyOut.Split([char]10)) { Out-Line ('    | ' + $l) } }
                Write-Ledger $st 'done (pre-satisfied)'
            }
        }
        $s = Select-Steps 'developer'
        $devN = $s.Pending.Count
        Out-Line "Developer steps (installed v$($script:installed), notes at the HEAD of $($script:localRoot)):"
        Out-Line "  ledger: $($script:devLog)"
        Out-Line "  pending ($devN, in order):"
        Write-Pending 'developer' $s
        if ((-not $first) -and $s.Pending.Count -gt 0) { $first = $s.Pending[0] }
    }
    if ($first) { Out-Line "next: show $first" }
    Out-Line "pending_repo=$repoN pending_developer=$devN"
}
function Get-DeclinedLedgers {
    # Declined repo ledgers in the main checkout, without a release clone (declined_ledgers).
    $n = 0; $v = [string](Read-Version $script:mainRoot)
    $d = $script:mainRoot + '/.sumela/migrations-applied'
    if (-not [IO.Directory]::Exists($d)) { return 0 }
    foreach ($f in [IO.Directory]::GetFiles($d)) {
        $name = [IO.Path]::GetFileName($f)
        $at = $name.IndexOf('@')
        if (($at -ge 0) -and -not (Eq $name.Substring($at + 1) $v)) { continue }
        if (Eq (Get-LedgerFileStatus $f) 'declined') { $n++ }
    }
    return $n
}
function Invoke-Status {
    $repoN = 0; $devN = 0; $repoD = 0; $devD = 0
    if (-not (Eq $script:scope 'developer')) {
        if (Initialize-Repo -Offline) { $s = Select-Steps 'repo'; $repoN = $s.Pending.Count; $repoD = $s.Declined.Count }
        else {
            if ([IO.File]::Exists($script:stateFile) -and -not $script:repoDone) { Warn $script:repoNote }
            $repoD = Get-DeclinedLedgers
        }
    }
    if (-not (Eq $script:scope 'repo')) {
        $rc = Initialize-Dev; if ($rc -ne 0) { exit $rc }
        $s = Select-Steps 'developer'; $devN = $s.Pending.Count; $devD = $s.Declined.Count
    }
    if (Eq $script:scope 'repo') { Out-Line "pending_repo=$repoN"; if ($repoD -gt 0) { Out-Line "declined_repo=$repoD" } }
    elseif (Eq $script:scope 'developer') { Out-Line "pending_developer=$devN"; if ($devD -gt 0) { Out-Line "declined_developer=$devD" } }
    else {
        Out-Line "pending_repo=$repoN pending_developer=$devN"
        if (($repoD -gt 0) -or ($devD -gt 0)) { Out-Line "declined_repo=$repoD declined_developer=$devD" }
    }
}
function Assert-NotTracking([string]$dir, [string]$branch) {
    # The upgrade branch may track only its own remote branch (after git push -u): a branch that
    # tracks the base would let a push land there (refuse_tracking in the bash runner).
    $up = Get-GitLine -Dir $dir -GitArgs @('config', '--get', "branch.$branch.merge")
    if ($up -and -not (Eq $up "refs/heads/$branch")) { Die "the upgrade branch $branch tracks ${up}: a push could land there. Remove its upstream (git branch --unset-upstream $branch), or create the worktree with git worktree add --no-track" }
}
function Invoke-Set {
    if ($script:args2.Count -eq 0) { Die 'set needs <key>=<value> (keys: prefix, base, branch, worktree)' }
    if (-not [IO.File]::Exists($script:stateFile)) { Die 'no upgrade in progress: run plan --source <release clone> first' }
    $t = Get-StateValue 'target'; if ($null -eq $t) { Die "$($script:stateFile) has no target" }
    $pairs = New-Object System.Collections.Generic.List[string]; $derived = ''; $newFrom = ''; $wtTop = ''; $haveBranch = $false
    foreach ($pair in $script:args2) {
        $p = $pair.IndexOf('='); if ($p -lt 0) { Die "set takes <key>=<value>, not '$pair'" }
        $k = $pair.Substring(0, $p); $v = $pair.Substring($p + 1)
        if (Test-Control $v) { Die 'a value is one line of plain characters (this one holds a control character)' }
        if (Eq $k 'prefix') {
            if ((Invoke-Git -Dir '' -GitArgs @('check-ref-format', '--branch', ($v + 'upgrade-' + $t))).ExitCode -ne 0) { Die "prefix '$v' does not make a valid branch name (${v}upgrade-$t)" }
        } elseif (Eq $k 'base') {
            if ($null -eq (Get-GitLine -Dir $script:mainRoot -GitArgs @('rev-parse', '-q', '--verify', ($v + '^{commit}')))) { Die "base '$v' is not a commit in this repository (git fetch first?)" }
        } elseif (Eq $k 'branch') {
            if ((Invoke-Git -Dir '' -GitArgs @('check-ref-format', '--branch', $v)).ExitCode -ne 0) { Die "branch '$v' is not a valid branch name" }
            Assert-NotTracking $script:mainRoot $v
            $haveBranch = $true
        } elseif (Eq $k 'worktree') {
            $v = Resolve-UserPath (ConvertTo-NativePath $v)
            if (-not [IO.Directory]::Exists($v)) { Die "worktree $v does not exist (create it with git worktree add first)" }
            $top = Get-GitLine -Dir $v -GitArgs @('rev-parse', '--show-toplevel'); if (-not $top) { Die "$v is not a git checkout" }
            $common = Get-GitLine -Dir $top -GitArgs @('rev-parse', '--path-format=absolute', '--git-common-dir')
            $gitDir = Get-GitLine -Dir $top -GitArgs @('rev-parse', '--path-format=absolute', '--git-dir')
            if (-not (Eq $common $script:common)) { Die "$v is a checkout of another repository, not a worktree of this one" }
            if (Eq $gitDir $common) { Die "$v is the main checkout: the upgrade runs in a new linked worktree (git worktree add --no-track -b <branch> <path> <base>)" }
            if (-not [IO.Directory]::Exists((Join-Root $top $script:prefix) + '/.sumela')) { Die "$v has no $(Join-Root '.' $script:prefix)/.sumela/ install" }
            $v = Slash $top; $wtTop = $top
            $br = Get-GitLine -Dir $top -GitArgs @('rev-parse', '--abbrev-ref', 'HEAD')
            if ($br -and -not (Eq $br 'HEAD')) { Assert-NotTracking $top $br; $derived = $br }
            $nf = Read-Version (Join-Root $top $script:prefix); if ($nf) { $newFrom = $nf }
        } elseif ((Eq $k 'from') -or (Eq $k 'target') -or (Eq $k 'tag') -or (Eq $k 'commit') -or (Eq $k 'clone') -or (Eq $k 'url')) {
            Die "$k comes from plan --source; set records only confirmed values (prefix, base, branch, worktree)"
        } else { Die "unknown key '$k' (keys: prefix, base, branch, worktree)" }
        $pairs.Add($k + '=' + $v)
    }
    if ((-not $haveBranch) -and $derived) { $pairs.Add('branch=' + $derived) }
    if ($newFrom -and (Test-Version $newFrom) -and -not (Eq $newFrom ([string](Get-StateValue 'from')))) {
        if ((Compare-Version $newFrom $t) -lt 0) { $pairs.Add('from=' + $newFrom); Say "the worktree is at v${newFrom}: the upgrade now starts from v$newFrom" }
        else {
            $ledgers = (Join-Root $wtTop $script:prefix) + '/.sumela/migrations-applied'
            $any = $false; if ([IO.Directory]::Exists($ledgers)) { $any = @([IO.Directory]::GetFiles($ledgers, ('*@' + $t))).Count -gt 0 }
            if (-not $any) { Warn "the worktree is already at v$newFrom (>= v$t): merge the base instead of upgrading (upgrade-02 refuses)" }
        }
    }
    Write-State $pairs.ToArray()
    foreach ($pair in $pairs) { $p = $pair.IndexOf('='); Say ("recorded " + $pair.Substring(0, $p) + '=' + $pair.Substring($p + 1)) }
}
function Invoke-Show([string]$id) {
    Resolve-Step $id
    $st = $script:step
    Out-Line "step: $id ($($script:stepScope), $($st.File):$($st.Line))"
    Out-Line ('status: ' + (Get-StateText))
    $rootNote = ''; if ((Eq $script:stepScope 'repo') -and -not $script:wtOk) { $rootNote = ' (no upgrade worktree yet: only upgrade-01 and verify work here)' }
    Out-Line "root: $($script:stepRoot)$rootNote"
    Write-Env
    $merge = ''; if (Eq $script:stepScope 'repo') { $merge = '   (before the merge only)' }
    foreach ($k in $st.Keys) {
        $v = [string]$st.Map[$k]
        if ((Eq $k 'title') -or (Eq $k 'agent')) { Out-Line ($k + ': ' + (Convert-Text $v)) }
        elseif (Eq $k 'expect') { Out-Line ($k + ': ' + (Convert-Expect $v)) }
        elseif (Eq $k 'rollback.ps1') { Out-Line ($k + ': ' + (Convert-PsCmd $v) + $merge) }
        elseif (Eq $k 'rollback') { Out-Line ($k + ': ' + (Convert-Cmd $v) + $merge) }
        elseif ($k.EndsWith('.ps1', $ord)) { Out-Line ($k + ': ' + (Convert-PsCmd $v)) }
        else { Out-Line ($k + ': ' + (Convert-Cmd $v)) }
    }
    $w = Get-UnmetRequires
    if ($w) { Out-Line "waiting for: $w" }
}
function Assert-Selectable {
    foreach ($ok in @('pending', 'declined', 'recorded', 'unlisted')) { if (Eq $script:stepState $ok) { return } }
    Die "$($script:step.Id) is $(Get-StateText): nothing to do"
}
function Invoke-Run([string]$id) {
    Resolve-Step $id
    Assert-Selectable
    $st = $script:step
    $s = Get-LedgerStatus $st
    if ($s -and -not (Eq $s 'rolled-back')) {
        if (Eq $s 'declined') { Say "$id was recorded declined: running it now" }
        else { Die "$id is already recorded (${s}): nothing to run" }
    }
    $req = Get-UnmetRequires
    if ($req) { Die "$id requires these steps to be recorded done first: $req" }
    $agentOnly = Eq (Get-Field $st 'run') '-'
    # Only upgrade-01, which creates the worktree, is followed from the main checkout: every other
    # repo step, an agent: line included, names {ROOT}, which must be the upgrade worktree.
    if ((-not $agentOnly) -or -not (Eq $id 'upgrade-01')) { Assert-Worktree }
    # Fail closed: anything but none or confirm needs the typed confirmation, run: - steps too.
    $consent = Get-Field $st 'consent'
    if (-not ((Eq $consent 'none') -or (Eq $consent 'confirm'))) {
        Warn "$id needs explicit consent (consent: $consent): the user types the confirmation, then: run $id --confirmed-by-user"
        if (-not $script:confirmed) { exit 2 }
    }
    if ($agentOnly) {
        Say "$id is performed by the agent (run: -): nothing was executed. Follow its agent: line, then: verify $id"
        Out-Line ('agent: ' + (Convert-Text (Get-Field $st 'agent')))
        return
    }
    $sl = Get-StepLine 'run'
    Say "run $id in $($script:stepRoot) (consent: $consent)"
    Out-Line ('  $ ' + $sl.Line)
    Write-Env
    $r = Invoke-StepLine $sl
    if ($r.ExitCode -ne 0) { Stop-Mig 1 "run ${id}: the command exited $($r.ExitCode)" }
    Say "run ${id}: the command exited 0. Next: verify $id"
}
function Invoke-Record([string]$id, [string]$status) {
    if (-not ((Eq $status 'done') -or (Eq $status 'declined') -or (Eq $status 'not-applicable'))) { Die 'record needs done, declined or not-applicable' }
    Resolve-Step $id
    Assert-Selectable
    Assert-Worktree
    if (Eq $status 'done') {
        $req = Get-UnmetRequires
        if ($req) { Die "$id cannot be done before these steps are recorded done: $req" }
        $rc = Invoke-VerifyStep
        if ($rc -ne 0) { Stop-Mig $rc "not recorded: $id is done only when its verify passes" }
    }
    Write-Ledger $script:step $status
}
function Invoke-Rollback([string]$id) {
    Resolve-Step $id
    Assert-Selectable
    $st = $script:step
    if (-not $script:confirmed) { Stop-Mig 2 "rollback changes the checkout: the user confirms, then: rollback $id --confirmed-by-user" }
    if (-not (Get-Field $st 'rollback')) { Die "$id has no rollback line: nothing to undo" }
    Assert-Worktree
    # The ledger entry goes first: the rollback line may need a clean worktree. It comes back if
    # the line fails.
    $proc = ''; $saved = $null; $staged = $false; $rel = ''; $f = ''
    if ((Eq $script:stepScope 'repo') -and (Eq (Get-Field $st 'ledger') 'none')) {
        $proc = Get-LedgerStatus $st
        if ($proc) { Set-ProcStatus (Get-LedgerName $st) '-' }
    } elseif (Eq $script:stepScope 'repo') {
        $rel = '.sumela/migrations-applied/' + (Get-LedgerName $st); $f = $script:runRoot + '/' + $rel
        if ([IO.File]::Exists($f)) {
            $saved = [IO.File]::ReadAllBytes($f)
            $inIndex = (Invoke-Git -Dir $script:runRoot -GitArgs @('ls-files', '--error-unmatch', '--', $rel)).ExitCode -eq 0
            $inHead = (Invoke-Git -Dir $script:runRoot -GitArgs @('cat-file', '-e', ('HEAD:./' + $rel))).ExitCode -eq 0
            if ($inIndex -and -not $inHead) {
                $staged = $true
                if ((Invoke-Git -Dir $script:runRoot -GitArgs @('rm', '-q', '--cached', '--', $rel)).ExitCode -ne 0) { Die "cannot unstage $rel" }
            }
            [IO.File]::Delete($f)
        }
    }
    $sl = Get-StepLine 'rollback'
    Say "rollback $id in $($script:stepRoot)"
    Out-Line ('  $ ' + $sl.Line)
    Write-Env
    $r = Invoke-StepLine $sl
    if ($r.ExitCode -ne 0) {
        if ($proc) { Set-ProcStatus (Get-LedgerName $st) $proc }
        if (($null -ne $saved) -and [IO.Directory]::Exists([IO.Path]::GetDirectoryName($f))) {
            [IO.File]::WriteAllBytes($f, $saved)
            if ($staged) { [void](Invoke-Git -Dir $script:runRoot -GitArgs @('add', '--', $rel)) }
            Say "restored the ledger entry $f"
        }
        Stop-Mig 1 "rollback ${id}: the command exited $($r.ExitCode)"
    }
    if (Eq $script:stepScope 'repo') {
        Say "$id is pending again"
        $wt = [string](Get-StateValue 'worktree')
        if ($wt -and -not [IO.Directory]::Exists((Join-Root $wt $script:prefix) + '/.sumela')) {
            Remove-StateKeys @('worktree', 'branch')
            Say "the rollback removed the upgrade worktree ${wt}: cleared it from $($script:stateFile)"
        }
    } elseif (Get-LedgerStatus $st) { Write-Ledger $st 'rolled-back' }
    Say "rollback ${id}: done"
}

# --- Dispatch ----------------------------------------------------------------------------------------
$code = 0
try {
    if ((-not $cmd) -or (Eq $cmd 'help')) { Show-Usage; if ($cmd) { exit 0 }; exit 1 }
    if (Eq $cmd 'lint') {
        $files = New-Object System.Collections.Generic.List[string]
        foreach ($a in $script:args2) { $files.Add($a) }
        if ($files.Count -eq 0) {
            $nd = Join-Path $script:scriptDir 'sumela-migrations'
            if ([IO.Directory]::Exists($nd)) {
                $all = [IO.Directory]::GetFiles($nd, '*.md'); [Array]::Sort($all, [StringComparer]::Ordinal)
                foreach ($f in $all) { $files.Add((Slash $f)) }
            }
            if ($files.Count -eq 0) { Die "no notes files in $nd/" }
        }
        exit (Invoke-Lint -Files $files.ToArray())
    }
    $known = @('plan', 'status', 'set', 'show', 'run', 'verify', 'record', 'rollback')
    $isKnown = $false; foreach ($k in $known) { if (Eq $cmd $k) { $isKnown = $true } }
    if (-not $isKnown) { Warn "unknown command: $cmd"; Show-Usage; exit 1 }
    foreach ($lib in @('sumela-state.ps1', 'sumela-provenance.ps1')) {
        $lp = Join-Path (Join-Path $script:scriptDir 'lib') $lib
        if (-not [IO.File]::Exists($lp)) { Die "missing $lp" }
        . $lp
    }
    if (-not (Get-Command git -CommandType Application -ErrorAction SilentlyContinue)) { Die 'git is required' }
    Initialize-Location
    $n = $script:args2.Count
    $a0 = ''; if ($n -gt 0) { $a0 = $script:args2[0] }
    if (Eq $cmd 'plan') { if ($n -ne 0) { Die 'plan takes no arguments' }; Invoke-Plan }
    elseif (Eq $cmd 'status') { if ($n -ne 0) { Die 'status takes no arguments' }; Invoke-Status }
    elseif (Eq $cmd 'set') { Invoke-Set }
    elseif (Eq $cmd 'show') { if ($n -ne 1) { Die 'show needs one step id' }; Invoke-Show $a0 }
    elseif (Eq $cmd 'run') { if ($n -ne 1) { Die 'run needs one step id' }; Invoke-Run $a0 }
    elseif (Eq $cmd 'verify') { if ($n -ne 1) { Die 'verify needs one step id' }; Resolve-Step $a0; $code = Invoke-VerifyStep }
    elseif (Eq $cmd 'record') { if ($n -ne 2) { Die 'record needs <id> done|declined|not-applicable' }; Invoke-Record $a0 $script:args2[1] }
    elseif (Eq $cmd 'rollback') { if ($n -ne 1) { Die 'rollback needs one step id' }; Invoke-Rollback $a0 }
} finally {
    # Its own temporary directory: a failure to remove it is reported, and changes no exit code.
    try { Remove-Tree $script:work } catch { Warn "could not remove the temporary directory $($script:work): $($_.Exception.Message)" }
}
exit $code
