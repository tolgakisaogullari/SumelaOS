# sumela-state.ps1 - the per-developer state directory (v0.20.0+). Dot-source it:
#   . (Join-Path $PSScriptRoot 'lib/sumela-state.ps1')
#
# The PowerShell twin of sumela-state.sh, which holds the full contract. Windows PowerShell 5.1
# and pwsh 7; culture-independent: strings are compared ordinally ([string]::Equals with
# Ordinal; never -ceq, which compares linguistically), formatting is invariant.
#
#   Get-SumelaStateDir [-Create] [-Root <install-root>]
#       Returns %LOCALAPPDATA%\sumela\<key> on Windows ($env:OS is Windows_NT), else
#       ${XDG_STATE_HOME:-$HOME/.local/state}/sumela/<key>, the same string sumela_state_dir
#       prints (a relative XDG_STATE_HOME is ignored). -Create makes the directory, mode 0700
#       outside Windows. Returns $null when there is no install root, no git work tree, git
#       refuses the repository (for example "dubious ownership"), git is older than 2.31, or there
#       is no base directory; a warning names every cause but a missing install root.
#   Write-SumelaStateFile -Name <name> [-Content <text>] [-Append] [-Root <install-root>]
#       Writes <state dir>/<name> as UTF-8 without BOM, exactly the given text (mode 0600
#       outside Windows); a replace goes through a temporary file and a rename. <name> is
#       [A-Za-z0-9._-]+ and not "." or "..". Throws on a bad name or a failed write.
#
# The key, exactly as in sumela-state.sh: the first 16 hex characters of the SHA-256 of the
# UTF-8 bytes of "<main checkout>/<install prefix>", where <main checkout> is
# `git rev-parse --path-format=absolute --git-common-dir` minus a trailing "/.git" and
# <install prefix> is `git rev-parse --show-prefix` run from the install root minus its
# trailing "/". The install root is -Root, else the nearest ancestor of the current location
# that holds .sumela/ [RU-M6]. Both git calls run with GIT_DIR, GIT_WORK_TREE, GIT_COMMON_DIR,
# GIT_INDEX_FILE and GIT_PREFIX cleared, so a hook's environment cannot redirect them.

