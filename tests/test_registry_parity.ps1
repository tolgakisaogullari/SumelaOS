# tests/test_registry_parity.ps1 - skill-description parity, the PowerShell twin (R1-07).
#
# The Windows-native half of tests/test_registry_parity.sh: the same cases against
# scripts/sumela-registry-parity.ps1, scripts/lib/sumela-registry.ps1 and the PowerShell plugin
# writers.
#   t_check_detects_drift_exit3, t_sync_rewrites_only_target_block (LF, CRLF, no final newline,
#   answers on stdin, as exact bytes with a BOM and CRLF too, no answer, -Only),
#   t_security_routing_drift_is_attention,
#   t_reserved_tag_refused, t_unparseable_is_never_synced, t_malformed_registry_is_never_a_pass,
#   t_unsafe_paths_are_unparseable, t_register_plugin (the one plugin writer, called directly:
#   it covers the setup.ps1 writer on every host), t_sync_stops_at_failed_write,
#   t_writers_copy_verbatim
#   (setup-memory.ps1's Register-Plugin wherever this host can parse it; setup.ps1 wherever its
#   run reaches the plugin step),
#   t_source_repo_parity_zero, t_registry_write_recorded_in_provenance (its carry the blob of the
#   bytes written, CRLF kept), t_usage_and_errors,
#   t_ps51_writer_keeps_utf8 (the writers keep non-ASCII text byte for byte: under Windows
#   PowerShell 5.1, Get-Content and Set-Content would read and write ANSI) [RU-M1],
#   t_line_endings_kept (CRLF, LF and a lone final CR in one registry, through both writers; the
#   CR check refuses a rendering that lost CRs), t_cleanup_removes_read_only_trees (this suite's
#   cleanup clears git's read-only object files first),
#   t_twins_agree (with bash, when there is one: Git Bash on Windows; LF, CRLF and mixed endings;
#   the same answers to both twins: as this host writes text, from a writer that starts stdin with
#   a BOM as Windows PowerShell 5.1 does under code page 65001, and as exact bytes).
# t_validate_fails_in_source_warns_in_consumer is in the bash suite only: validate-structure.sh is
# bash and runs the bash twin.
#
# Labels are ASCII: Windows PowerShell 5.1 reads a BOM-less script in the ANSI code page, so the
# non-ASCII fixture text is built from char codes.
#
# Run:  pwsh -NoProfile -File tests/test_registry_parity.ps1   (or: powershell -NoProfile -File ...)
# Exit 0 = all assertions passed, 1 = a failure (printed above).

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repoRoot = Split-Path -Parent $PSScriptRoot
$tool = Join-Path $repoRoot 'scripts/sumela-registry-parity.ps1'
# Git Bash on Windows takes C:/x/y, not C:\x\y, as a script path.
$toolSh = (Join-Path $repoRoot 'scripts/sumela-registry-parity.sh').Replace('\', '/')
. (Join-Path $repoRoot 'scripts/lib/sumela-registry.ps1')

$script:pass = 0
$script:fail = 0
function Ok([string]$m) { Write-Host "  PASS  $m"; $script:pass++ }
function Bad([string]$m) { Write-Host "  FAIL  $m"; $script:fail++ }
function Skip([string]$m) { Write-Host "  SKIP  $m" }
function Same([string]$label, $expected, $got) {
    if ([string]::Equals([string]$expected, [string]$got, [StringComparison]::Ordinal)) { Ok $label } else { Bad "$label (expected '$expected', got '$got')" }
}
function Has([string]$label, [string]$text, [string]$want) {
    if ($text.IndexOf($want, [StringComparison]::Ordinal) -ge 0) { Ok $label } else { Bad "$label (wanted '$want' in '$text')" }
}
function Hasnt([string]$label, [string]$text, [string]$unwanted) {
    if ($text.IndexOf($unwanted, [StringComparison]::Ordinal) -lt 0) { Ok $label } else { Bad "$label (unwanted '$unwanted')" }
}
$utf8 = New-Object System.Text.UTF8Encoding $false
$latin1 = [System.Text.Encoding]::GetEncoding(28591)
$onWindows = [string]::Equals([string]$env:OS, 'Windows_NT', [StringComparison]::Ordinal)
$hostExe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$LF = [string][char]10
$CR = [string][char]13
# Non-ASCII fixture letters: an em dash, o-umlaut, s-cedilla, g-breve, dotless i, dotted capital I.
$EM = [string][char]0x2014
$TR = [string][char]0x00F6 + ' ' + [string][char]0x015F + ' ' + [string][char]0x011F + ' ' + [string][char]0x0131 + ' ' + [string][char]0x0130
[Environment]::SetEnvironmentVariable('GIT_AUTHOR_DATE', '2026-10-14T00:00:00 +0000')
[Environment]::SetEnvironmentVariable('GIT_COMMITTER_DATE', '2026-10-14T00:00:00 +0000')
[Environment]::SetEnvironmentVariable('SUMELA_SKIP_MEMORY_SETUP', '1')
foreach ($n in @('GIT_DIR', 'GIT_WORK_TREE', 'GIT_COMMON_DIR', 'GIT_INDEX_FILE', 'GIT_PREFIX')) { [Environment]::SetEnvironmentVariable($n, [NullString]::Value) }

function Read-Bytes([string]$Path) { return [IO.File]::ReadAllBytes($Path) }
function Test-SameBytes([string]$A, [string]$B) {
    $x = [IO.File]::ReadAllBytes($A); $y = [IO.File]::ReadAllBytes($B)
    return ($x.Length -eq $y.Length) -and [string]::Equals([Convert]::ToBase64String($x), [Convert]::ToBase64String($y), [StringComparison]::Ordinal)
}
function Unchanged([string]$label, [string]$A, [string]$B) { if (Test-SameBytes $A $B) { Ok $label } else { Bad "$label (the file changed)" } }
function Write-Utf8([string]$Path, [string]$Text) {
    $dir = [IO.Path]::GetDirectoryName($Path)
    if (-not [IO.Directory]::Exists($dir)) { [void][IO.Directory]::CreateDirectory($dir) }
    [IO.File]::WriteAllBytes($Path, $utf8.GetBytes($Text))
}
function Read-Utf8([string]$Path) { return $utf8.GetString([IO.File]::ReadAllBytes($Path)) }
function ConvertTo-Crlf([string]$Path) { Write-Utf8 $Path ((Read-Utf8 $Path).Replace($LF, $CR + $LF)) }
function New-Skill([string]$File, [string]$Name, [string]$Value) {
    Write-Utf8 $File ("---" + $LF + "name: $Name" + $LF + "description: $Value" + $LF + "---" + $LF + $LF + "# $Name" + $LF + $LF + "Body text." + $LF)
}
function tgit {
    $ErrorActionPreference = 'Continue'
    $out = & git @args 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git $($args -join ' ') failed: $out" }
    return $out
}
function Save-All([string]$Dir, [string]$Msg) {
    tgit -C $Dir add -A | Out-Null
    tgit -C $Dir commit -qm $Msg | Out-Null
}

$regBetaLine = 16
function New-Install([string]$Dir) {
    # The bash suite's mkinstall: alpha (non-ASCII), secure-coding-standard and gamma (a single-quoted
    # plugin description) in parity; beta drifted; "gone" an orphaned entry. A git repository with one
    # commit; the provenance record is gitignored.
    New-Skill (Join-Path $Dir '.sumela/skills/alpha/SKILL.md') 'alpha' ('"Use when alpha work starts ' + $EM + ' ' + $TR + '."')
    New-Skill (Join-Path $Dir '.sumela/skills/beta/SKILL.md') 'beta' '"Use when beta work starts (new text)."'
    New-Skill (Join-Path $Dir '.sumela/skills/secure-coding-standard/SKILL.md') 'secure-coding-standard' '"Use whenever code is planned, written or reviewed."'
    New-Skill (Join-Path $Dir '.sumela/memory-plugins/gamma/SKILL.md') 'gamma' "'Use when gamma memory is needed.'"
    $reg = @(
        '<skills_system priority="1">', '<usage>', "A synthetic registry. Match the user's task against each <description>.", '</usage>', '',
        '<available_skills>', '',
        '<skill activation="eager">', '<name>alpha</name>', ('<description>Use when alpha work starts ' + $EM + ' ' + $TR + '.</description>'),
        '<path>.sumela/skills/alpha/SKILL.md</path>', '</skill>', '',
        '<skill activation="lazy">', '<name>beta</name>', '<description>Use when beta work starts (old text).</description>',
        '<path>.sumela/skills/beta/SKILL.md</path>', '</skill>', '',
        '<skill activation="lazy">', '<name>secure-coding-standard</name>', '<description>Use whenever code is planned, written or reviewed.</description>',
        '<path>.sumela/skills/secure-coding-standard/SKILL.md</path>', '</skill>', '',
        '<skill activation="lazy">', '<name>gamma</name>', '<description>Use when gamma memory is needed.</description>',
        '<path>.sumela/memory-plugins/gamma/SKILL.md</path>', '</skill>', '',
        '<skill activation="lazy">', '<name>gone</name>', '<description>An orphaned entry whose skill is not on disk.</description>',
        '<path>.sumela/skills/gone/SKILL.md</path>', '</skill>', '',
        '</available_skills>', '</skills_system>')
    Write-Utf8 (Join-Path $Dir '.sumela/SKILL_REGISTRY.md') (([string]::Join($LF, $reg)) + $LF)
    Write-Utf8 (Join-Path $Dir '.gitignore') ('.sumela/.last-update.json' + $LF)
    tgit -C $Dir init -q -b main | Out-Null
    tgit -C $Dir config user.email t@example.com | Out-Null
    tgit -C $Dir config user.name Test | Out-Null
    tgit -C $Dir config core.autocrlf false | Out-Null
    Save-All $Dir 'init'
    return (Join-Path $Dir '.sumela/SKILL_REGISTRY.md')
}

function ConvertTo-ArgText([string]$Value) {
    # One argument for ProcessStartInfo.Arguments (the rule Windows programs and .NET split by).
    if ($Value.Length -gt 0 -and $Value.IndexOfAny([char[]]" `t`n`v`"") -lt 0) { return $Value }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append([char]34)
    $slashes = 0
    foreach ($ch in $Value.ToCharArray()) {
        if ([int]$ch -eq 92) { $slashes++; continue }
        if ([int]$ch -eq 34) { [void]$sb.Append([char]92, 2 * $slashes + 1); $slashes = 0; [void]$sb.Append($ch); continue }
        if ($slashes -gt 0) { [void]$sb.Append([char]92, $slashes); $slashes = 0 }
        [void]$sb.Append($ch)
    }
    if ($slashes -gt 0) { [void]$sb.Append([char]92, 2 * $slashes) }
    [void]$sb.Append([char]34)
    return $sb.ToString()
}
function ConvertTo-HexText([byte[]]$Bytes) {
    if ($null -eq $Bytes -or $Bytes.Length -eq 0) { return 'nothing' }
    return [string]::Join(' ', @($Bytes | ForEach-Object { ([int]$_).ToString('x2', [System.Globalization.CultureInfo]::InvariantCulture) }))
}
$script:stdinStart = $null
function Invoke-Child {
    # <exe> <args> in <dir>: stdin gets $Stdin as this host writes text to a child (in
    # $StdinEncoding when given: one with a preamble starts stdin with it, as Windows PowerShell 5.1
    # does under console code page 65001), or nothing (end of input at once), or exactly the bytes
    # $StdinBytes; stdout and stderr are decoded as UTF-8. Returns Code, Out (CRs dropped) and Err.
    param([string]$Exe, [string[]]$ArgList, [string]$Dir, [string]$Stdin = '', [hashtable]$Env = @{}, [byte[]]$StdinBytes = $null,
        [System.Text.Encoding]$StdinEncoding = $null)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.Arguments = [string]::Join(' ', @($ArgList | ForEach-Object { ConvertTo-ArgText $_ }))
    $psi.WorkingDirectory = $Dir
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = $utf8
    $psi.StandardErrorEncoding = $utf8
    $ownEncoding = ($null -ne $psi.PSObject.Properties['StandardInputEncoding'])
    $encoding = $utf8
    if ($null -ne $StdinEncoding) { $encoding = $StdinEncoding }
    if ($ownEncoding) { $psi.StandardInputEncoding = $encoding }
    foreach ($k in $Env.Keys) { $psi.EnvironmentVariables[[string]$k] = [string]$Env[$k] }
    # Windows PowerShell 5.1 writes a child's stdin in [Console]::InputEncoding and, as the process
    # starts, that encoding's preamble: a UTF-8 BOM under console code page 65001. Exact bytes need
    # a preamble-free encoding there for the moment of the start, and a given encoding is set there.
    $restore = $null
    if ((-not $ownEncoding) -and (($null -ne $StdinBytes) -or ($null -ne $StdinEncoding))) {
        try { $restore = [Console]::InputEncoding; [Console]::InputEncoding = $encoding } catch { $restore = $null }
    }
    try { $p = [System.Diagnostics.Process]::Start($psi) }
    finally { if ($null -ne $restore) { try { [Console]::InputEncoding = $restore } catch { } } }
    $o = $p.StandardOutput.ReadToEndAsync()
    $e = $p.StandardError.ReadToEndAsync()
    $start = $p.StandardInput.Encoding.GetPreamble()
    if (($null -eq $StdinBytes) -and ($null -eq $StdinEncoding) -and ($null -eq $script:stdinStart)) {
        $script:stdinStart = (ConvertTo-HexText $start) + ' (' + $p.StandardInput.Encoding.WebName + ', code page ' + $p.StandardInput.Encoding.CodePage + ')'
    }
    if ($null -ne $StdinBytes) {
        if ($start.Length -gt 0) {
            # Reported, not thrown: the cases that sent these bytes fail on code -1 and the suite goes on.
            Write-Host "  NOTE  this host started a child's stdin with $(ConvertTo-HexText $start): its exact bytes could not be sent"
            try { $p.Kill() } catch { }
            return [pscustomobject]@{ Code = -1; Out = ''; Err = 'exact stdin bytes could not be sent' }
        }
        $p.StandardInput.BaseStream.Write($StdinBytes, 0, $StdinBytes.Length)
        $p.StandardInput.BaseStream.Flush()
    } elseif ($Stdin.Length -gt 0) { $p.StandardInput.Write($Stdin) }
    $p.StandardInput.Close()
    $p.WaitForExit()
    return [pscustomobject]@{ Code = $p.ExitCode; Out = $o.Result.Replace($CR + $LF, $LF); Err = $e.Result }
}
function Invoke-Tool([string]$Dir, [string[]]$ArgList, [string]$Stdin = '', [byte[]]$StdinBytes = $null, [System.Text.Encoding]$StdinEncoding = $null) {
    return (Invoke-Child -Exe $hostExe -ArgList (@('-NoProfile', '-NonInteractive', '-File', $tool) + $ArgList) -Dir $Dir -Stdin $Stdin -StdinBytes $StdinBytes -StdinEncoding $StdinEncoding)
}
# The bytes of a byte string (one char per byte), for -StdinBytes. $BOM is the UTF-8 BOM's bytes.
function Get-Bytes([string]$ByteString) { return [byte[]]$latin1.GetBytes($ByteString) }
$BOM = [string][char]0xEF + [string][char]0xBB + [string][char]0xBF
function Get-ByteCount([byte[]]$Bytes, [int]$Value) { $n = 0; foreach ($b in $Bytes) { if ($b -eq $Value) { $n++ } }; return $n }
function ConvertTo-Mixed([string]$Path) {
    # The bash suite's to_mixed: lines 1-19 end in CRLF (beta's <description> among them), the
    # others in LF, and the last one in a lone CR instead (no LF). The file ends in LF.
    $parts = $latin1.GetString([IO.File]::ReadAllBytes($Path)).Split([char]10)
    $n = $parts.Length - 1
    $sb = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $n; $i++) {
        [void]$sb.Append($parts[$i])
        if ($i -eq ($n - 1)) { [void]$sb.Append($CR) } elseif ($i -lt 19) { [void]$sb.Append($CR + $LF) } else { [void]$sb.Append($LF) }
    }
    [IO.File]::WriteAllBytes($Path, $latin1.GetBytes($sb.ToString()))
}
function Remove-Tree([string]$Path) {
    # A directory tree, removed. Git marks its object files read-only, and on Windows
    # [IO.Directory]::Delete refuses a read-only file: every file's attributes are cleared first.
    # Returns '' once the tree is gone, else why it is not; never throws.
    $why = ''
    for ($try = 0; $try -lt 3; $try++) {
        if (-not [IO.Directory]::Exists($Path)) { return '' }
        try {
            foreach ($f in [IO.Directory]::GetFiles($Path, '*', [IO.SearchOption]::AllDirectories)) {
                [IO.File]::SetAttributes($f, [IO.FileAttributes]::Normal)
            }
            [IO.Directory]::Delete($Path, $true)
            return ''
        } catch {
            $why = $_.Exception.Message
            Start-Sleep -Milliseconds 300                  # a child that just exited may still hold a file
        }
    }
    return $why
}
function Get-RegValue([string]$Reg, [string]$Name) {
    # The <description> after <name>Name</name>, read here without the library.
    $lines = (Read-Utf8 $Reg).Split([char]10)
    $found = $false
    foreach ($l in $lines) {
        $k = $l.TrimEnd([char]13)
        if ([string]::Equals($k, '<name>' + $Name + '</name>', [StringComparison]::Ordinal)) { $found = $true; continue }
        if ($found -and $k.StartsWith('<description>', [StringComparison]::Ordinal)) { return $k.Substring(13, $k.Length - 27) }
    }
    return $null
}
function Get-Lines([string]$Path) { return (Read-Utf8 $Path).Split([char]10) }
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
function Test-HostParses([string]$File) {
    # Whether this host can run the script at all (Windows PowerShell 5.1 reads BOM-less UTF-8 as ANSI).
    $t = $null; $e = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($File, [ref]$t, [ref]$e)
    return (@($e).Count -eq 0)
}

$work = Join-Path ([IO.Path]::GetTempPath()) ('sumela-parity-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($work)
$work = (Resolve-Path -LiteralPath $work).ProviderPath
Write-Host "Registry and frontmatter parity, PowerShell twin ($($PSVersionTable.PSEdition) $($PSVersionTable.PSVersion), culture $([System.Globalization.CultureInfo]::CurrentCulture.Name))"
try {
    # -----------------------------------------------------------------------------------------
    Write-Host '== t_check_detects_drift_exit3'
    $d = Join-Path $work 'check'; $reg = New-Install $d
    $orig = Join-Path $work 'check.orig'; [IO.File]::Copy($reg, $orig)
    $r = Invoke-Tool $d @('-Check')
    Same '-Check exits 3 on drift' 3 $r.Code
    Has 'the drifted entry is a DRIFT row with its name and path' $r.Out 'DRIFT       beta  .sumela/skills/beta/SKILL.md'
    Has 'the summary counts it; the orphaned entry is skipped, not drift' $r.Out 'sumela-registry-parity: 4 checked, 1 out of parity (1 drift, 0 attention, 0 unparseable), 1 skipped'
    Has 'the fixer is named in this twin''s spelling' $r.Out 'fix: powershell -NoProfile -File scripts/sumela-registry-parity.ps1 -Sync'
    Hasnt 'an entry in parity prints no row (alpha, non-ASCII, byte-identical)' $r.Out 'alpha'
    Hasnt 'the orphaned entry prints no row' $r.Out 'gone'
    Unchanged '-Check writes nothing' $orig $reg
    $none = Invoke-Tool $d @()
    Same 'no flag is -Check' $r.Out $none.Out
    $bashStyle = Invoke-Tool $d @('--check')
    Same 'the bash spelling --check works too' $r.Out $bashStyle.Out
    $r = Invoke-Tool $d @('-Plan')
    Same '-Plan exits 3 on drift' 3 $r.Code
    Has '-Plan prints one diff per drifted entry' $r.Out ('--- a/.sumela/SKILL_REGISTRY.md' + $LF + '+++ b/.sumela/SKILL_REGISTRY.md' + $LF +
        '@@ -16 +16 @@ beta' + $LF + '-<description>Use when beta work starts (old text).</description>' + $LF +
        '+<description>Use when beta work starts (new text).</description>')
    Unchanged '-Plan writes nothing' $orig $reg
    if ([IO.File]::Exists((Join-Path $d '.sumela/.last-update.json'))) { Bad '-Check and -Plan write no provenance record' } else { Ok '-Check and -Plan write no provenance record' }
    New-Skill (Join-Path $d '.sumela/skills/beta/SKILL.md') 'beta' '"Use when beta work starts (old text)."'
    $r = Invoke-Tool $d @('-Check')
    Same 'after a hand fix of the frontmatter: exit 0' 0 $r.Code

    # -----------------------------------------------------------------------------------------
    Write-Host '== t_sync_rewrites_only_target_block'
    $newBeta = '<description>Use when beta work starts (new text).</description>'
    foreach ($variant in @('lf', 'crlf', 'nofinal')) {
        $d = Join-Path $work "sync-$variant"; $reg = New-Install $d
        if ([string]::Equals($variant, 'crlf', [StringComparison]::Ordinal)) {
            ConvertTo-Crlf $reg
            foreach ($s in @('alpha', 'beta', 'secure-coding-standard')) { ConvertTo-Crlf (Join-Path $d ".sumela/skills/$s/SKILL.md") }
            ConvertTo-Crlf (Join-Path $d '.sumela/memory-plugins/gamma/SKILL.md')
            Save-All $d 'crlf'
        }
        if ([string]::Equals($variant, 'nofinal', [StringComparison]::Ordinal)) { Write-Utf8 $reg ((Read-Utf8 $reg).TrimEnd([char]10)); Save-All $d 'nofinal' }
        $orig = Join-Path $work "sync-$variant.orig"; [IO.File]::Copy($reg, $orig)
        $r = Invoke-Tool $d @('-Sync', '-Yes')
        Same "${variant}: -Sync -Yes exits 0" 0 $r.Code
        Has "${variant}: the drifted entry is synced" $r.Out 'synced      beta'
        Has "${variant}: nothing is left" $r.Out '4 checked, 1 synced, 0 out of parity (0 drift, 0 attention, 0 unparseable), 1 skipped'
        $a = Get-Lines $orig; $b = Get-Lines $reg
        $same = ($a.Length -eq $b.Length)
        for ($i = 0; $same -and ($i -lt $a.Length); $i++) {
            if ($i -eq ($regBetaLine - 1)) { continue }
            if (-not [string]::Equals($a[$i], $b[$i], [StringComparison]::Ordinal)) { $same = $false }
        }
        if ($same) { Ok "${variant}: every other byte of the registry is unchanged" } else { Bad "${variant}: every other byte of the registry is unchanged" }
        $want = $newBeta
        if ([string]::Equals($variant, 'crlf', [StringComparison]::Ordinal)) { $want += $CR }
        Same "${variant}: the description line is the frontmatter's text" $want $b[$regBetaLine - 1]
        $r = Invoke-Tool $d @('-Check')
        Same "${variant}: -Check after the sync exits 0" 0 $r.Code
    }
    $bytes = Read-Bytes (Join-Path $work 'sync-nofinal/.sumela/SKILL_REGISTRY.md')
    Same 'nofinal: the missing final newline stays missing' 'False' ([string]($bytes[$bytes.Length - 1] -eq 10))

    $d = Join-Path $work 'answers'; $reg = New-Install $d
    New-Skill (Join-Path $d '.sumela/memory-plugins/gamma/SKILL.md') 'gamma' "'Use when gamma memory is needed (new).'"
    Save-All $d 'gamma drifts'
    $orig = Join-Path $work 'answers.orig'; [IO.File]::Copy($reg, $orig)
    $r = Invoke-Tool $d @('-Sync') ('y' + $LF + 'n' + $LF)
    Same 'answers y then n: exit 3 (one entry left)' 3 $r.Code
    Has 'each entry is asked about' $r.Out 'Sync the registry description of beta from its frontmatter? [y/N] '
    Has 'y syncs the first' $r.Out 'synced      beta'
    Has 'n declines the second' $r.Out 'declined    gamma'
    Same 'beta was rewritten' 'Use when beta work starts (new text).' (Get-RegValue $reg 'beta')
    Same 'gamma was not' 'Use when gamma memory is needed.' (Get-RegValue $reg 'gamma')
    # Answers from a Windows pipe, as exact bytes: CRLF line ends, and the UTF-8 BOM Windows
    # PowerShell 5.1 writes first when the console code page is UTF-8. One of each is trimmed (the
    # answer is read as bytes, not through a decoder that may drop a BOM or keep it); a second CR stays.
    [IO.File]::Copy($orig, $reg, $true)
    $r = Invoke-Tool $d @('-Sync') -StdinBytes (Get-Bytes ($BOM + 'y' + $CR + $LF + 'n' + $CR + $LF))
    Has 'a BOM before y and CRLF after each answer: y still syncs the first' $r.Out 'synced      beta'
    Has '...and n still declines the second' $r.Out 'declined    gamma'
    Same '...beta was rewritten' 'Use when beta work starts (new text).' (Get-RegValue $reg 'beta')
    [IO.File]::Copy($orig, $reg, $true)
    $r = Invoke-Tool $d @('-Sync') -StdinBytes (Get-Bytes ('y' + $CR + $CR + $LF + 'yes'))
    Has 'only one CR is trimmed: y and two CRs declines' $r.Out 'declined    beta'
    Has '...and a last answer without its line end still counts' $r.Out 'synced      gamma'
    [IO.File]::Copy($orig, $reg, $true)
    $r = Invoke-Tool $d @('-Sync')
    Same 'no answer (end of input): exit 3' 3 $r.Code
    Has '...every entry declined' $r.Out 'declined    beta'
    Has '...and the developer-consent route is named' $r.Out 'run powershell -NoProfile -File scripts/sumela-registry-parity.ps1 -Sync -Yes once the developer consents'
    Unchanged '...and nothing written' $orig $reg
    $r = Invoke-Tool $d @('-Sync', '-Yes', '-Only', 'gamma')
    Same '-Only gamma -Sync -Yes: exit 0 for that entry' 0 $r.Code
    Same '...gamma synced' 'Use when gamma memory is needed (new).' (Get-RegValue $reg 'gamma')
    Same '...beta untouched' 'Use when beta work starts (old text).' (Get-RegValue $reg 'beta')

    # -----------------------------------------------------------------------------------------
    Write-Host '== t_security_routing_drift_is_attention'
    $d = Join-Path $work 'attention'; $reg = New-Install $d
    New-Skill (Join-Path $d '.sumela/skills/secure-coding-standard/SKILL.md') 'secure-coding-standard' '"Use whenever code is touched."'
    $extra = ''
    foreach ($s in @('requesting-code-review', 'receiving-code-review', 'verification-before-completion')) {
        New-Skill (Join-Path $d ".sumela/skills/$s/SKILL.md") $s ('"Use when ' + $s + ' applies (new)."')
        $extra += $LF + '<skill activation="lazy">' + $LF + "<name>$s</name>" + $LF + "<description>Use when $s applies.</description>" + $LF +
            "<path>.sumela/skills/$s/SKILL.md</path>" + $LF + '</skill>'
    }
    Write-Utf8 $reg ((Read-Utf8 $reg).Replace('<available_skills>' + $LF, '<available_skills>' + $extra + $LF))
    Save-All $d 'attention'
    $r = Invoke-Tool $d @('-Check')
    Same 'security-routing drift exits 3' 3 $r.Code
    foreach ($s in @('secure-coding-standard', 'requesting-code-review', 'receiving-code-review', 'verification-before-completion')) {
        Has "$s drift is an ATTENTION row" $r.Out "ATTENTION   $s  .sumela/skills/$s/SKILL.md  (security routing: review this diff before it is synced)"
    }
    Has 'beta stays a plain DRIFT row' $r.Out 'DRIFT       beta  '
    Has 'the summary counts attention apart' $r.Out '7 checked, 5 out of parity (1 drift, 4 attention, 0 unparseable), 1 skipped'
    # Either sign is enough: a security-routing name at another path, another name at such a path.
    $d = Join-Path $work 'attention2'; $reg = New-Install $d
    New-Skill (Join-Path $d '.sumela/memory-plugins/verification-before-completion/SKILL.md') 'verification-before-completion' '"Use when done (new)."'
    New-Skill (Join-Path $d '.sumela/skills/receiving-code-review/SKILL.md') 'review-alias' '"Use when feedback arrives (new)."'
    $extra = $LF + '<skill activation="lazy">' + $LF + '<name>verification-before-completion</name>' + $LF + '<description>Use when done.</description>' + $LF +
        '<path>.sumela/memory-plugins/verification-before-completion/SKILL.md</path>' + $LF + '</skill>' + $LF + $LF +
        '<skill activation="lazy">' + $LF + '<name>review-alias</name>' + $LF + '<description>Use when feedback arrives.</description>' + $LF +
        '<path>.sumela/skills/receiving-code-review/SKILL.md</path>' + $LF + '</skill>'
    Write-Utf8 $reg ((Read-Utf8 $reg).Replace('<available_skills>' + $LF, '<available_skills>' + $extra + $LF))
    Save-All $d 'attention2'
    $r = Invoke-Tool $d @('-Check')
    Has 'a security-routing name at another path is ATTENTION' $r.Out 'ATTENTION   verification-before-completion  .sumela/memory-plugins/verification-before-completion/SKILL.md'
    Has 'another name at a security-routing path is ATTENTION' $r.Out 'ATTENTION   review-alias  .sumela/skills/receiving-code-review/SKILL.md'

    # -----------------------------------------------------------------------------------------
    Write-Host '== t_reserved_tag_refused'
    $d = Join-Path $work 'reserved'; $reg = New-Install $d
    New-Skill (Join-Path $d '.sumela/skills/beta/SKILL.md') 'beta' '"Use when </description> ends a block."'
    New-Skill (Join-Path $d '.sumela/memory-plugins/gamma/SKILL.md') 'gamma' '"Use when </skill> ends a block."'
    Save-All $d 'reserved'
    $orig = Join-Path $work 'reserved.orig'; [IO.File]::Copy($reg, $orig)
    $r = Invoke-Tool $d @('-Check')
    Same 'a reserved tag in a frontmatter description: exit 3' 3 $r.Code
    Has 'it is UNPARSEABLE, not DRIFT (</description>)' $r.Out 'UNPARSEABLE beta  .sumela/skills/beta/SKILL.md  (the frontmatter description holds </description> or </skill>'
    Has 'it is UNPARSEABLE, not DRIFT (</skill>)' $r.Out 'UNPARSEABLE gamma  '
    $r = Invoke-Tool $d @('-Sync', '-Yes')
    Same '-Sync -Yes leaves them out of parity: exit 3' 3 $r.Code
    Unchanged '...and never writes them' $orig $reg
    foreach ($case in @(@('set', 'a </description> b'), @('set', 'a </skill> b'), @('set', ('two' + $LF + 'lines')), @('add', 'a </skill> b'))) {
        $code = 0
        try {
            if ([string]::Equals($case[0], 'set', [StringComparison]::Ordinal)) { Set-SumelaRegistryDescription -Registry $reg -SkillPath '.sumela/skills/beta/SKILL.md' -Description $case[1] }
            else { Add-SumelaRegistryEntry -Registry $reg -Name 'x' -SkillPath '.sumela/skills/x/SKILL.md' -Description $case[1] }
        } catch { $code = $_.Exception.Data['SumelaExitCode'] }
        Same "the library refuses '$($case[1].Replace($LF, '\n'))' ($($case[0])) with 4" 4 $code
    }
    $code = 0
    try { Add-SumelaRegistryEntry -Registry $reg -Name 'bad<name' -SkillPath '.sumela/skills/x/SKILL.md' -Description 'ok' } catch { $code = $_.Exception.Data['SumelaExitCode'] }
    Same 'Add-SumelaRegistryEntry refuses a name holding < with 4' 4 $code
    Unchanged 'every refusal left the registry unchanged' $orig $reg
    $tmpLeft = @([IO.Directory]::GetFiles((Join-Path $d '.sumela'), '*sumela-tmp*')).Count
    Same 'no temp file is left behind' 0 $tmpLeft

    # -----------------------------------------------------------------------------------------
    Write-Host '== t_unparseable_is_never_synced'
    $d = Join-Path $work 'unparseable'; $reg = New-Install $d
    Write-Utf8 (Join-Path $d '.sumela/skills/beta/SKILL.md') ('---' + $LF + 'name: beta' + $LF + 'description: >' + $LF + '  Use when beta work starts,' + $LF + '  folded.' + $LF + '---' + $LF)
    New-Skill (Join-Path $d '.sumela/skills/alpha/SKILL.md') 'alpha' '""'
    $g = '<description>Use when gamma memory is needed.</description>'
    Write-Utf8 $reg ((Read-Utf8 $reg).Replace($g + $LF, $g + $LF + '<description>A second description line.</description>' + $LF))
    Save-All $d 'unparseable'
    $orig = Join-Path $work 'unparseable.orig'; [IO.File]::Copy($reg, $orig)
    $r = Invoke-Tool $d @('-Check')
    Same 'unparseable entries: exit 3' 3 $r.Code
    Has 'a folded block scalar is UNPARSEABLE' $r.Out 'UNPARSEABLE beta  .sumela/skills/beta/SKILL.md  (the frontmatter description is not one line'
    Has 'a registry entry with two <description> lines is UNPARSEABLE' $r.Out 'UNPARSEABLE gamma  .sumela/memory-plugins/gamma/SKILL.md  (the registry entry does not hold exactly one <description> line)'
    Has 'an empty frontmatter description is UNPARSEABLE, never copied over the routing text' $r.Out 'UNPARSEABLE alpha  .sumela/skills/alpha/SKILL.md  (the frontmatter description is empty)'
    $r = Invoke-Tool $d @('-Sync', '-Yes')
    Same '-Sync -Yes: exit 3' 3 $r.Code
    Unchanged '...and the registry is untouched' $orig $reg
    $code = 0
    try { Set-SumelaRegistryDescription -Registry $reg -SkillPath '.sumela/memory-plugins/gamma/SKILL.md' -Description 'x' } catch { $code = $_.Exception.Data['SumelaExitCode'] }
    Same 'the library refuses a block without exactly one <description> line (code 1)' 1 $code
    Unchanged '...leaving the registry unchanged' $orig $reg
    # The frontmatter reader, form by form (the bash suite's table).
    $fx = Join-Path $work 'fm'; [void][IO.Directory]::CreateDirectory($fx)
    $bomText = [string][char]0xFEFF
    $forms = @(
        @(0, 'Use when x', ('---' + $LF + 'description: "Use when x"' + $LF + '---' + $LF), 'double quotes'),
        @(0, "it''s", ('---' + $LF + "description: 'it''s'" + $LF + '---' + $LF), 'single quotes, doubled quote kept as written'),
        @(0, 'Use \"x\"', ('---' + $LF + 'description: "Use \"x\""' + $LF + '---' + $LF), 'escapes kept as written'),
        @(0, 'plain text', ('---' + $LF + 'description: plain text  ' + $LF + 'name: n' + $LF + '---' + $LF), 'plain, trailing blanks dropped'),
        @(0, $TR, ('---' + $CR + $LF + 'description: "' + $TR + '"' + $CR + $LF + '---' + $CR + $LF), 'CRLF and non-ASCII'),
        @(0, 'bom', ($bomText + '---' + $LF + 'description: bom' + $LF + '---' + $LF), 'a UTF-8 BOM'),
        @(3, '', ('---' + $LF + 'description: |' + $LF + '  literal' + $LF + '---' + $LF), 'a literal block scalar'),
        @(3, '', ('---' + $LF + 'description:' + $LF + '  on the next line' + $LF + '---' + $LF), 'an empty value'),
        @(3, '', ('---' + $LF + 'description: "opens' + $LF + '  and closes"' + $LF + '---' + $LF), 'a quote that does not close on its line'),
        @(3, '', ('---' + $LF + 'description: plain' + $LF + '  continued' + $LF + '---' + $LF), 'a continuation line'),
        @(1, '', ('---' + $LF + 'name: n' + $LF + '---' + $LF + 'description: in the body' + $LF), 'no description in the frontmatter'),
        @(1, '', ('# no frontmatter' + $LF + 'description: x' + $LF), 'no frontmatter'),
        @(3, '', ('---' + $LF + 'description: "ends \"' + $LF + '---' + $LF), 'an escaped quote does not close its value'),
        @(0, 'ends \\', ('---' + $LF + 'description: "ends \\"' + $LF + '---' + $LF), 'an escaped backslash before the closing quote'),
        @(3, '', ('---' + $LF + 'description: |' + $LF + '---' + $LF), 'a block scalar with no lines'),
        @(3, '', ('---' + $LF + "description: 'ends''" + $LF + '---' + $LF), 'a doubled single quote does not close its value'))
    $i = 0
    foreach ($f in $forms) {
        $i++
        $file = Join-Path $fx "$i.md"
        Write-Utf8 $file $f[2]
        $res = Get-SumelaFmDescription -Path $file
        $val = ''
        if ($null -ne $res.Value) { $val = ConvertFrom-SumelaByteString $res.Value }
        if (($res.Code -eq $f[0]) -and [string]::Equals($val, [string]$f[1], [StringComparison]::Ordinal)) { Ok "frontmatter form $i ($($f[3]))" }
        else { Bad "frontmatter form $i ($($f[3])): code $($res.Code), value [$val]" }
    }

    # -----------------------------------------------------------------------------------------
    Write-Host '== t_malformed_registry_is_never_a_pass'
    # The bash suite's shapes. The skill on disk has drifted, so the only right answers are an
    # UNPARSEABLE row and exit 3; none may count as skipped.
    $p1 = 'the registry entry does not hold exactly one <path> line; a tag line in it is indented, has text around it, or opens another block'
    $aDesc = '<description>Use when a works.</description>'
    $aPath = '<path>.sumela/skills/a/SKILL.md</path>'
    $shapes = @(
        @('indented', (@('<available_skills>', '<skill activation="lazy">', '  <name>a</name>', ('  ' + $aDesc), ('  ' + $aPath), '</skill>', '</available_skills>', '') -join $LF),
          ('UNPARSEABLE -  .sumela/SKILL_REGISTRY.md:2  (' + $p1 + ')')),
        @('trailing', (@('<available_skills>', '<skill activation="lazy">', '<name>a</name>', $aDesc, ($aPath + '  '), '</skill>', '</available_skills>', '') -join $LF),
          ('UNPARSEABLE a  .sumela/SKILL_REGISTRY.md:2  (' + $p1 + ')')),
        @('lost-end', (@('<available_skills>', '<skill activation="lazy">', '<name>a</name>', $aDesc, $aPath, '', '<skill activation="lazy">', '<name>b</name>',
            '<description>B.</description>', '<path>.sumela/skills/b/SKILL.md</path>', '</skill>', '</available_skills>', '') -join $LF),
          ('UNPARSEABLE a  .sumela/skills/a/SKILL.md  (' + $p1 + ')')),
        @('all-indented', (@('  <available_skills>', '  <skill activation="lazy">', '  <name>a</name>', ('  ' + $aDesc), ('  ' + $aPath), '  </skill>', '  </available_skills>', '') -join $LF),
          'UNPARSEABLE -  .sumela/SKILL_REGISTRY.md:2  (a <skill> line the registry grammar does not read: it is indented, or not followed by a space or >)'),
        @('tab-start', (@('<available_skills>', ('<skill' + [string][char]9 + 'activation="lazy">'), '<name>a</name>', $aDesc, $aPath, '</skill>', '</available_skills>', '') -join $LF),
          'UNPARSEABLE -  .sumela/SKILL_REGISTRY.md:2  (a <skill> line the registry grammar does not read'),
        @('loose-description', (@('<available_skills>', '<skill activation="lazy">', '<name>a</name>', '<description>Use when a works (new).</description>', ('   ' + $aDesc), $aPath, '</skill>', '</available_skills>', '') -join $LF),
          'UNPARSEABLE a  .sumela/skills/a/SKILL.md  (a tag line in the registry entry is indented, has text around it, or opens another block)'),
        @('one-line', (@('<available_skills>', ('x <skill activation="lazy"><name>a</name>' + $aDesc + $aPath + '</skill>'), '</available_skills>', '') -join $LF),
          'UNPARSEABLE -  .sumela/SKILL_REGISTRY.md  (the registry holds <skill text but no block its readers can parse)'))
    foreach ($s in $shapes) {
        $n = $s[0]
        $d = Join-Path $work "mal-$n"
        New-Skill (Join-Path $d '.sumela/skills/a/SKILL.md') 'a' '"Use when a works (new)."'
        $reg = Join-Path $d '.sumela/SKILL_REGISTRY.md'
        Write-Utf8 $reg $s[1]
        $orig = Join-Path $work "mal-$n.orig"; [IO.File]::Copy($reg, $orig, $true)
        $r = Invoke-Tool $d @('-Check')
        Same "${n}: exit 3" 3 $r.Code
        Has "${n}: an UNPARSEABLE row" $r.Out $s[2]
        Hasnt "${n}: never a silent skip" $r.Out '0 out of parity'
        $r = Invoke-Tool $d @('-Sync', '-Yes')
        Same "${n}: -Sync -Yes exits 3" 3 $r.Code
        Unchanged "${n}: ...and writes nothing" $orig $reg
    }
    # The writer refuses a block with a loose line itself, whoever calls it.
    $reg = Join-Path $work 'mal-loose-description/.sumela/SKILL_REGISTRY.md'
    $code = 0; $msg = ''
    try { Set-SumelaRegistryDescription -Registry $reg -SkillPath '.sumela/skills/a/SKILL.md' -Description 'Use when a works (newer).' }
    catch { $code = $_.Exception.Data['SumelaExitCode']; $msg = $_.Exception.Message }
    Same 'the library refuses to rewrite a block that holds a loose line (code 1)' 1 $code
    Has '...saying why' $msg 'holds a loose tag line'
    Unchanged '...and leaves the registry as it was' (Join-Path $work 'mal-loose-description.orig') $reg
    $d = Join-Path $work 'mal-orphan'
    Write-Utf8 (Join-Path $d '.sumela/SKILL_REGISTRY.md') ((@('<available_skills>', '<skill activation="lazy">', '<name>gone</name>', '<description>X.</description>',
        '<path>.sumela/skills/gone/SKILL.md</path>', '</skill>', '</available_skills>', '') -join $LF))
    $r = Invoke-Tool $d @('-Check')
    Same 'a well-formed orphaned entry is still skipped: exit 0' 0 $r.Code
    Has '...and counted' $r.Out '0 checked, 0 out of parity (0 drift, 0 attention, 0 unparseable), 1 skipped'

    # -----------------------------------------------------------------------------------------
    Write-Host '== t_unsafe_paths_are_unparseable'
    $d = Join-Path $work 'unsafe'
    $inst = Join-Path $d 'inst'
    [void][IO.Directory]::CreateDirectory((Join-Path $inst '.sumela'))
    New-Skill (Join-Path $d 'outside/SKILL.md') 'outside' '"SECRET OUTSIDE TEXT"'
    $abs = (Join-Path $d 'outside/SKILL.md').Replace('\', '/')
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('<available_skills>')
    foreach ($p in @($abs, '../outside/SKILL.md', '.sumela/../../outside/SKILL.md', 'C:x/SKILL.md', '.sumela\skills\x\SKILL.md', '..')) {
        foreach ($l in @('<skill activation="lazy">', '<name>u</name>', '<description>Old.</description>', ('<path>' + $p + '</path>'), '</skill>')) { $lines.Add($l) }
    }
    $lines.Add('</available_skills>')
    Write-Utf8 (Join-Path $inst '.sumela/SKILL_REGISTRY.md') (([string]::Join($LF, $lines.ToArray())) + $LF)
    $r = Invoke-Tool $inst @('-Plan')
    Same 'paths that leave the install: exit 3' 3 $r.Code
    $rows = @($r.Out.Split([char]10) | Where-Object { $_.StartsWith('UNPARSEABLE u  ', [StringComparison]::Ordinal) -and $_.EndsWith('(the path leaves the install (absolute, or with a .. segment): not read)', [StringComparison]::Ordinal) })
    Same '...each is an UNPARSEABLE row' 6 $rows.Count
    Hasnt '...and the file outside is never read' $r.Out 'SECRET OUTSIDE TEXT'
    Has '...none is skipped' $r.Out '6 checked, 6 out of parity (0 drift, 0 attention, 6 unparseable), 0 skipped'

    # -----------------------------------------------------------------------------------------
    Write-Host '== t_register_plugin'
    # The one plugin writer, called directly: setup.ps1 and setup-memory.ps1 only map its codes,
    # so this covers the setup.ps1 writer on every host.
    $d = Join-Path $work 'plug'; $reg = New-Install $d
    $omega = 'Use when omega memory is needed ' + $EM + ' ' + $TR + '.'
    New-Skill (Join-Path $d '.sumela/memory-plugins/omega/SKILL.md') 'omega' ('"' + $omega + '"')
    Save-All $d 'omega'
    $res = Register-SumelaRegistryPlugin -Root $d -Name 'omega'
    Same 'a new plugin: code 0' 0 $res.Code
    Same '...its entry carries the frontmatter description verbatim' $omega (Get-RegValue $reg 'omega')
    $recText = ''
    if ([IO.File]::Exists((Join-Path $d '.sumela/.last-update.json'))) { $recText = Read-Utf8 (Join-Path $d '.sumela/.last-update.json') }
    Has '...and the write is recorded in the provenance record' $recText ('  "files": [' + $LF + '    ".sumela/SKILL_REGISTRY.md"' + $LF + '  ]')
    $after = Join-Path $work 'plug.after'; [IO.File]::Copy($reg, $after, $true)
    Same 'already registered: code 5' 5 (Register-SumelaRegistryPlugin -Root $d -Name 'omega').Code
    Unchanged '...and nothing written' $after $reg
    Same 'no SKILL.md: code 2' 2 (Register-SumelaRegistryPlugin -Root $d -Name 'missing').Code
    Write-Utf8 (Join-Path $d '.sumela/memory-plugins/multi/SKILL.md') ('---' + $LF + 'name: multi' + $LF + 'description: >' + $LF + '  folded' + $LF + '---' + $LF)
    Same 'a multi-line description: code 3' 3 (Register-SumelaRegistryPlugin -Root $d -Name 'multi').Code
    New-Skill (Join-Path $d '.sumela/memory-plugins/empty/SKILL.md') 'empty' '""'
    Same 'an empty description: code 3' 3 (Register-SumelaRegistryPlugin -Root $d -Name 'empty').Code
    New-Skill (Join-Path $d '.sumela/memory-plugins/tagged/SKILL.md') 'tagged' '"Use when </skill> appears."'
    Same 'a description holding </skill>: code 4' 4 (Register-SumelaRegistryPlugin -Root $d -Name 'tagged').Code
    Unchanged 'every refusal left the registry unchanged' $after $reg
    $n = Join-Path $work 'plug-noreg'; [void][IO.Directory]::CreateDirectory((Join-Path $n '.sumela'))
    Same 'no registry: code 6' 6 (Register-SumelaRegistryPlugin -Root $n -Name 'omega').Code
    $d = Join-Path $work 'plug-crlf'; $reg = New-Install $d; ConvertTo-Crlf $reg
    New-Skill (Join-Path $d '.sumela/memory-plugins/omega/SKILL.md') 'omega' '"Use when omega."'; Save-All $d 'crlf'
    Same 'a CRLF registry: code 0' 0 (Register-SumelaRegistryPlugin -Root $d -Name 'omega').Code
    $all = (Read-Utf8 $reg).Split([char]10)
    $plain = @($all | Select-Object -SkipLast 1 | Where-Object { -not $_.EndsWith($CR, [StringComparison]::Ordinal) }).Count
    Same '...every line still ends with CRLF' 0 $plain
    $d = Join-Path $work 'plug-rec'; $reg = New-Install $d
    New-Skill (Join-Path $d '.sumela/memory-plugins/omega/SKILL.md') 'omega' '"Use when omega."'; Save-All $d 'rec'
    Write-Utf8 (Join-Path $d '.sumela/.last-update.json') ('not a record' + $LF)
    $res = Register-SumelaRegistryPlugin -Root $d -Name 'omega'
    Same 'an unreadable provenance record: code 7 (registered, not recorded)' 7 $res.Code
    Same '...the entry is written' 'Use when omega.' (Get-RegValue $reg 'omega')
    Has '...and the reason is named' $res.Message '.last-update.json'
    $d = Join-Path $work 'plug-notag'
    Write-Utf8 (Join-Path $d '.sumela/SKILL_REGISTRY.md') ('<skills_system>' + $LF + '</skills_system>' + $LF)
    New-Skill (Join-Path $d '.sumela/memory-plugins/omega/SKILL.md') 'omega' '"Use when omega."'
    $res = Register-SumelaRegistryPlugin -Root $d -Name 'omega'
    Same 'a registry without </available_skills>: code 1' 1 $res.Code
    Has '...naming the missing line' $res.Message 'no </available_skills> line'

    # -----------------------------------------------------------------------------------------
    Write-Host '== t_sync_stops_at_failed_write'
    $d = Join-Path $work 'stop'; $reg = New-Install $d
    New-Skill (Join-Path $d '.sumela/memory-plugins/gamma/SKILL.md') 'gamma' "'Use when gamma memory is needed (new).'"
    Save-All $d 'two drift'
    $orig = Join-Path $work 'stop.orig'; [IO.File]::Copy($reg, $orig)
    # Block the write: a read-only registry on Windows (File.Replace refuses it), a read-only
    # .sumela/ elsewhere (no temp file can be created). Root, or a host without either, SKIPs.
    $sumelaDir = Join-Path $d '.sumela'
    if ($onWindows) { (Get-Item -Force -LiteralPath $reg).IsReadOnly = $true } else { & chmod a-w $sumelaDir }
    $r = Invoke-Tool $d @('-Sync', '-Yes')
    if ($onWindows) { (Get-Item -Force -LiteralPath $reg).IsReadOnly = $false } else { & chmod u+w $sumelaDir }
    if ($r.Code -eq 0) {
        Skip 'the failed-write case: this host let the blocked write through (root?)'
    } else {
        Same 'a failed write: exit 1' 1 $r.Code
        Has '...the run says where it stopped' $r.Out 'sumela-registry-parity: stopped at the first failed write (beta); the entries after it were not checked'
        Has '...and counts that entry as left' $r.Out '2 checked, 0 synced, 1 out of parity (1 drift, 0 attention, 0 unparseable), 0 skipped'
        Hasnt '...never claims parity' $r.Out '0 out of parity'
        Unchanged '...the registry is unchanged' $orig $reg
        Same '...no temp file is left behind' 0 @([IO.Directory]::GetFiles($sumelaDir, '*sumela-tmp*')).Count
    }

    # -----------------------------------------------------------------------------------------
    Write-Host '== t_writers_copy_verbatim'
    $qd = '.sumela/memory-plugins/qdrant-session-memory/SKILL.md'
    $w = Join-Path $work 'writers'
    $seeded = $true
    try {
        tgit -C $repoRoot clone --quiet --no-hardlinks . $w | Out-Null
        $changed = @(tgit -C $repoRoot ls-files -m -o --exclude-standard -- scripts .sumela AGENTS.md.template docs/second-brain/template)
        foreach ($f in $changed) {
            $src = Join-Path $repoRoot ([string]$f)
            if (-not [IO.File]::Exists($src)) { continue }
            $dst = Join-Path $w ([string]$f)
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($dst))
            [IO.File]::Copy($src, $dst, $true)
        }
    } catch { $seeded = $false; Bad "could not seed a clone of the repository: $($_.Exception.Message)" }
    if ($seeded) {
        $wreg = Join-Path $w '.sumela/SKILL_REGISTRY.md'
        $want = Get-RegValue (Join-Path $repoRoot '.sumela/SKILL_REGISTRY.md') 'qdrant-session-memory'
        function Remove-QdrantEntry {
            # Drop the qdrant block and the blank line after it, without the library under test.
            $lines = New-Object System.Collections.Generic.List[string]
            $skipBlank = $false; $buf = $null
            foreach ($l in (Read-Utf8 $wreg).Split([char]10)) {
                $k = $l.TrimEnd([char]13)
                if ($null -ne $buf) {
                    $buf.Add($l)
                    if ($k.StartsWith('</skill>', [StringComparison]::Ordinal)) {
                        $drop = $false
                        foreach ($x in $buf) { if ([string]::Equals($x.TrimEnd([char]13), '<name>qdrant-session-memory</name>', [StringComparison]::Ordinal)) { $drop = $true } }
                        if ($drop) { $skipBlank = $true } else { foreach ($x in $buf) { $lines.Add($x) } }
                        $buf = $null
                    }
                    continue
                }
                if ($k.StartsWith('<skill ', [StringComparison]::Ordinal)) { $buf = New-Object System.Collections.Generic.List[string]; $buf.Add($l); continue }
                if ($skipBlank -and $k.Length -eq 0) { $skipBlank = $false; continue }
                $skipBlank = $false
                $lines.Add($l)
            }
            Write-Utf8 $wreg ([string]::Join($LF, $lines.ToArray()))
        }
        $childEnv = @{ QDRANT_HOST = '127.0.0.1'; QDRANT_PORT = '9' }
        [IO.File]::WriteAllBytes((Join-Path $w '.sumela/memory-plugins/qdrant-session-memory/requirements.txt'), (New-Object byte[] 0))
        $sm = Join-Path $w 'scripts/setup-memory.ps1'
        if (Test-HostParses $sm) {
            Remove-QdrantEntry
            Same 'the fixture registry lost its qdrant entry' $null (Get-RegValue $wreg 'qdrant-session-memory')
            $r = Invoke-Child -Exe $hostExe -ArgList @('-NoProfile', '-NonInteractive', '-File', $sm, '-Plugins', 'qdrant-session-memory', '-NonInteractive') -Dir $w -Env $childEnv
            Has "setup-memory.ps1's Register-Plugin registers the plugin" $r.Out 'Registered qdrant-session-memory in SKILL_REGISTRY.md'
            Same '...copying the frontmatter description verbatim (em dash included)' $want (Get-RegValue $wreg 'qdrant-session-memory')
            $r = Invoke-Tool $w @('-Check')
            Same '...and parity stays 0' 0 $r.Code
            $after = Join-Path $work 'writers.after'; [IO.File]::Copy($wreg, $after, $true)
            $r = Invoke-Child -Exe $hostExe -ArgList @('-NoProfile', '-NonInteractive', '-File', $sm, '-Plugins', 'qdrant-session-memory', '-NonInteractive') -Dir $w -Env $childEnv
            Unchanged 'a second Register-Plugin run changes nothing' $after $wreg
        } else {
            Skip "setup-memory.ps1's Register-Plugin: this host cannot parse scripts/setup-memory.ps1 (Windows PowerShell 5.1 reads its BOM-less UTF-8 as ANSI; follow-up B.1)"
        }
        # setup.ps1 is a whole install: its other steps can stop it, or fail its closing validation,
        # for reasons outside this task (outside Windows, `Get-Item .gitignore` without -Force cannot
        # see a dotfile). So the case asserts only once the output shows section 7 ran.
        $sp = Join-Path $w 'scripts/setup.ps1'
        if (-not (Test-HostParses $sp)) {
            Skip 'setup.ps1: this host cannot parse scripts/setup.ps1 (Windows PowerShell 5.1 reads its BOM-less UTF-8 as ANSI; follow-up B.1)'
        } else {
            Remove-QdrantEntry
            $r = Invoke-Child -Exe $hostExe -ArgList @('-NoProfile', '-NonInteractive', '-File', $sp, '-NonInteractive', '-ProjectName', 'ParityProbe', '-Plugins', 'qdrant-session-memory') -Dir $w -Env $childEnv
            if ($r.Out.IndexOf('Registering memory plugins in SKILL_REGISTRY.md', [StringComparison]::Ordinal) -lt 0) {
                $plain = [regex]::Replace($r.Err, '\x1b\[[0-9;]*m', '')          # pwsh colors its error text
                $why = @($plain.Split([char]10) | Where-Object { $_.Trim().Length -gt 0 } | Select-Object -First 1)
                Skip "setup.ps1: it stopped before plugin registration (exit $($r.Code)): $(if ($why.Count -gt 0) { $why[0].Trim() } else { 'no message' })"
            } else {
                Has 'setup.ps1 registers the plugin' $r.Out 'Registered plugin: qdrant-session-memory'
                Same '...with the frontmatter description, verbatim' $want (Get-RegValue $wreg 'qdrant-session-memory')
                Same '...and parity stays 0' 0 (Invoke-Tool $w @('-Check')).Code
            }
        }
    }

    # -----------------------------------------------------------------------------------------
    Write-Host '== t_source_repo_parity_zero'
    $r = Invoke-Tool $repoRoot @('-Check')
    Same 'this repository: -Check exits 0' 0 $r.Code
    Has '...with nothing out of parity' $r.Out '0 out of parity (0 drift, 0 attention, 0 unparseable)'

    # -----------------------------------------------------------------------------------------
    Write-Host '== t_registry_write_recorded_in_provenance'
    $d = Join-Path $work 'prov'; $reg = New-Install $d
    $rec = Join-Path $d '.sumela/.last-update.json'
    $r = Invoke-Tool $d @('-Sync', '-Yes')
    Same 'a sync with a rewrite: exit 0' 0 $r.Code
    $head = [string](tgit -C $d rev-parse HEAD)
    $blob = [string](tgit -C $d hash-object --no-filters -- .sumela/SKILL_REGISTRY.md)
    $wantRec = '{' + $LF + '  "files": [' + $LF + '    ".sumela/SKILL_REGISTRY.md"' + $LF + '  ],' + $LF + '  "carry_head": "' + $head + '",' + $LF +
        '  "carry": ["' + $blob + ' .sumela/SKILL_REGISTRY.md"]' + $LF + '}' + $LF
    $gotRec = ''
    if ([IO.File]::Exists($rec)) { $gotRec = Read-Utf8 $rec }
    Same 'with no record, a minimal one names the registry in "files" and binds it to HEAD and its content' $wantRec $gotRec
    # The carry is git hash-object --no-filters of the registry as written, in both twins: a CRLF
    # registry is recorded with its CRs (a twin that lost them would record another blob).
    $d = Join-Path $work 'prov-crlf'; $reg = New-Install $d; ConvertTo-Crlf $reg; Save-All $d 'crlf'
    $r = Invoke-Tool $d @('-Sync', '-Yes')
    Same 'a CRLF registry: the sync exits 0' 0 $r.Code
    $bytes = Read-Bytes $reg
    Same '...every line keeps its CRLF' (Get-ByteCount $bytes 10) (Get-ByteCount $bytes 13)
    $blob = [string](tgit -C $d hash-object --no-filters -- .sumela/SKILL_REGISTRY.md)
    $gotRec = ''
    if ([IO.File]::Exists((Join-Path $d '.sumela/.last-update.json'))) { $gotRec = Read-Utf8 (Join-Path $d '.sumela/.last-update.json') }
    Has '...and the carry is the blob of those bytes' $gotRec ('"carry": ["' + $blob + ' .sumela/SKILL_REGISTRY.md"]')
    $d = Join-Path $work 'prov3'; [void](New-Install $d)
    $r = Invoke-Tool $d @('-Sync')
    if ([IO.File]::Exists((Join-Path $d '.sumela/.last-update.json'))) { Bad 'a declined sync writes no record' } else { Ok 'a declined sync writes no record' }
    $d = Join-Path $work 'prov4'; $reg = New-Install $d
    $rec = Join-Path $d '.sumela/.last-update.json'
    Write-Utf8 $rec ('not a record' + $LF)
    $recOrig = Join-Path $work 'prov4.rec'; [IO.File]::Copy($rec, $recOrig)
    $r = Invoke-Tool $d @('-Sync', '-Yes')
    Same 'an unreadable record: the sync exits 1' 1 $r.Code
    Same '...the registry rewrite itself stands' 'Use when beta work starts (new text).' (Get-RegValue $reg 'beta')
    Has '...and the message says the record was not updated' $r.Err '.sumela/SKILL_REGISTRY.md was rewritten, but the provenance record'
    Unchanged '...which is left as it was' $recOrig $rec

    # -----------------------------------------------------------------------------------------
    Write-Host '== t_ps51_writer_keeps_utf8'
    # The library's two writers, run in this host (Windows PowerShell 5.1 in CI): non-ASCII text in,
    # the same UTF-8 bytes out, no BOM added, CRLF kept, every other byte unchanged.
    foreach ($variant in @('lf', 'crlf')) {
        $d = Join-Path $work "utf8-$variant"; $reg = New-Install $d
        if ([string]::Equals($variant, 'crlf', [StringComparison]::Ordinal)) { ConvertTo-Crlf $reg }
        $before = Read-Bytes $reg
        $text = 'Use when ' + $TR + ' ' + $EM + ' a plugin is needed.'
        Add-SumelaRegistryEntry -Registry $reg -Name 'delta' -SkillPath '.sumela/memory-plugins/delta/SKILL.md' -Description (ConvertTo-SumelaByteString $text)
        $eol = $LF
        if ([string]::Equals($variant, 'crlf', [StringComparison]::Ordinal)) { $eol = $CR + $LF }
        $block = '<skill activation="lazy">' + $eol + '<name>delta</name>' + $eol + '<description>' + $text + '</description>' + $eol +
            '<path>.sumela/memory-plugins/delta/SKILL.md</path>' + $eol + '</skill>' + $eol + $eol
        $wantText = $utf8.GetString($before).Replace('</available_skills>', $block + '</available_skills>')
        $got = Read-Bytes $reg
        Same "${variant}: the new entry is the text's UTF-8 bytes, every other byte as it was" ([Convert]::ToBase64String($utf8.GetBytes($wantText))) ([Convert]::ToBase64String($got))
        Same "${variant}: no BOM was added" 60 ([int]$got[0])
        $text2 = 'Use when alpha work starts ' + $EM + ' ' + $TR + ' (' + $TR + ').'
        Set-SumelaRegistryDescription -Registry $reg -SkillPath '.sumela/skills/alpha/SKILL.md' -Description (ConvertTo-SumelaByteString $text2)
        Same "${variant}: a rewritten non-ASCII description reads back as written" $text2 (Get-RegValue $reg 'alpha')
        $wantText = $wantText.Replace('<description>Use when alpha work starts ' + $EM + ' ' + $TR + '.</description>', '<description>' + $text2 + '</description>')
        Same "${variant}: ...and every other byte is unchanged" ([Convert]::ToBase64String($utf8.GetBytes($wantText))) ([Convert]::ToBase64String((Read-Bytes $reg)))
    }
    $res = Get-SumelaFmDescription -Path (Join-Path $work 'utf8-lf/.sumela/skills/alpha/SKILL.md')
    Same 'the frontmatter reader returns the UTF-8 bytes of a non-ASCII description' ('Use when alpha work starts ' + $EM + ' ' + $TR + '.') (ConvertFrom-SumelaByteString $res.Value)

    # -----------------------------------------------------------------------------------------
    Write-Host '== t_line_endings_kept'
    # Each line keeps its own ending through both writers, as in the bash twin: CRLF lines, LF lines
    # and a last line that ends in a lone CR, in one registry. The expected bytes are built here,
    # without the library: the LF fixture with the change made, then given the same endings.
    $d = Join-Path $work 'endings'; $reg = New-Install $d
    $lfText = $latin1.GetString((Read-Bytes $reg))
    ConvertTo-Mixed $reg; Save-All $d 'mixed'
    $orig = Join-Path $work 'endings.orig'; [IO.File]::Copy($reg, $orig)
    $want = Join-Path $work 'endings.want'
    [IO.File]::WriteAllBytes($want, $latin1.GetBytes($lfText.Replace('(old text).', '(new text).'))); ConvertTo-Mixed $want
    $r = Invoke-Tool $d @('-Sync', '-Yes')
    Same 'mixed endings: -Sync -Yes exits 0' 0 $r.Code
    Unchanged "...only beta's line changed, and every line kept its ending (the rewritten one too)" $want $reg
    [IO.File]::Copy($orig, $reg, $true)
    $block = '<skill activation="lazy">' + $LF + '<name>delta</name>' + $LF + '<description>Use when delta.</description>' + $LF +
        '<path>.sumela/memory-plugins/delta/SKILL.md</path>' + $LF + '</skill>' + $LF + $LF
    $wantAdd = Join-Path $work 'endings.add'
    [IO.File]::WriteAllBytes($wantAdd, $latin1.GetBytes($lfText.Replace($LF + '</available_skills>' + $LF, $LF + $block + '</available_skills>' + $LF)))
    ConvertTo-Mixed $wantAdd
    Add-SumelaRegistryEntry -Registry $reg -Name 'delta' -SkillPath '.sumela/memory-plugins/delta/SKILL.md' -Description 'Use when delta.'
    Unchanged '...an added block ends as the line it went before; nothing else changed' $wantAdd $reg
    # The CR check refuses a rendering that lost CRs, as the bash twin's does.
    [IO.File]::Copy($orig, $reg, $true)
    $code = 0; $msg = ''
    try { Save-SumelaRegistryText -File $reg -Text ($latin1.GetString((Read-Bytes $reg)).Replace($CR, '')) -Who 'probe' -Added 0 }
    catch { $code = $_.Exception.Data['SumelaExitCode']; $msg = $_.Exception.Message }
    Same 'a rendering that lost its CRs is refused (code 1)' 1 $code
    Has '...the CR check says why' $msg ('CR bytes where the registry holds ' + (Get-ByteCount (Read-Bytes $orig) 13))
    Unchanged '...and the registry is left as it was' $orig $reg
    Same '...no temp file is left behind' 0 @([IO.Directory]::GetFiles((Join-Path $d '.sumela'), '*sumela-tmp*')).Count

    # -----------------------------------------------------------------------------------------
    Write-Host '== t_usage_and_errors'
    $d = Join-Path $work 'usage'; [void](New-Install $d)
    Same 'an unknown argument: exit 2' 2 (Invoke-Tool $d @('-Bogus')).Code
    Same '-Yes without -Sync: exit 2' 2 (Invoke-Tool $d @('-Yes')).Code
    Same 'two modes: exit 2' 2 (Invoke-Tool $d @('-Check', '-Sync')).Code
    Same '-Only without a name: exit 2' 2 (Invoke-Tool $d @('-Only')).Code
    $r = Invoke-Tool $d @('-Only', 'nobody')
    Same '-Only with an unknown name: exit 2' 2 $r.Code
    Has '...naming it' $r.Err "no registry entry is named 'nobody'"
    $n = Join-Path $work 'noinstall'; [void][IO.Directory]::CreateDirectory($n)
    Same 'no .sumela/ above the working directory: exit 1' 1 (Invoke-Tool $n @('-Check')).Code
    $n = Join-Path $work 'noreg'; [void][IO.Directory]::CreateDirectory((Join-Path $n '.sumela'))
    Same 'no registry: exit 1' 1 (Invoke-Tool $n @('-Check')).Code
    $sub = Join-Path $d 'sub/dir'; [void][IO.Directory]::CreateDirectory($sub)
    Same 'from a subdirectory, the install root is found above it' 3 (Invoke-Tool $sub @('-Check')).Code

    # -----------------------------------------------------------------------------------------
    Write-Host '== t_cleanup_removes_read_only_trees'
    # This suite's own cleanup (Remove-Tree): git marks its object files read-only, and on Windows
    # [IO.Directory]::Delete refuses a read-only file. A cleanup that fails is a NOTE after the
    # results, never a failure that hides them.
    $t = Join-Path $work 'cleanup'; [void](New-Install $t)
    $ro = Join-Path $t 'deep/dir/read-only.txt'; Write-Utf8 $ro ('x' + $LF)
    [IO.File]::SetAttributes($ro, [IO.FileAttributes]::ReadOnly)
    $readOnly = @([IO.Directory]::GetFiles($t, '*', [IO.SearchOption]::AllDirectories) |
        Where-Object { ([IO.File]::GetAttributes($_) -band [IO.FileAttributes]::ReadOnly) -ne 0 }).Count
    if ($readOnly -ge 1) { Ok "the tree holds read-only files ($readOnly)" } else { Bad 'the tree holds read-only files (0)' }
    Same '...and is removed all the same' '' (Remove-Tree $t)
    Same '...gone' 'False' ([string][IO.Directory]::Exists($t))

    # -----------------------------------------------------------------------------------------
    Write-Host '== t_twins_agree'
    function SameBytes([string]$label, [string]$A, [string]$B) {
        # Unchanged, and on a difference each side's LF and CR counts (a lost line ending shows there).
        if (Test-SameBytes $A $B) { Ok $label; return }
        $x = Read-Bytes $A; $y = Read-Bytes $B
        Bad "$label (bash: $(Get-ByteCount $x 10) LF, $(Get-ByteCount $x 13) CR; PowerShell: $(Get-ByteCount $y 10) LF, $(Get-ByteCount $y 13) CR)"
    }
    $bash = Find-Bash
    if ($null -eq $bash) {
        Skip 'the bash twin (no bash on this machine)'
    } else {
        # Each variant answers its own way (beta, then secure-coding-standard), to both twins: lf as
        # text this host writes to a child (Windows PowerShell 5.1 may start it with a BOM, see the
        # NOTE); bom as text a writer whose encoding has a preamble writes (it starts stdin with a
        # BOM, as Windows PowerShell 5.1 does under console code page 65001), on an LF registry;
        # crlf as exact bytes, with the BOM and CRLF line ends a Windows pipe may carry; mixed as
        # exact bytes, "yes" and a CRLF, then a declining "No".
        Write-Host "  NOTE  text this host writes to a child's stdin starts with: $script:stdinStart"
        foreach ($variant in @('lf', 'bom', 'crlf', 'mixed')) {
            $pb = Join-Path $work "twin-$variant-bash"; $pp = Join-Path $work "twin-$variant-ps"
            foreach ($t in @($pb, $pp)) {
                $treg = New-Install $t
                New-Skill (Join-Path $t '.sumela/skills/secure-coding-standard/SKILL.md') 'secure-coding-standard' ('"Use whenever code is touched ' + $EM + ' ' + $TR + '."')
                Write-Utf8 (Join-Path $t '.sumela/memory-plugins/gamma/SKILL.md') ('---' + $LF + 'name: gamma' + $LF + 'description: |' + $LF + '  block' + $LF + '---' + $LF)
                if ([string]::Equals($variant, 'crlf', [StringComparison]::Ordinal)) {
                    ConvertTo-Crlf $treg
                    foreach ($s in @('alpha', 'beta', 'secure-coding-standard')) { ConvertTo-Crlf (Join-Path $t ".sumela/skills/$s/SKILL.md") }
                }
                if ([string]::Equals($variant, 'mixed', [StringComparison]::Ordinal)) { ConvertTo-Mixed $treg }
                Save-All $t $variant
            }
            $crsBefore = Get-ByteCount (Read-Bytes (Join-Path $pb '.sumela/SKILL_REGISTRY.md')) 13
            foreach ($mode in @('check', 'plan')) {
                $rb = Invoke-Child -Exe $bash -ArgList @($toolSh, "--$mode") -Dir $pb
                $mp = '-Check'
                if ([string]::Equals($mode, 'plan', [StringComparison]::Ordinal)) { $mp = '-Plan' }
                $rp = Invoke-Tool $pp @($mp)
                Same "$variant ${mode}: the same exit code" $rb.Code $rp.Code
                $po = $rp.Out.Replace('powershell -NoProfile -File scripts/sumela-registry-parity.ps1 -Sync', 'bash scripts/sumela-registry-parity.sh --sync')
                Same "$variant ${mode}: the same lines" $rb.Out $po
            }
            $text = ''; $bytes = $null; $enc = $null
            if ([string]::Equals($variant, 'lf', [StringComparison]::Ordinal)) { $text = 'y' + $LF + 'n' + $LF }
            elseif ([string]::Equals($variant, 'bom', [StringComparison]::Ordinal)) { $text = 'y' + $LF + 'n' + $LF; $enc = New-Object System.Text.UTF8Encoding $true }
            elseif ([string]::Equals($variant, 'crlf', [StringComparison]::Ordinal)) { $bytes = Get-Bytes ($BOM + 'y' + $CR + $LF + 'n' + $CR + $LF) }
            else { $bytes = Get-Bytes ('yes' + $CR + $LF + 'No' + $LF) }
            $rb = Invoke-Child -Exe $bash -ArgList @($toolSh, '--sync') -Dir $pb -Stdin $text -StdinBytes $bytes -StdinEncoding $enc
            $rp = Invoke-Tool $pp @('-Sync') $text $bytes $enc
            Same "$variant answered sync: the same exit code" $rb.Code $rp.Code
            $po = $rp.Out.Replace('powershell -NoProfile -File scripts/sumela-registry-parity.ps1 -Sync -Yes', 'bash scripts/sumela-registry-parity.sh --sync --yes')
            Same "$variant answered sync: the same lines" $rb.Out $po
            Has "$variant answered sync: the first entry is synced" $rb.Out 'synced      beta'
            SameBytes "$variant answered sync: the same registry bytes" (Join-Path $pb '.sumela/SKILL_REGISTRY.md') (Join-Path $pp '.sumela/SKILL_REGISTRY.md')
            [void](Invoke-Child -Exe $bash -ArgList @($toolSh, '--sync', '--yes') -Dir $pb)
            [void](Invoke-Tool $pp @('-Sync', '-Yes'))
            SameBytes "$variant -Sync -Yes: the same registry bytes" (Join-Path $pb '.sumela/SKILL_REGISTRY.md') (Join-Path $pp '.sumela/SKILL_REGISTRY.md')
            Same "$variant -Sync -Yes: the bash twin kept every CR the registry had" $crsBefore (Get-ByteCount (Read-Bytes (Join-Path $pb '.sumela/SKILL_REGISTRY.md')) 13)
            SameBytes "$variant -Sync -Yes: the same provenance record" (Join-Path $pb '.sumela/.last-update.json') (Join-Path $pp '.sumela/.last-update.json')
        }
        # The malformed registries and the paths that leave the install: the same rows and exits.
        foreach ($t in @('mal-indented', 'mal-trailing', 'mal-lost-end', 'mal-all-indented', 'mal-tab-start', 'mal-loose-description', 'mal-one-line', 'mal-orphan', 'unsafe/inst')) {
            $dir = Join-Path $work $t
            $rb = Invoke-Child -Exe $bash -ArgList @($toolSh, '--plan') -Dir $dir
            $rp = Invoke-Tool $dir @('-Plan')
            $po = $rp.Out.Replace('powershell -NoProfile -File scripts/sumela-registry-parity.ps1 -Sync', 'bash scripts/sumela-registry-parity.sh --sync')
            if (($rb.Code -eq $rp.Code) -and [string]::Equals($rb.Out, $po, [StringComparison]::Ordinal)) { Ok "${t}: the same lines and exit code ($($rp.Code))" }
            else { Bad "${t}: the same lines and exit code (bash $($rb.Code), PowerShell $($rp.Code))" }
        }
    }
} finally {
    # Read-only git objects are cleared first (Remove-Tree); a cleanup that still fails is a note,
    # and never keeps the summary and the exit code below from being reached.
    $why = ''
    try { $why = Remove-Tree $work } catch { $why = $_.Exception.Message }
    if ($why.Length -gt 0) { Write-Host "  NOTE  could not remove ${work}: $why" }
}

Write-Host ''
Write-Host "registry-parity (PowerShell): $script:pass passed, $script:fail failed"
if ($script:fail -gt 0) { exit 1 }
exit 0
