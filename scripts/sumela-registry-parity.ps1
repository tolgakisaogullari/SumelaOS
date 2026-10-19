# sumela-registry-parity.ps1 - skill-description parity between .sumela/SKILL_REGISTRY.md and each
# skill's SKILL.md frontmatter (v0.20.0+).
#
# The PowerShell twin of scripts/sumela-registry-parity.sh, whose header holds the full contract:
# the rows (DRIFT, ATTENTION, UNPARSEABLE), what is skipped, the summary line, what a sync asks and
# writes, the provenance record, the exit codes. This twin prints the same lines (LF line endings,
# the registry's own bytes), except that the fixer it names is its own command, and writes the
# same bytes (scripts/lib/sumela-registry.ps1). It reads a redirected answer as bytes, as the bash
# twin does, and trims it the same way: one UTF-8 BOM before it, one CR after it.
#
# Usage, from anywhere inside the install (Windows PowerShell 5.1 or pwsh 7):
#   powershell -NoProfile -File scripts/sumela-registry-parity.ps1 [-Check]   report drift (default)
#   powershell -NoProfile -File scripts/sumela-registry-parity.ps1 -Plan      ...with one diff per entry
#   powershell -NoProfile -File scripts/sumela-registry-parity.ps1 -Sync      ask per entry, rewrite on "y"
#   powershell -NoProfile -File scripts/sumela-registry-parity.ps1 -Sync -Yes rewrite without asking (agent
#                                                                             mode, after consent)
#   add -Only <name> for the one registry entry with that <name>. The bash spellings (--check,
#   --plan, --sync, --yes, --only) work too.
#
# Exit: 0 in parity; 1 error; 2 usage; 3 out of parity (see the bash twin).
# Culture-independent: the invariant culture, ordinal comparisons only.
# Keep this file ASCII-only: Windows PowerShell 5.1 reads a script without a BOM as ANSI.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$invariant = [System.Globalization.CultureInfo]::InvariantCulture
[System.Threading.Thread]::CurrentThread.CurrentCulture = $invariant
[System.Threading.Thread]::CurrentThread.CurrentUICulture = $invariant
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }

$me = 'sumela-registry-parity'
# The one line that differs from the bash twin's output: the fixer is named in this twin's spelling.
$fixer = 'powershell -NoProfile -File scripts/sumela-registry-parity.ps1 -Sync'
$fixerYes = $fixer + ' -Yes'
$usage = 'usage: powershell -NoProfile -File scripts/sumela-registry-parity.ps1 [-Check | -Plan | -Sync [-Yes]] [-Only <name>]'
$ord = [StringComparison]::Ordinal
$latin1 = [System.Text.Encoding]::GetEncoding(28591)
$stdout = [Console]::OpenStandardOutput()

function Write-Out([string]$Text) {
    # A byte string to stdout, exactly: one byte per char.
    $b = $latin1.GetBytes($Text)
    $stdout.Write($b, 0, $b.Length)
    $stdout.Flush()
}
function Write-OutLine([string]$Text) { Write-Out ($Text + [string][char]10) }
function Write-Err([string]$Text) { [Console]::Error.WriteLine($Text) }
function Exit-Usage([string]$Message) { Write-Err ($me + ': ' + $Message); Write-Err $usage; exit 2 }
function Test-Word([string]$Value, [string[]]$Words) {
    foreach ($w in $Words) { if ([string]::Equals($Value, $w, [StringComparison]::OrdinalIgnoreCase)) { return $true } }
    return $false
}

# The arguments are read here, not by a param block: the binder exits 1 on a bad parameter, and
# every usage error must exit 2.
$mode = ''
$yes = $false
$only = $null
for ($i = 0; $i -lt $args.Count; $i++) {
    $a = [string]$args[$i]
    $m = ''
    if (Test-Word $a @('-Check', '--check')) { $m = 'check' }
    elseif (Test-Word $a @('-Plan', '--plan')) { $m = 'plan' }
    elseif (Test-Word $a @('-Sync', '--sync')) { $m = 'sync' }
    if ($m.Length -gt 0) {
        if (($mode.Length -gt 0) -and (-not [string]::Equals($mode, $m, $ord))) { Exit-Usage "-$mode and $a exclude each other" }
        $mode = $m
    }
    elseif (Test-Word $a @('-Yes', '--yes', '-y')) { $yes = $true }
    elseif (Test-Word $a @('-Only', '--only')) {
        $i++
        if (($i -ge $args.Count) -or ([string]$args[$i]).Length -eq 0) { Exit-Usage '-Only needs a skill name' }
        $only = [string]$args[$i]
    }
    elseif (Test-Word $a @('-h', '-?', '-Help', '--help')) {
        [Console]::Out.WriteLine($usage)
        [Console]::Out.WriteLine('Reports skill-description drift between the registry and the skills, and repairs it with consent; see the header of scripts/sumela-registry-parity.sh.')
        exit 0
    }
    else { Exit-Usage ('unknown argument: ' + $a) }
}
if ($mode.Length -eq 0) { $mode = 'check' }
if ($yes -and (-not [string]::Equals($mode, 'sync', $ord))) { Exit-Usage '-Yes goes with -Sync' }

