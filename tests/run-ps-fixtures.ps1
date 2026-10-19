<#
.SYNOPSIS
    Runs every tests/test_*.ps1 suite in a child process of the same PowerShell host.

.DESCRIPTION
    The CI "windows" job runs this under Windows PowerShell 5.1 and under pwsh 7, then once more
    under pwsh with -Culture tr-TR, where "I".ToLower() is a dotless i [RU-M2]. tests/smoke.sh
    runs the same suites wherever pwsh is installed; tests/test_fixture_runners.sh tests this file.

    Each suite runs in its own process of this host (from $PSHOME), with -NoProfile, the
    repository root as working directory and stdin closed, so a suite that waits for input fails
    instead of hanging the job. A suite passes when its process exits 0. Without -Culture a
    suite runs exactly as "<host> -NoProfile -File <suite>", the way tests/smoke.sh runs it.

    -Culture <name> runs each suite, and each process a suite starts, under that culture:
      - In the suite process the runner sets the culture (current, UI, and the default for new
        threads) before the suite starts. It keeps the exit codes of -File: "exit N" gives N, an
        uncaught error gives 1, and finishing without "exit" gives 0.
      - A process a suite starts takes its culture from the OS, not from its parent. Outside
        Windows the runner sets LC_ALL for each suite (tr-TR: LC_ALL=tr_TR.UTF-8), and the
        suite's processes inherit it. On Windows the culture is the user's setting: run
        "Set-Culture <name>" first, as the CI job does. Every process started after that takes it.

    Before any suite, a self-check sends two throwaway suites down the same path. One runs
    "exit 3" and must fail with 3. The other prints its culture and must pass. Under -Culture
    that passing suite also starts PowerShell again and ends after a failing native command,
    and both processes must run under the culture. When the culture misses only the process a
    suite starts, the runner stops with exit 2 in CI (CI=true) and prints a warning elsewhere.
    Any other self-check failure stops the run with exit 2 instead of passing.

    What a failing suite printed (its standard output, then "[stderr]" and its standard error)
    is shown in two parts, so a failure far from the end of a long log is never lost. First
    every failure line before the last 60 lines, each with the 6 lines after it, as one excerpt
    of at most 400 lines (a cut says how many lines it left out). Then the last 60 lines. A
    failure line starts with FAIL or FAILED, or holds Exception, Traceback, fatal:, error:,
    [stderr] or a bash "line N:" error; a line that starts with PASS or SKIP never is one.
    "[line N]" gives a block's place in the full log. git's line-ending warnings ("LF will be
    replaced by CRLF") are left out of what is shown and counted on one line. The suite itself
    sees its output unchanged. tests/run-gitbash-fixtures.sh prints the same.

    SUMELA_FIXTURE_LOG_DIR=<dir> saves the full log of each failing suite as <dir>/<suite>.log
    (UTF-8; the CI job uploads that directory).

    Usage:  powershell -NoProfile -File tests/run-ps-fixtures.ps1 [-Culture <name>]
            pwsh -NoProfile -File tests/run-ps-fixtures.ps1 [-Culture <name>]

.NOTES
    Exit 0 = every suite passed, or none exists yet ("0 suites").
    Exit 1 = a suite failed (its failure lines and the tail of its output are printed).
    Exit 2 = a usage error (including a missing or empty -Culture value), an unknown culture, or
             a failed self-check.
    Keep this file ASCII-only: Windows PowerShell 5.1 reads a script without a BOM as ANSI.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The runner formats and compares under the invariant culture, whatever culture it starts in.
$invariant = [System.Globalization.CultureInfo]::InvariantCulture
[System.Threading.Thread]::CurrentThread.CurrentCulture = $invariant
[System.Threading.Thread]::CurrentThread.CurrentUICulture = $invariant
$utf8 = New-Object System.Text.UTF8Encoding $false
# [Console]::OutputEncoding stays untouched: on Windows it is the code page of the console the
# suites share with this process, and a suite must set its own, as every entry point does.

$tailLines = 60
$contextLines = 6     # lines shown after each failure line
$excerptCap = 400     # lines of failure excerpt shown per suite, before its tail
$drainMs = 10000      # how long to wait for a suite's output once its process has exited
$usage = 'usage: run-ps-fixtures.ps1 [-Culture <name>]'

# How a failing suite's output is read (see Write-Excerpt): case-sensitive, culture-invariant.
$rxOptions = [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
$rxFail = New-Object System.Text.RegularExpressions.Regex -ArgumentList '\A[ \t]*FAIL(ED)?([^A-Za-z0-9_]|\z)', $rxOptions
$rxVerdictOk = New-Object System.Text.RegularExpressions.Regex -ArgumentList '\A[ \t]*(PASS|SKIP)([^A-Za-z0-9_]|\z)', $rxOptions
$rxFailure = New-Object System.Text.RegularExpressions.Regex -ArgumentList ('Exception|Traceback|\[stderr\]|' +
    '[Ff][Aa][Tt][Aa][Ll]:|[Ee][Rr][Rr][Oo][Rr]:|: line [0-9]+: '), $rxOptions
$rxEolWarning = New-Object System.Text.RegularExpressions.Regex -ArgumentList ('warning: .*(LF will be replaced by CRLF|CRLF will be replaced by LF)|' +
    '\A[ \t]*The file will have its original line endings in your working directory[ \t]*\z'), $rxOptions

function Exit-Usage([string]$Message) {
    [Console]::Error.WriteLine('run-ps-fixtures: ' + $Message)
    [Console]::Error.WriteLine($usage)
    exit 2
}

function Test-Word([string]$Value, [string[]]$Words) {
    foreach ($w in $Words) { if ([string]::Equals($Value, $w, [System.StringComparison]::OrdinalIgnoreCase)) { return $true } }
    return $false
}

# The arguments are read here, not by a param block. The parameter binder exits 1 on a
# missing value, the same code as a failed suite, and every usage error must exit 2.
$Culture = $null
for ($i = 0; $i -lt $args.Count; $i++) {
    $arg = [string]$args[$i]
    if (Test-Word $arg @('-Culture')) {
        if ($null -ne $Culture) { Exit-Usage '-Culture given twice' }
        $i++
        if ($i -ge $args.Count -or ([string]$args[$i]).Length -eq 0) { Exit-Usage '-Culture needs a culture name, such as tr-TR' }
        $Culture = [string]$args[$i]
    }
    elseif (Test-Word $arg @('-h', '-?', '-Help', '--help')) {
        [Console]::Out.WriteLine($usage)
        [Console]::Out.WriteLine('Runs every tests/test_*.ps1 in a child process of this host; see the header of this file.')
        exit 0
    }
    else { Exit-Usage ('unknown argument: ' + $arg) }
}

$testsDir = $PSScriptRoot
$repoRoot = Split-Path -Parent $testsDir
$onWindows = ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT)
$inCI = [string]::Equals([string]$env:CI, 'true', [System.StringComparison]::OrdinalIgnoreCase)
# Where the full log of each failing suite is saved; empty = nowhere. A path that cannot be used
# is reported when the first log is saved, with the reason.
$logDir = [string]$env:SUMELA_FIXTURE_LOG_DIR
if ($logDir.Length -gt 0) { try { $logDir = [System.IO.Path]::GetFullPath($logDir) } catch { } }

$targetCulture = $null
$suiteLcAll = $null   # outside Windows under -Culture: the LC_ALL each suite process gets
if ($null -ne $Culture) {
    try { $targetCulture = [System.Globalization.CultureInfo]::GetCultureInfo($Culture) }
    catch { Exit-Usage ("unknown culture '" + $Culture + "'") }
    # ICU builds a culture for any well-formed name; accept only one the platform actually knows.
    $known = @([System.Globalization.CultureInfo]::GetCultures([System.Globalization.CultureTypes]::AllCultures) |
        Where-Object { $_.Name -ceq $targetCulture.Name })
    if ($known.Count -eq 0 -or $targetCulture.Name.Length -eq 0) { Exit-Usage ("unknown culture '" + $Culture + "'") }
    if (-not $onWindows) { $suiteLcAll = $targetCulture.Name.Replace('-', '_') + '.UTF-8' }
}

# The same host: powershell.exe for Windows PowerShell, pwsh for PowerShell 7.
if ($PSVersionTable.PSEdition -ceq 'Desktop') { $exeName = 'powershell.exe' }
elseif ($onWindows) { $exeName = 'pwsh.exe' }
else { $exeName = 'pwsh' }
$hostExe = Join-Path $PSHOME $exeName
if (-not [System.IO.File]::Exists($hostExe)) {
    $hostExe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
}

# One argument for ProcessStartInfo.Arguments, quoted by the rule Windows programs and .NET use
# to split a command line: backslashes are literal except before a double quote.
function ConvertTo-ArgumentText([string]$Value) {
    if ($Value.Length -gt 0 -and $Value.IndexOfAny([char[]]" `t`n`v`"") -lt 0) { return $Value }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append([char]34)
    $slashes = 0
    foreach ($ch in $Value.ToCharArray()) {
        if ([int]$ch -eq 92) { $slashes++; continue }
        if ([int]$ch -eq 34) { [void]$sb.Append([char]92, 2 * $slashes + 1) }
        elseif ($slashes -gt 0) { [void]$sb.Append([char]92, $slashes) }
        $slashes = 0
        [void]$sb.Append($ch)
    }
    [void]$sb.Append([char]92, 2 * $slashes)
    [void]$sb.Append([char]34)
    return $sb.ToString()
}

function Invoke-HostChild([string[]]$ArgumentList) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $hostExe
    $psi.Arguments = (@($ArgumentList | ForEach-Object { ConvertTo-ArgumentText $_ }) -join ' ')
    $psi.WorkingDirectory = $repoRoot
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = $utf8
    $psi.StandardErrorEncoding = $utf8
    if ($null -ne $suiteLcAll) { $psi.EnvironmentVariables['LC_ALL'] = $suiteLcAll }
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $proc = [System.Diagnostics.Process]::Start($psi)
    try {
        try { $proc.StandardInput.Close() } catch { }      # EOF: a read gets nothing, never waits
        $outRead = $proc.StandardOutput.ReadToEndAsync()
        $errRead = $proc.StandardError.ReadToEndAsync()
        $proc.WaitForExit()
        $seconds = $clock.Elapsed.TotalSeconds
        # A process the suite left running can hold the pipes open: never wait for it forever.
        $drained = [System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]@($outRead, $errRead), $drainMs)
        $text = ''
        if ($outRead.IsCompleted) { $text = $outRead.Result.TrimEnd([char[]]"`r`n") }
        if ($errRead.IsCompleted -and $errRead.Result.Length -gt 0) { $text += "`n[stderr]`n" + $errRead.Result }
        if (-not $drained) { $text += "`n[run-ps-fixtures: output cut off; a process the suite started still holds it open]" }
        return [pscustomobject]@{ ExitCode = $proc.ExitCode; Output = $text; Seconds = $seconds; Drained = $drained }
    }
    finally { $proc.Dispose() }
}

function Invoke-Suite([string]$Path) {
    if ($null -eq $targetCulture) { return Invoke-HostChild @('-NoProfile', '-File', $Path) }
    $literal = [System.Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent($Path)
    $name = [System.Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent($targetCulture.Name)
    $wanted = "[System.Globalization.CultureInfo]::GetCultureInfo('$name')"
    $command = @(
        "[System.Threading.Thread]::CurrentThread.CurrentCulture = $wanted"
        "[System.Threading.Thread]::CurrentThread.CurrentUICulture = $wanted"
        "[System.Globalization.CultureInfo]::DefaultThreadCurrentCulture = $wanted"
        "[System.Globalization.CultureInfo]::DefaultThreadCurrentUICulture = $wanted"
        "& '$literal'"
        # -File semantics: after "exit N" in the suite $? is false and $LASTEXITCODE is N; a
        # suite that finishes without "exit" passes, whatever a native command left in
        # $LASTEXITCODE; an uncaught error ends this command with exit 1 before these lines.
        'if ($?) { exit 0 }'
        'if (($LASTEXITCODE -is [int]) -and ($LASTEXITCODE -ne 0)) { exit $LASTEXITCODE }'
        'exit 1'
    ) -join '; '
    return Invoke-HostChild @('-NoProfile', '-Command', $command)
}

function Get-Noun([int]$Count) {
    if ($Count -eq 1) { return 'line' }
    return 'lines'
}

# Write-Excerpt <output> <tail lines>: what a suite printed, indented, as the header describes:
# the failure lines before the tail with the lines after each, then the tail.
function Write-Excerpt([string]$Text, [int]$TailCount) {
    $all = $Text.TrimEnd([char[]]"`r`n")
    if ($all.Length -eq 0) { Write-Host '    (no output)'; return }
    $raw = $all -split "\r?\n"
    $lines = New-Object 'System.Collections.Generic.List[string]'
    $numbers = New-Object 'System.Collections.Generic.List[int]'     # each line's place in the full log
    $warnings = 0
    for ($i = 0; $i -lt $raw.Count; $i++) {
        if ((-not $rxFail.IsMatch($raw[$i])) -and $rxEolWarning.IsMatch($raw[$i])) { $warnings++; continue }
        $lines.Add($raw[$i])
        $numbers.Add($i + 1)
    }
    if ($warnings -gt 0) { Write-Host ('    [' + $warnings + ' ' + (Get-Noun $warnings) + ' of git line-ending warnings ("LF will be replaced by CRLF") left out]') }
    $n = $lines.Count
    if ($n -eq 0) { Write-Host '    (no other output)'; return }
    $t = [Math]::Max(0, $n - $TailCount)      # the lines before index $t come before the tail
    $keep = New-Object 'bool[]' $n
    $failure = New-Object 'bool[]' $n
    $found = 0
    for ($i = 0; $i -lt $t; $i++) {
        $s = $lines[$i]
        if (-not ($rxFail.IsMatch($s) -or ((-not $rxVerdictOk.IsMatch($s)) -and $rxFailure.IsMatch($s)))) { continue }
        $found++
        $failure[$i] = $true
        $last = [Math]::Min($i + $contextLines, $t - 1)
        for ($j = $i; $j -le $last; $j++) { $keep[$j] = $true }
    }
    if ($found -gt 0) {
        Write-Host ('    [failure lines before the last ' + $TailCount + ' lines: ' + $found + ', each shown with up to ' + $contextLines + ' lines after it]')
        $shown = 0; $prev = -2; $cut = 0; $cutFailures = 0
        for ($i = 0; $i -lt $t; $i++) {
            if (-not $keep[$i]) { continue }
            if ($shown -ge $excerptCap) {
                $cut++
                if ($failure[$i]) { $cutFailures++ }
                continue
            }
            if ($i -ne $prev + 1) { Write-Host ('    [line ' + $numbers[$i] + ']') }
            Write-Host ('    ' + $lines[$i])
            $shown++
            $prev = $i
        }
        if ($cut -gt 0) {
            Write-Host ('    [the excerpt stops at ' + $excerptCap + ' lines; not shown: ' + $cut + ' more ' + (Get-Noun $cut) +
                ', failure lines among them: ' + $cutFailures + ']')
        }
        Write-Host ('    [the last ' + ($n - $t) + ' lines, from line ' + $numbers[$t] + ']')
    }
    elseif ($t -gt 0) { Write-Host ('    [' + $t + ' earlier ' + (Get-Noun $t) + ' omitted]') }
    for ($i = $t; $i -lt $n; $i++) { Write-Host ('    ' + $lines[$i]) }
}

# Save-Log <suite name> <output>: with SUMELA_FIXTURE_LOG_DIR set, keeps the full log there.
function Save-Log([string]$Name, [string]$Text) {
    if ($logDir.Length -eq 0) { return }
    $path = [System.IO.Path]::Combine($logDir, $Name + '.log')
    try {
        [void][System.IO.Directory]::CreateDirectory($logDir)
        [System.IO.File]::WriteAllText($path, $Text + "`n", $utf8)
        Write-Host ('    [full log: ' + $path + ']')
    }
    catch { Write-Host ('    [could not save the full log as ' + $path + ': ' + $_.Exception.Message + ']') }
}

$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ('sumela-ps-fixtures-' + [System.IO.Path]::GetRandomFileName())
[void][System.IO.Directory]::CreateDirectory($scratch)
$failed = 0
try {
    Write-Host 'PowerShell fixtures (tests/test_*.ps1)'
    Write-Host ('  host:       ' + $hostExe)
    Write-Host ('  PSVersion:  ' + $PSVersionTable.PSVersion.ToString() + ' (' + $PSVersionTable.PSEdition + ')')
    if ($logDir.Length -gt 0) { Write-Host ('  full logs:  ' + $logDir + " (each failing suite's)") }

    # --- Self-check: the path every suite takes must tell a failure from a pass -------------
    $passCanary = Join-Path $scratch 'canary-pass.ps1'
    $failCanary = Join-Path $scratch 'canary-fail.ps1'
    $passText = @'
'probe ' + [System.Globalization.CultureInfo]::CurrentCulture.Name + ' ' + ([int][char]('I'.ToLower())).ToString('X4')
'@
    if ($null -ne $targetCulture) {
        # Only under -Culture: here the exit code after a failing native command is the
        # runner's own bootstrap, and a process the suite starts must get the culture too.
        $passText += "`n" + @'
$exe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
'child ' + (@(& $exe -NoProfile -NonInteractive -Command '[System.Globalization.CultureInfo]::CurrentCulture.Name') -join ' ')
if ($env:OS -ceq 'Windows_NT') { & cmd.exe /d /c 'exit 4' } else { & /bin/sh -c 'exit 4' }
'@
    }
    [System.IO.File]::WriteAllText($passCanary, $passText.Replace("`r`n", "`n") + "`n", $utf8)
    [System.IO.File]::WriteAllText($failCanary, "exit 3`n", $utf8)
    $pass = Invoke-Suite $passCanary
    $fail = Invoke-Suite $failCanary
    $probe = [regex]::Match($pass.Output, '(?m)^probe (\S*) ([0-9A-F]{4})\r?$')
    $child = [regex]::Match($pass.Output, '(?m)^child (.*?)\r?$')
    $problem = ''
    $warning = ''
    if ($fail.ExitCode -ne 3) {
        $problem = 'a suite that runs "exit 3" gave exit ' + $fail.ExitCode
    }
    elseif ($pass.ExitCode -ne 0) {
        if ($null -ne $targetCulture) { $problem = 'a suite that finishes after a failing native command gave exit ' + $pass.ExitCode }
        else { $problem = 'a suite that passes gave exit ' + $pass.ExitCode }
    }
    elseif (-not $probe.Success) {
        $problem = 'the passing suite printed no culture probe'
    }
    elseif ($null -ne $targetCulture) {
        $wantLower = '0069'
        if (@('tr', 'az') -ccontains $targetCulture.TwoLetterISOLanguageName) { $wantLower = '0131' }
        if (($probe.Groups[1].Value -cne $targetCulture.Name) -or ($probe.Groups[2].Value -cne $wantLower)) {
            $problem = 'culture not applied: the suite ran under "' + $probe.Groups[1].Value + '" ("I" lowercases to U+' +
                $probe.Groups[2].Value + '), expected "' + $targetCulture.Name + '" (U+' + $wantLower + ')'
        }
        elseif (-not $child.Success) {
            $problem = 'the passing suite could not start PowerShell again'
        }
        elseif ($child.Groups[1].Value -cne $targetCulture.Name) {
            $childSeen = $child.Groups[1].Value
            if ($childSeen.Length -eq 0) { $childSeen = 'invariant' }
            if ($onWindows) {
                $how = 'a new process takes the user culture from Windows; run "Set-Culture ' + $targetCulture.Name +
                    '" first (the CI job does), then start this runner again'
            }
            else { $how = 'this runner sets LC_ALL=' + $suiteLcAll + ' for each suite, and PowerShell did not take it' }
            $text = 'a process a suite starts runs under "' + $childSeen + '", not "' + $targetCulture.Name + '": ' + $how
            if ($inCI) { $problem = $text } else { $warning = $text }
        }
    }
    if ($problem.Length -gt 0) {
        Write-Host ('  self-check FAILED: ' + $problem)
        Write-Host '  passing suite output:'
        Write-Excerpt $pass.Output 20
        Write-Host '  failing suite output:'
        Write-Excerpt $fail.Output 20
        exit 2
    }
    $seen = $probe.Groups[1].Value
    if ($seen.Length -eq 0) { $seen = 'invariant' }
    $lower = ' ("I" lowercases to U+' + $probe.Groups[2].Value + ')'
    if ($null -eq $targetCulture) {
        Write-Host ('  culture:    ' + $seen + ', the host default' + $lower)
        Write-Host '  self-check: ok (a failing suite gives exit 3, a passing one exit 0)'
    }
    else {
        $where = ' in each suite process'
        if ($warning.Length -eq 0) { $where += ' and in the processes it starts' }
        Write-Host ('  culture:    ' + $seen + $where + $lower)
        if ($null -ne $suiteLcAll) { Write-Host ('  LC_ALL:     ' + $suiteLcAll + ', set for each suite') }
        if ($warning.Length -gt 0) {
            Write-Host ('  WARNING:    ' + $warning)
            Write-Host '              The suites themselves still run under the culture; in CI (CI=true) this stops the run.'
        }
        Write-Host '  self-check: ok (a failing suite gives exit 3, a passing one exit 0, also after a failing native command)'
    }

    # --- The suites ---------------------------------------------------------------------------
    $names = @(Get-ChildItem -LiteralPath $testsDir -File | ForEach-Object { $_.Name } |
        Where-Object { $_ -cmatch '\Atest_[^\\/]*\.ps1\z' })
    [string[]]$suites = $names
    [Array]::Sort($suites, [System.StringComparer]::Ordinal)
    foreach ($name in $suites) {
        $result = Invoke-Suite (Join-Path $testsDir $name)
        $took = '{0:0.0} s' -f $result.Seconds
        if (-not $result.Drained) { $took += ', then ' + ($drainMs / 1000) + ' s waiting for output a process it started holds open' }
        if ($result.ExitCode -eq 0) {
            Write-Host ('  PASS  ' + $name + ' (' + $took + ')')
        }
        else {
            $failed++
            Write-Host ('  FAIL  ' + $name + ' (exit ' + $result.ExitCode + ', ' + $took + ')')
            Save-Log $name $result.Output
            Write-Excerpt $result.Output $tailLines
        }
    }
    if ($suites.Count -eq 0) { Write-Host '0 suites' }
    else { Write-Host ('' + $suites.Count + ' suites, ' + $failed + ' failed') }
}
finally {
    try { [System.IO.Directory]::Delete($scratch, $true) }
    catch { Write-Host ('  note: could not remove ' + $scratch + ': ' + $_.Exception.Message) }
}
if ($failed -gt 0) { exit 1 }
exit 0