function Invoke-SumelaStateGit {
    # git -C <dir> <args> with UTF-8 output and the hook variables cleared. Returns ExitCode, Lines
    # (stdout) and Err (stderr), CRs dropped. Never throws for a git failure: callers decide, and
    # name git's reason.
    param([string]$Dir, [string[]]$GitArgs)
    $ErrorActionPreference = 'Continue'
    $names = @('GIT_DIR', 'GIT_WORK_TREE', 'GIT_COMMON_DIR', 'GIT_INDEX_FILE', 'GIT_PREFIX')
    $saved = @{}
    foreach ($n in $names) {
        $saved[$n] = [Environment]::GetEnvironmentVariable($n)
        # [NullString]::Value, never $null: PowerShell passes $null to a .NET string parameter as
        # "", and from .NET 9 an empty value SETS the variable (GIT_DIR="" breaks every git call).
        [Environment]::SetEnvironmentVariable($n, [NullString]::Value)
    }
    $prevEnc = $null
    $all = $null
    $code = 1
    $failure = $null
    try {
        try {
            $prevEnc = [Console]::OutputEncoding
            [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
        } catch { $prevEnc = $null }
        $all = & git -C $Dir @GitArgs 2>&1
        $code = $LASTEXITCODE
    } catch {
        $code = 127
        $failure = $_.Exception.Message
    } finally {
        if ($null -ne $prevEnc) { try { [Console]::OutputEncoding = $prevEnc } catch { } }
        foreach ($n in $names) {
            if ($null -eq $saved[$n]) { [Environment]::SetEnvironmentVariable($n, [NullString]::Value) }
            else { [Environment]::SetEnvironmentVariable($n, [string]$saved[$n]) }
        }
    }
    $lines = New-Object System.Collections.Generic.List[string]
    $err = New-Object System.Collections.Generic.List[string]
    if ($null -ne $failure) { $err.Add([string]$failure) }
    foreach ($o in @($all)) {
        if ($null -eq $o) { continue }
        if ($o -is [System.Management.Automation.ErrorRecord]) { $err.Add(([string]$o).TrimEnd([char]13)) }
        else { $lines.Add(([string]$o).TrimEnd([char]13)) }
    }
    return [pscustomobject]@{ ExitCode = $code; Lines = $lines.ToArray(); Err = $err.ToArray() }
}

function Get-SumelaStateGitReason {
    # git's first non-blank stderr line, for a one-line warning.
    param($Result)
    foreach ($l in @($Result.Err)) { if ($l -cmatch '\S') { return [string]$l } }
    return "git exited with code $($Result.ExitCode) and gave no reason"
}

function Get-SumelaInstallRoot {
    # -Root as given (made absolute), else the nearest ancestor of the current location that
    # holds .sumela/. $null when there is none.
    param([string]$Root)
    $here = (Get-Location -PSProvider FileSystem).ProviderPath
    if ($Root) {
        $p = $Root
        if (-not [IO.Path]::IsPathRooted($p)) { $p = Join-Path $here $p }
        if ([IO.Directory]::Exists((Join-Path $p '.sumela'))) { return $p }
        return $null
    }
    $p = $here
    while ($p) {
        if ([IO.Directory]::Exists((Join-Path $p '.sumela'))) { return $p }
        $parent = [IO.Path]::GetDirectoryName($p)
        if ((-not $parent) -or [string]::Equals($parent, $p, [StringComparison]::Ordinal)) { break }
        $p = $parent
    }
    return $null
}

function Test-SumelaStateOnWindows {
    return [string]::Equals([string]$env:OS, 'Windows_NT', [StringComparison]::Ordinal)
}

function Set-SumelaUnixMode {
    # Outside Windows only: set a POSIX mode (448 = 0700, 384 = 0600). pwsh 7.3+ has the .NET
    # API; older pwsh falls back to chmod. Windows PowerShell never gets here.
    param([string]$Path, [int]$Mode)
    if (Test-SumelaStateOnWindows) { return }
    $modeType = 'System.IO.UnixFileMode' -as [type]
    if ($null -ne $modeType) {
        [IO.File]::SetUnixFileMode($Path, [Enum]::ToObject($modeType, $Mode))
    } else {
        & chmod ([Convert]::ToString($Mode, 8)) $Path
        if ($LASTEXITCODE -ne 0) { throw "chmod failed on $Path" }
    }
}

function Get-SumelaStateDir {
    [CmdletBinding()]
    param([switch]$Create, [string]$Root)
    $installRoot = Get-SumelaInstallRoot -Root $Root
    if (-not $installRoot) { return $null }
    $r = Invoke-SumelaStateGit -Dir $installRoot -GitArgs @('rev-parse', '--path-format=absolute', '--git-common-dir')
    if ($r.ExitCode -ne 0) {
        Write-Warning ("Get-SumelaStateDir: git cannot read the repository at ${installRoot}: " + (Get-SumelaStateGitReason $r))
        return $null
    }
    # git < 2.31 echoes "--path-format=absolute" back instead of failing: one absolute path or nothing.
    if (@($r.Lines).Count -ne 1) {
        Write-Warning 'Get-SumelaStateDir: git printed more than one line for --git-common-dir (git 2.31 or later is required)'
        return $null
    }
    $common = [string]$r.Lines[0]
    if ($common -cnotmatch '^(/|[A-Za-z]:/)') {
        Write-Warning "Get-SumelaStateDir: git printed no absolute path for --git-common-dir ('$common'; git 2.31 or later is required)"
        return $null
    }
    $p = Invoke-SumelaStateGit -Dir $installRoot -GitArgs @('rev-parse', '--show-prefix')   # from the INSTALL root [RU-M6]
    if ($p.ExitCode -ne 0) {
        Write-Warning ("Get-SumelaStateDir: git cannot read the repository at ${installRoot}: " + (Get-SumelaStateGitReason $p))
        return $null
    }
    $prefix = ''
    if (@($p.Lines).Count -ge 1) { $prefix = [string]$p.Lines[0] }
    if ($common.EndsWith('/.git', [StringComparison]::Ordinal)) { $common = $common.Substring(0, $common.Length - 5) }
    if ($prefix.EndsWith('/', [StringComparison]::Ordinal)) { $prefix = $prefix.Substring(0, $prefix.Length - 1) }
    $bytes = (New-Object System.Text.UTF8Encoding $false).GetBytes($common + '/' + $prefix)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $hash = $sha.ComputeHash($bytes) } finally { $sha.Dispose() }
    $key = ([BitConverter]::ToString($hash).Replace('-', '')).ToLowerInvariant().Substring(0, 16)

    if (Test-SumelaStateOnWindows) {
        if (-not $env:LOCALAPPDATA) { Write-Warning 'Get-SumelaStateDir: LOCALAPPDATA is not set'; return $null }
        $dir = Join-Path (Join-Path $env:LOCALAPPDATA 'sumela') $key
    } else {
        $base = [string]$env:XDG_STATE_HOME
        if (-not $base.StartsWith('/', [StringComparison]::Ordinal)) { $base = '' }   # the XDG spec: relative is invalid
        if (-not $base) {
            if (-not $env:HOME) { Write-Warning 'Get-SumelaStateDir: neither XDG_STATE_HOME nor HOME is set'; return $null }
            $base = $env:HOME + '/.local/state'
        }
        $dir = $base + '/sumela/' + $key            # plain concatenation: the same string bash prints
    }
    if ($Create) {
        $modeType = 'System.IO.UnixFileMode' -as [type]
        if ((-not (Test-SumelaStateOnWindows)) -and ($null -ne $modeType)) {
            [void][IO.Directory]::CreateDirectory($dir, [Enum]::ToObject($modeType, 448))   # new parents 0700 too, as bash's umask 077
        } else {
            [void][IO.Directory]::CreateDirectory($dir)
        }
        Set-SumelaUnixMode -Path $dir -Mode 448
        if (-not [IO.Directory]::Exists($dir)) { throw "Get-SumelaStateDir: cannot create $dir" }
    }
    return $dir
}