foreach ($lib in @('sumela-provenance.ps1', 'sumela-registry.ps1')) {
    $p = Join-Path (Join-Path $PSScriptRoot 'lib') $lib
    if (-not [IO.File]::Exists($p)) { Write-Err "${me}: $p is missing"; exit 1 }
}
. (Join-Path (Join-Path $PSScriptRoot 'lib') 'sumela-registry.ps1')      # loads sumela-provenance.ps1 too

$root = (Get-Location -PSProvider FileSystem).ProviderPath
while (-not [IO.Directory]::Exists((Join-Path $root '.sumela'))) {
    $up = [IO.Path]::GetDirectoryName($root)
    if ([string]::IsNullOrEmpty($up) -or [string]::Equals($up, $root, $ord)) { break }
    $root = $up
}
if (-not [IO.Directory]::Exists((Join-Path $root '.sumela'))) {
    Write-Err "${me}: no .sumela/ in $((Get-Location -PSProvider FileSystem).ProviderPath) or above it: not inside a SumelaOS install"
    exit 1
}
$base = $root.TrimEnd([char]'/', [char]'\')
$regRel = '.sumela/SKILL_REGISTRY.md'
$reg = $base + '/' + $regRel
if (-not [IO.File]::Exists($reg)) { Write-Err "${me}: $reg not found"; exit 1 }
try { $rows = @(Get-SumelaRegistryRows -Registry $reg) } catch { Write-Err "${me}: cannot read ${reg}: $($_.Exception.Message)"; exit 1 }

$onlyBytes = $null
if ($null -ne $only) {
    $onlyBytes = ConvertTo-SumelaByteString $only
    $found = $false
    foreach ($r in $rows) {
        if ([string]::Equals($r.Kind, 'B', $ord) -and [string]::Equals($r.Name, $onlyBytes, $ord)) { $found = $true; break }
    }
    if (-not $found) { Write-Err "${me}: no registry entry is named '$only' in $regRel"; exit 2 }
}

$securityNames = @('secure-coding-standard', 'requesting-code-review', 'receiving-code-review', 'verification-before-completion')
function Test-SecurityRouting([string]$Name, [string]$Path) {
    foreach ($s in $securityNames) {
        if ([string]::Equals($Name, $s, $ord)) { return $true }
        if ($Path.StartsWith('.sumela/skills/' + $s + '/', $ord)) { return $true }
    }
    return $false
}
function Test-LeavesInstall([string]$Path) {
    # The bash twin's case: /*|\\*|[A-Za-z]:*|..|../*|*/..|*/../*|*\\*
    if ($Path.StartsWith('/', $ord) -or ($Path.IndexOf('\', $ord) -ge 0)) { return $true }
    if (($Path.Length -ge 2) -and ([int]$Path[1] -eq 58)) {
        $c = [int]$Path[0]
        if ((($c -ge 65) -and ($c -le 90)) -or (($c -ge 97) -and ($c -le 122))) { return $true }
    }
    if ([string]::Equals($Path, '..', $ord) -or $Path.StartsWith('../', $ord) -or $Path.EndsWith('/..', $ord) -or ($Path.IndexOf('/../', $ord) -ge 0)) { return $true }
    return $false
}
function Show-Name([string]$Name) { if ($Name.Length -eq 0) { return '-' }; return $Name }
function Write-Row([string]$Label, [string]$Name, [string]$Path, [string]$Note) {
    $line = $Label.PadRight(11) + ' ' + (Show-Name $Name) + '  ' + $Path
    if ($Note.Length -gt 0) { $line += '  (' + $Note + ')' }
    Write-OutLine $line
}
function Write-Diff([int]$Line, [string]$Name, [string]$Old, [string]$New) {
    Write-OutLine ('--- a/' + $regRel)
    Write-OutLine ('+++ b/' + $regRel)
    Write-OutLine ('@@ -' + $Line + ' +' + $Line + ' @@ ' + (Show-Name $Name))
    Write-OutLine ('-<description>' + $Old + '</description>')
    Write-OutLine ('+<description>' + $New + '</description>')
}
$script:answerStream = $null
function Read-AnswerBytes {
    # One line of redirected stdin as a byte string, without its LF; $null at the end of input. It
    # is read byte by byte, as bash's read takes a pipe, so no decoder decides what an answer is:
    # [Console]::In would drop a BOM or keep it, as the host's input encoding has it.
    if ($null -eq $script:answerStream) { $script:answerStream = [Console]::OpenStandardInput() }
    $sb = New-Object System.Text.StringBuilder
    $any = $false
    while ($true) {
        $b = $script:answerStream.ReadByte()
        if ($b -lt 0) { break }
        if ($b -eq 10) { return $sb.ToString() }
        $any = $true
        [void]$sb.Append([char]$b)
    }
    if ($any) { return $sb.ToString() }
    return $null
}
function Read-Consent([string]$Name) {
    # $true on "y" or "yes"; no answer (end of input) declines. The bash twin's answer: one line,
    # without one UTF-8 BOM before it and one CR after it.
    Write-Out ('Sync the registry description of ' + (Show-Name $Name) + ' from its frontmatter? [y/N] ')
    $redirected = [Console]::IsInputRedirected
    if ($redirected) { $a = Read-AnswerBytes } else { $a = [Console]::In.ReadLine() }
    if ($null -eq $a) { Write-Out ([string][char]10); return $false }
    if ($redirected) { Write-Out ([string][char]10) }
    $bom = [string][char]0xEF + [string][char]0xBB + [string][char]0xBF        # the BOM's bytes
    if ($a.StartsWith($bom, $ord)) { $a = $a.Substring(3) }
    elseif ($a.StartsWith([string][char]0xFEFF, $ord)) { $a = $a.Substring(1) }   # ...decoded (a console)
    if ($a.EndsWith([string][char]13, $ord)) { $a = $a.Substring(0, $a.Length - 1) }
    foreach ($w in @('y', 'Y', 'yes', 'Yes', 'YES')) { if ([string]::Equals($a, $w, $ord)) { return $true } }   # the bash twin's case
    return $false
}

$looseIn = 'a tag line in it is indented, has text around it, or opens another block'
$nChecked = 0; $nSkip = 0; $nDrift = 0; $nAttn = 0; $nUnp = 0; $nSynced = 0; $lDrift = 0; $lAttn = 0
$wrote = $false
$failed = $false
$stopped = ''
foreach ($r in $rows) {
    if ([string]::Equals($r.Kind, 'L', $ord)) {                                 # a block start no reader sees
        if ($null -ne $onlyBytes) { continue }
        $nChecked++; $nUnp++
        Write-Row 'UNPARSEABLE' '' ($regRel + ':' + $r.Line) 'a <skill> line the registry grammar does not read: it is indented, or not followed by a space or >'
        continue
    }
    if (($null -ne $onlyBytes) -and (-not [string]::Equals($r.Name, $onlyBytes, $ord))) { continue }
    $where = $r.Path
    if ($where.Length -eq 0) { $where = $regRel + ':' + $r.BlockLine }
    $note = ''
    $skill = $null
    if ($r.PathCount -ne 1) {
        $note = 'the registry entry does not hold exactly one <path> line'
        if ($r.Loose -ne 0) { $note += '; ' + $looseIn }
    } elseif (Test-LeavesInstall $r.Path) {
        $note = 'the path leaves the install (absolute, or with a .. segment): not read'
    } else {
        $skill = $base + '/' + (ConvertFrom-SumelaByteString $r.Path)
        if (-not [IO.File]::Exists($skill)) { $nSkip++; continue }
    }
    $nChecked++
    if ($note.Length -eq 0) {
        if ($r.Count -ne 1) {
            $note = 'the registry entry does not hold exactly one <description> line'
            if ($r.Loose -ne 0) { $note += '; ' + $looseIn }
        } elseif ($r.Loose -ne 0) {
            $note = 'a tag line in the registry entry is indented, has text around it, or opens another block'
        }
    }
    $fm = $null
    if ($note.Length -eq 0) {
        try { $res = Get-SumelaFmDescription -Path $skill } catch {
            Write-Err "${me}: cannot read ${skill}: $($_.Exception.Message)"
            $failed = $true; $stopped = (ConvertFrom-SumelaByteString $r.Path) + ', which cannot be read'
            break
        }
        if ($res.Code -eq 0) {
            $fm = [string]$res.Value
            if ($fm.Length -eq 0) { $note = 'the frontmatter description is empty' }
            elseif (($fm.IndexOf('</description>', $ord) -ge 0) -or ($fm.IndexOf('</skill>', $ord) -ge 0)) {
                $note = 'the frontmatter description holds </description> or </skill>, which the registry cannot hold'
            }
        }
        elseif ($res.Code -eq 1) { $note = 'the frontmatter has no description: line' }
        else { $note = 'the frontmatter description is not one line: a block scalar, an open quote or a continuation line' }
        if (($note.Length -eq 0) -and [string]::Equals($fm, $r.Description, $ord)) { continue }   # in parity
    }
    if ($note.Length -gt 0) {
        if (Test-SecurityRouting $r.Name $r.Path) { $note += '; a security-routing skill' }
        Write-Row 'UNPARSEABLE' $r.Name $where $note
        $nUnp++; continue
    }

    $attention = Test-SecurityRouting $r.Name $r.Path
    if ($attention) {
        $nAttn++
        Write-Row 'ATTENTION' $r.Name $r.Path 'security routing: review this diff before it is synced'
    } else {
        $nDrift++
        Write-Row 'DRIFT' $r.Name $r.Path ''
    }
    if ([string]::Equals($mode, 'check', $ord)) { continue }
    Write-Diff $r.Line $r.Name $r.Description $fm
    if ([string]::Equals($mode, 'plan', $ord)) { continue }

    if ($yes -or (Read-Consent $r.Name)) {
        $ok = $true
        try {
            Set-SumelaRegistryDescription -Registry $reg -SkillPath $r.Path -Description $fm
        } catch {
            $code = $_.Exception.Data['SumelaExitCode']
            if ($null -eq $code) { $code = 1 }
            Write-Err $_.Exception.Message
            Write-Err "${me}: could not rewrite the entry for $(ConvertFrom-SumelaByteString $r.Path) in $regRel (exit $code)"
            $failed = $true; $stopped = 'the first failed write (' + (Show-Name $r.Name) + ')'
            $ok = $false
        }
        if ($ok) {
            $wrote = $true
            $nSynced++
            Write-OutLine ('synced      ' + (Show-Name $r.Name))
            continue
        }
    } else {
        Write-OutLine ('declined    ' + (Show-Name $r.Name))
    }
    if ($attention) { $lAttn++ } else { $lDrift++ }
    if ($stopped.Length -gt 0) { break }
}

# A registry that holds <skill text but no block or block start the grammar sees parses as empty:
# never a pass.
if (($rows.Count -eq 0) -and ($null -eq $onlyBytes)) {
    # The bash twin's grep -E '<skill([ >\t]|$)', line by line (a CR stays part of its line).
    $hit = $false
    foreach ($l in $latin1.GetString([IO.File]::ReadAllBytes($reg)).Split([char]10)) {
        foreach ($s in @('<skill ', '<skill>', ('<skill' + [string][char]9))) { if ($l.IndexOf($s, $ord) -ge 0) { $hit = $true } }
        if ($l.EndsWith('<skill', $ord)) { $hit = $true }
    }
    if ($hit) {
        $nChecked++; $nUnp++
        Write-Row 'UNPARSEABLE' '' $regRel 'the registry holds <skill text but no block its readers can parse'
    }
}

if ($wrote) {
    try { Write-SumelaRegistryRecord -Root $base }
    catch {
        Write-Err $_.Exception.Message
        Write-Err "${me}: $regRel was rewritten, but the provenance record $base/.sumela/.last-update.json was not updated"
        $failed = $true
    }
}

if ($stopped.Length -gt 0) { Write-OutLine "${me}: stopped at $stopped; the entries after it were not checked" }
if ([string]::Equals($mode, 'sync', $ord)) {
    $nLeft = $lDrift + $lAttn + $nUnp
    Write-OutLine ("${me}: $nChecked checked, $nSynced synced, $nLeft out of parity ($lDrift drift, $lAttn attention, $nUnp unparseable), $nSkip skipped")
    if ((-not $failed) -and (($lDrift + $lAttn) -gt 0)) {
        Write-OutLine "declined entries stay as they are: answer y to sync one, or run $fixerYes once the developer consents"
    }
} else {
    $nLeft = $nDrift + $nAttn + $nUnp
    Write-OutLine ("${me}: $nChecked checked, $nLeft out of parity ($nDrift drift, $nAttn attention, $nUnp unparseable), $nSkip skipped")
    if (($nDrift + $nAttn) -gt 0) { Write-OutLine "fix: $fixer" }
}
if ($nUnp -gt 0) { Write-OutLine 'hand fix: each UNPARSEABLE row says what to change; --sync never rewrites it' }

if ($failed) { exit 1 }
if ($nLeft -eq 0) { exit 0 }
exit 3
