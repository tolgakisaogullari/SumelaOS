# sumela-token-report.ps1 - run scripts/sumela-token-report.py with the first Python >= 3.9.
#
# The PowerShell twin of sumela-token-report.sh, for Windows PowerShell 5.1 and pwsh 7. The token
# report (SumelaOS v0.20.0+) is an optional tool: Python 3.9 or later, the standard library only,
# always run isolated (-I). It runs on demand only, never from a git hook, the bootstrap or CI.
# It reads this install's local Claude Code transcripts, makes no network call, writes no file
# and prints aggregates (ASCII) to stdout. The options and the privacy contract:
#   powershell -File scripts\sumela-token-report.ps1 --help
#   (the header of scripts/sumela-token-report.py documents every section and metric)
#
# Python is probed in order: python3, py -3, python; each must report 3.9 or later (the Microsoft
# Store "python3" stub fails the probe). PYTHONUTF8=1 is set for child processes, and -X utf8 is
# passed (python -I ignores PYTHON* variables). The script runs under the invariant culture.
#
# Exit codes: the report's own (0 printed; 2 degraded: no transcripts, another IDE or no session
# in the window, with a --static hint; 1 could not run); 1 with
# "optional tool: needs Python >=3.9" when no suitable Python is on PATH.

$ErrorActionPreference = 'Continue'
[Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::InvariantCulture
[Threading.Thread]::CurrentThread.CurrentUICulture = [Globalization.CultureInfo]::InvariantCulture

$reportArgs = @($args)
$script = Join-Path $PSScriptRoot 'sumela-token-report.py'
if (-not [IO.File]::Exists($script)) {
    [Console]::Error.WriteLine('sumela-token-report: sumela-token-report.py is missing next to this wrapper')
    exit 1
}
# Set for the child process only: a caller that ran .\sumela-token-report.ps1 keeps its own value.
$savedUtf8 = [Environment]::GetEnvironmentVariable('PYTHONUTF8')
function Restore-SumelaPythonUtf8 {
    # [NullString]::Value, never $null: PowerShell passes $null to a .NET string parameter as "",
    # and from .NET 9 an empty value SETS the variable instead of removing it.
    if ($null -eq $savedUtf8) { [Environment]::SetEnvironmentVariable('PYTHONUTF8', [NullString]::Value) }
    else { [Environment]::SetEnvironmentVariable('PYTHONUTF8', [string]$savedUtf8) }
}
$env:PYTHONUTF8 = '1'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }

$probeCode = 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)'
$candidates = @(@('python3'), @('py', '-3'), @('python'))
foreach ($c in $candidates) {
    $name = [string]$c[0]
    $pre = @()
    if ($c.Count -gt 1) { $pre = @($c[1..($c.Count - 1)]) }
    $cmd = Get-Command -Name $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $cmd) { continue }
    $exe = [string]$cmd.Path
    $ok = $false
    try {
        # The probe's own output is not the report's (the Store stub prints an install hint).
        $null = & $exe @pre -I -c $probeCode 2>&1
        $ok = ($LASTEXITCODE -eq 0)
    } catch {
        $ok = $false
    }
    if (-not $ok) { continue }
    try {
        & $exe @pre -I -X utf8 $script @reportArgs
        $code = $LASTEXITCODE
    } finally {
        Restore-SumelaPythonUtf8
    }
    exit $code
}
Restore-SumelaPythonUtf8
[Console]::Error.WriteLine('sumela-token-report: optional tool: needs Python >=3.9 (python3, py -3 or python on PATH)')
exit 1