function Write-SumelaStateFile {
    [CmdletBinding()]
    param([string]$Name, [AllowEmptyString()][string]$Content = '', [switch]$Append, [string]$Root)
    # \z, never $: in .NET, $ also matches before a final line feed, so "note`n" would pass.
    $ord = [StringComparison]::Ordinal
    if ((-not $Name) -or ($Name -cnotmatch '^[A-Za-z0-9._-]+\z') -or [string]::Equals($Name, '.', $ord) -or [string]::Equals($Name, '..', $ord)) {
        throw "Write-SumelaStateFile: invalid name '$Name'"
    }
    $dir = Get-SumelaStateDir -Create -Root $Root
    if (-not $dir) { throw 'Write-SumelaStateFile: no state directory (no install root or git work tree)' }
    $path = Join-Path $dir $Name
    $enc = New-Object System.Text.UTF8Encoding $false
    if ($Append) {
        [IO.File]::AppendAllText($path, $Content, $enc)
        Set-SumelaUnixMode -Path $path -Mode 384
    } else {
        $tmp = Join-Path $dir ('.' + $Name + '.sumela-tmp.' + $PID)
        try {
            [IO.File]::WriteAllText($tmp, $Content, $enc)
            Set-SumelaUnixMode -Path $tmp -Mode 384
            if ([IO.File]::Exists($path)) { [IO.File]::Replace($tmp, $path, [NullString]::Value) }
            else { [IO.File]::Move($tmp, $path) }
        } catch {
            if ([IO.File]::Exists($tmp)) { [IO.File]::Delete($tmp) }
            throw "Write-SumelaStateFile: cannot write ${path}: $($_.Exception.Message)"
        }
    }
    if (-not [IO.File]::Exists($path)) { throw "Write-SumelaStateFile: $path is missing after the write" }
}
