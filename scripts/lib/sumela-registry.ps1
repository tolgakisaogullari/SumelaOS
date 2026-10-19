# sumela-registry.ps1 - skill descriptions in .sumela/SKILL_REGISTRY.md and in SKILL.md frontmatter
# (v0.20.0+). Dot-source it:
#   . (Join-Path $PSScriptRoot 'lib/sumela-registry.ps1')
# It dot-sources sumela-provenance.ps1, next to it, for Write-SumelaRegistryRecord.
#
# The PowerShell twin of sumela-registry.sh, which holds the full contract: the canonical
# comparison, the registry grammar (tag lines, loose lines, usable entries, unreadable block
# starts), and what each writer refuses. Both twins read the same lines and write the same bytes.
# Windows PowerShell 5.1 and pwsh 7; culture-independent: text is compared ordinally
# ([string]::Equals, StartsWith, EndsWith and IndexOf with Ordinal, chars as numbers), never with
# -eq, -ceq, -match, -like or switch.
#
# Byte strings. A file is read with [IO.File]::ReadAllBytes and held as an ISO-8859-1 string, one
# char per byte, so every comparison is byte for byte (as awk's under LC_ALL=C) and a rewrite gives
# back every byte it did not change exactly as it was: a UTF-8 BOM, CRLF line endings, a missing
# final newline, even bytes that are not UTF-8 (such as the ANSI dash a Windows PowerShell 5.1
# Set-Content once wrote into a registry). Names, paths and descriptions cross this API as byte
# strings: Get-SumelaFmDescription returns one, Set-SumelaRegistryDescription and
# Add-SumelaRegistryEntry take one. ConvertTo-SumelaByteString turns ordinary text (a command-line
# argument) into one; ConvertFrom-SumelaByteString turns one back into text (a file path, a
# message). Writes go through [IO.File]::WriteAllBytes to <registry>.sumela-tmp.<pid>, whose line
# count and CR count are checked as the bash twin checks them, then a rename, then a re-read; the
# temp file never outlives the call. Never Set-Content, Add-Content or Out-File, which write ANSI
# or a BOM on Windows PowerShell 5.1 [RU-M1].
#
#   Get-SumelaFmDescription -Path <SKILL.md>
#       [pscustomobject]@{ Code; Value }. Code is the bash twin's exit code: 0 Value holds the
#       description; 1 no frontmatter, or no description: line in it; 3 UNPARSEABLE (the value is
#       not one line). Value is $null unless Code is 0.
#   Get-SumelaRegistryRows -Registry <file>
#       One object per row of sumela_registry_rows, in file order. Kind 'B' (a block): Line,
#       Count, PathCount, Loose, BlockLine, Name, Path, Description. Kind 'L' (a block start no
#       reader sees): Line. Throws (code 1) when the registry is not a file.
#   Get-SumelaRegistryDescription -Registry <file> -SkillPath <path>
#       The <description> of the first usable entry for the path, or $null.
#   Set-SumelaRegistryDescription -Registry <file> -SkillPath <path> -Description <text>
#   Add-SumelaRegistryEntry -Registry <file> -Name <name> -SkillPath <path> -Description <text>
#       The two writers throw on failure. The exception's Data['SumelaExitCode'] holds the bash
#       twin's code (1 or 4), and its message says what the bash twin says on stderr.
#   Register-SumelaRegistryPlugin -Root <install-root> -Name <plugin>
#       The one plugin writer (setup.ps1 and setup-memory.ps1 call it); never throws. Returns
#       [pscustomobject]@{ Code; Message } with the bash twin's sumela_registry_register_plugin
#       code (0 registered and recorded, 1 write failed, 2 no SKILL.md, 3 no usable description,
#       4 refused, 5 already registered, 6 no registry, 7 registered but not recorded); Message
#       says why for 1, 4 and 7.
#   Write-SumelaRegistryRecord -Root <install-root>
#       Adds .sumela/SKILL_REGISTRY.md to the provenance record's "files" (Add-SumelaRecordFiles).
#       Throws as Add-SumelaRecordFiles does; code 1 when that library is missing.
#
# Keep this file ASCII-only: Windows PowerShell 5.1 reads a script without a BOM as ANSI.

$sumelaRegistryProvenance = Join-Path $PSScriptRoot 'sumela-provenance.ps1'
if ([IO.File]::Exists($sumelaRegistryProvenance)) { . $sumelaRegistryProvenance }

function New-SumelaRegistryError {
    param([int]$Code, [string]$Message)
    $e = New-Object System.InvalidOperationException $Message
    $e.Data['SumelaExitCode'] = $Code
    return $e
}

function Get-SumelaRegistryLatin1 { return [System.Text.Encoding]::GetEncoding(28591) }

function ConvertTo-SumelaByteString {
    # Text -> its UTF-8 bytes, one char per byte.
    param([string]$Text)
    if ($null -eq $Text) { return '' }
    return (Get-SumelaRegistryLatin1).GetString((New-Object System.Text.UTF8Encoding $false).GetBytes($Text))
}

function ConvertFrom-SumelaByteString {
    # A byte string -> text, decoded as UTF-8 (a byte that is not UTF-8 becomes U+FFFD).
    param([string]$Bytes)
    if ($null -eq $Bytes) { return '' }
    return (New-Object System.Text.UTF8Encoding $false).GetString((Get-SumelaRegistryLatin1).GetBytes($Bytes))
}

function Resolve-SumelaRegistryFile {
    # A relative path is taken from the current location, as bash takes it from $PWD (.NET would
    # take it from the process directory, which Set-Location does not move).
    param([string]$Path)
    if ([IO.Path]::IsPathRooted($Path)) { return $Path }
    return (Join-Path (Get-Location -PSProvider FileSystem).ProviderPath $Path)
}

function Read-SumelaRegistryLines {
    # The file's lines as awk reads them: split on LF, each line with its CR; FinalNewline is
    # $false when the last line has no LF (awk's output keeps that through the twins' writers).
    param([string]$File)
    $text = (Get-SumelaRegistryLatin1).GetString([IO.File]::ReadAllBytes($File))
    $lines = New-Object System.Collections.Generic.List[string]
    $final = $true
    if ($text.Length -gt 0) {
        $parts = $text.Split([char]10)
        $last = $parts.Length - 1
        if ($parts[$last].Length -gt 0) { $final = $false; $last++ }
        for ($i = 0; $i -lt $last; $i++) { $lines.Add($parts[$i]) }
    }
    return [pscustomobject]@{ Lines = $lines; FinalNewline = $final }
}

function Join-SumelaRegistryLines {
    param($Lines, [bool]$FinalNewline)
    if ($Lines.Count -eq 0) { return '' }
    $text = [string]::Join([string][char]10, $Lines.ToArray())
    if ($FinalNewline) { $text += [string][char]10 }
    return $text
}

function Remove-SumelaRegistryCR {
    param([string]$Line)
    if ($Line.EndsWith([string][char]13, [StringComparison]::Ordinal)) { return $Line.Substring(0, $Line.Length - 1) }
    return $Line
}

function Test-SumelaRegistryBlank {
    # awk /^[ \t]*$/
    param([string]$Line)
    foreach ($ch in $Line.ToCharArray()) { if (([int]$ch -ne 32) -and ([int]$ch -ne 9)) { return $false } }
    return $true
}

function Test-SumelaRegistryTagLine {
    # awk /^<tag>.*<\/tag>$/ on a line without its CR
    param([string]$Line, [string]$Tag)
    $ord = [StringComparison]::Ordinal
    return ($Line.Length -ge (2 * $Tag.Length + 5)) -and $Line.StartsWith('<' + $Tag + '>', $ord) -and $Line.EndsWith('</' + $Tag + '>', $ord)
}

function Test-SumelaRegistryBlockStart {
    # awk /^<skill[ >]/
    param([string]$Line)
    $ord = [StringComparison]::Ordinal
    return $Line.StartsWith('<skill ', $ord) -or $Line.StartsWith('<skill>', $ord)
}

function Test-SumelaRegistryBlockEnd {
    # awk /^<\/skill>/
    param([string]$Line)
    return $Line.StartsWith('</skill>', [StringComparison]::Ordinal)
}

function Test-SumelaRegistryLooseStart {
    # awk t ~ /^<skill[ \t>]/ || t == "<skill", on a line trimmed of its blanks
    param([string]$Trimmed)
    $ord = [StringComparison]::Ordinal
    return $Trimmed.StartsWith('<skill ', $ord) -or $Trimmed.StartsWith('<skill' + [string][char]9, $ord) -or
           $Trimmed.StartsWith('<skill>', $ord) -or [string]::Equals($Trimmed, '<skill', $ord)
}

function Test-SumelaRegistryLoose {
    # The bash twin's loose(): a block line (CR dropped) that is not a tag line but looks like
    # structure once its blanks are trimmed.
    param([string]$Line)
    $ord = [StringComparison]::Ordinal
    $t = $Line.Trim([char[]]@(32, 9))
    foreach ($p in @('<name>', '</name>', '<path>', '</path>', '<description>', '</description>', '</skill>')) {
        if ($t.StartsWith($p, $ord)) { return $true }
    }
    return (Test-SumelaRegistryLooseStart $t)
}

function Test-SumelaRegistryReserved {
    # What no registry <description> can hold: a closing tag the readers end on, or a line break.
    param([string]$Text)
    $ord = [StringComparison]::Ordinal
    return ($Text.IndexOf('</description>', $ord) -ge 0) -or ($Text.IndexOf('</skill>', $ord) -ge 0) -or
           ($Text.IndexOf([char]10) -ge 0) -or ($Text.IndexOf([char]13) -ge 0)
}

function Test-SumelaRegistryQuoteCloses {
    # The bash twin's closes(): 1 when the quoted value, opened by quote char code $Q, closes at its
    # last byte (an even run of backslashes before a closing double quote; an odd closing run of
    # single quotes).
    param([string]$Value, [int]$Q)
    if (($Value.Length -lt 2) -or ([int]$Value[$Value.Length - 1] -ne $Q)) { return $false }
    $n = 0
    if ($Q -eq 34) {
        for ($i = $Value.Length - 2; ($i -gt 0) -and ([int]$Value[$i] -eq 92); $i--) { $n++ }
        return (($n % 2) -eq 0)
    }
    for ($i = $Value.Length - 1; ($i -gt 0) -and ([int]$Value[$i] -eq 39); $i--) { $n++ }
    return (($n % 2) -eq 1)
}

function Get-SumelaFmDescription {
    [CmdletBinding()]
    param([string]$Path)
    $none = [pscustomobject]@{ Code = 1; Value = $null }
    $file = Resolve-SumelaRegistryFile $Path
    if (-not [IO.File]::Exists($file)) { return $none }
    $lines = (Read-SumelaRegistryLines $file).Lines
    $ord = [StringComparison]::Ordinal
    $bom = [string][char]0xEF + [string][char]0xBB + [string][char]0xBF
    $blank = [char[]]@(32, 9)
    $st = 0
    $bad = $false
    $v = $null
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $l = Remove-SumelaRegistryCR $lines[$i]
        if ($i -eq 0) {
            if ($l.StartsWith($bom, $ord)) { $l = $l.Substring(3) }
            if (-not [string]::Equals($l, '---', $ord)) { return $none }
            continue
        }
        if ([string]::Equals($l, '---', $ord)) { break }
        if ($st -eq 1) {
            if (Test-SumelaRegistryBlank $l) { continue }
            if (([int]$l[0] -eq 32) -or ([int]$l[0] -eq 9)) { $bad = $true }
            break
        }
        if ($lines[$i].StartsWith('description:', $ord)) {
            $v = $l.Substring(12).TrimStart($blank).TrimEnd($blank)
            $c = -1
            if ($v.Length -gt 0) { $c = [int]$v[0] }
            if (($v.Length -eq 0) -or ($c -eq 124) -or ($c -eq 62)) { $bad = $true }
            elseif (($c -eq 34) -or ($c -eq 39)) {
                if (Test-SumelaRegistryQuoteCloses -Value $v -Q $c) { $v = $v.Substring(1, $v.Length - 2) } else { $bad = $true }
            }
            $st = 1
        }
    }
    if ($st -ne 1) { return $none }
    if ($bad) { return [pscustomobject]@{ Code = 3; Value = $null } }
    return [pscustomobject]@{ Code = 0; Value = $v }
}

function ConvertFrom-SumelaRegistryBlock {
    # The bash twin's flush() in sumela_registry_rows. $Ended: the block closed with its </skill>
    # line (its last line), not at the end of the file.
    param($Lines, $Numbers, [bool]$Ended)
    $np = 0; $nd = 0; $nn = 0; $nl = 0; $dl = 0; $ds = ''; $nm = ''; $pt = ''
    $last = $Lines.Count - 1
    for ($i = 0; $i -le $last; $i++) {
        $k = Remove-SumelaRegistryCR $Lines[$i]
        if (Test-SumelaRegistryTagLine $k 'name') { if ($nn -eq 0) { $nm = $k.Substring(6, $k.Length - 13) }; $nn++ }
        elseif (Test-SumelaRegistryTagLine $k 'path') {
            if ($np -eq 0) { $pt = $k.Substring(6, $k.Length - 13) }
            $np++
            if ($k.IndexOf([char]9) -ge 0) { $nl++ }
        }
        elseif (Test-SumelaRegistryTagLine $k 'description') {
            if ($nd -eq 0) { $dl = $Numbers[$i]; $ds = $k.Substring(13, $k.Length - 27) }
            $nd++
        }
        elseif (($i -gt 0) -and (-not ($Ended -and ($i -eq $last))) -and (Test-SumelaRegistryLoose $k)) { $nl++ }
    }
    $tab = [string][char]9
    return [pscustomobject]@{ Kind = 'B'; Line = $dl; Count = $nd; PathCount = $np; Loose = $nl; BlockLine = $Numbers[0]
        Name = $nm.Replace($tab, ' '); Path = $pt.Replace($tab, ' '); Description = $ds }
}

function Get-SumelaRegistryRows {
    [CmdletBinding()]
    param([string]$Registry)
    $file = Resolve-SumelaRegistryFile $Registry
    if (-not [IO.File]::Exists($file)) { throw (New-SumelaRegistryError 1 "Get-SumelaRegistryRows: $Registry is not a file") }
    $read = Read-SumelaRegistryLines $file
    $rows = New-Object System.Collections.Generic.List[object]
    $buf = New-Object System.Collections.Generic.List[string]
    $nums = New-Object System.Collections.Generic.List[int]
    $inb = $false
    for ($i = 0; $i -lt $read.Lines.Count; $i++) {
        $raw = $read.Lines[$i]
        if (Test-SumelaRegistryBlockStart $raw) { $inb = $true }
        if (-not $inb) {
            $t = (Remove-SumelaRegistryCR $raw).Trim([char[]]@(32, 9))
            if (Test-SumelaRegistryLooseStart $t) { $rows.Add([pscustomobject]@{ Kind = 'L'; Line = $i + 1 }) }
            continue
        }
        $buf.Add($raw); $nums.Add($i + 1)
        if (Test-SumelaRegistryBlockEnd $raw) {
            $rows.Add((ConvertFrom-SumelaRegistryBlock $buf $nums $true)); $buf.Clear(); $nums.Clear(); $inb = $false
        }
    }
    if ($inb) { $rows.Add((ConvertFrom-SumelaRegistryBlock $buf $nums $false)) }
    return $rows.ToArray()
}

function Get-SumelaRegistryDescription {
    [CmdletBinding()]
    param([string]$Registry, [string]$SkillPath)
    foreach ($r in @(Get-SumelaRegistryRows -Registry $Registry)) {
        if (-not [string]::Equals($r.Kind, 'B', [StringComparison]::Ordinal)) { continue }
        if (($r.Count -eq 1) -and ($r.PathCount -eq 1) -and ($r.Loose -eq 0) -and
            [string]::Equals($r.Path, $SkillPath, [StringComparison]::Ordinal)) { return $r.Description }
    }
    return $null
}

function Get-SumelaRegistryByteCount {
    # How many bytes of the array are $Value (10: its lines; 13: its CRs).
    param([byte[]]$Bytes, [int]$Value)
    $n = 0
    foreach ($b in $Bytes) { if ($b -eq $Value) { $n++ } }
    return $n
}

function Save-SumelaRegistryText {
    # The rendered byte string over the registry: its line count checked against the registry's
    # plus $Added (an add may also put one blank line first), and its CR count as the bash twin
    # checks it (the registry's CRs, or those plus one per added line), nothing written when the
    # bytes are already so, else a temp file beside it, then a rename. The temp file never outlives
    # the call.
    param([string]$File, [string]$Text, [string]$Who, [int]$Added)
    $latin1 = Get-SumelaRegistryLatin1
    $new = $latin1.GetBytes($Text)
    $old = [IO.File]::ReadAllBytes($File)
    $oldLines = Get-SumelaRegistryByteCount $old 10
    $want = $oldLines + $Added
    $got = Get-SumelaRegistryByteCount $new 10
    if (($got -ne $want) -and (($Added -eq 0) -or ($got -ne ($want + 1)))) {
        throw (New-SumelaRegistryError 1 "${Who}: the rendered registry has $got lines where $want were expected; $File left unchanged")
    }
    $crsOld = Get-SumelaRegistryByteCount $old 13
    $crsNew = Get-SumelaRegistryByteCount $new 13
    if (($crsNew -ne $crsOld) -and ($crsNew -ne ($crsOld + $got - $oldLines))) {
        throw (New-SumelaRegistryError 1 "${Who}: the rendered registry holds $crsNew CR bytes where the registry holds ${crsOld}: line endings were not kept as they are; $File left unchanged")
    }
    if (($old.Length -eq $new.Length) -and [string]::Equals([Convert]::ToBase64String($old), [Convert]::ToBase64String($new), [StringComparison]::Ordinal)) { return }
    $tmp = $File + '.sumela-tmp.' + $PID
    try {
        [IO.File]::WriteAllBytes($tmp, $new)
        [IO.File]::Replace($tmp, $File, [NullString]::Value)
    } catch {
        throw (New-SumelaRegistryError 1 "${Who}: cannot replace ${File}: $($_.Exception.Message)")
    } finally {
        if ([IO.File]::Exists($tmp)) { [IO.File]::Delete($tmp) }
    }
}

function Set-SumelaRegistryDescription {
    [CmdletBinding()]
    param([string]$Registry, [string]$SkillPath, [string]$Description)
    $who = 'Set-SumelaRegistryDescription'
    if (Test-SumelaRegistryReserved $Description) { throw (New-SumelaRegistryError 4 "${who}: refused: the description holds </description>, </skill> or a line break") }
    $file = Resolve-SumelaRegistryFile $Registry
    if (-not [IO.File]::Exists($file)) { throw (New-SumelaRegistryError 1 "${who}: $Registry not found") }
    $ord = [StringComparison]::Ordinal
    $want = '<path>' + $SkillPath + '</path>'
    $read = Read-SumelaRegistryLines $file
    $out = New-Object System.Collections.Generic.List[string]
    $buf = New-Object System.Collections.Generic.List[string]
    $inb = $false
    $bad = $false
    $done = 0
    $count = $read.Lines.Count
    for ($i = 0; $i -le $count; $i++) {
        $flush = $false
        $ended = $false
        if ($i -lt $count) {
            $raw = $read.Lines[$i]
            if (Test-SumelaRegistryBlockStart $raw) { $inb = $true }
            if (-not $inb) { $out.Add($raw); continue }
            $buf.Add($raw)
            if (Test-SumelaRegistryBlockEnd $raw) { $flush = $true; $ended = $true; $inb = $false }
        } elseif ($inb) {
            $flush = $true                                   # an unterminated last block, as awk's END
        }
        if (-not $flush) { continue }
        # The bash twin's flush(): rewrite the one <description> of a usable block for the path.
        $np = 0; $nd = 0; $nl = 0; $hit = $false
        $last = $buf.Count - 1
        for ($j = 0; $j -le $last; $j++) {
            $k = Remove-SumelaRegistryCR $buf[$j]
            if (Test-SumelaRegistryTagLine $k 'name') { continue }
            if (Test-SumelaRegistryTagLine $k 'path') {
                $np++
                if ($k.IndexOf([char]9) -ge 0) { $nl++ }
                if ([string]::Equals($k, $want, $ord)) { $hit = $true }
                continue
            }
            if (Test-SumelaRegistryTagLine $k 'description') { $nd++; continue }
            if (($j -gt 0) -and (-not ($ended -and ($j -eq $last))) -and (Test-SumelaRegistryLoose $k)) { $nl++ }
        }
        if ($hit -and (($np -ne 1) -or ($nd -ne 1) -or ($nl -gt 0))) { $hit = $false; $bad = $true }
        foreach ($b in $buf) {
            $k = Remove-SumelaRegistryCR $b
            $cr = ''
            if ($b.EndsWith([string][char]13, $ord)) { $cr = [string][char]13 }
            if ($hit -and (Test-SumelaRegistryTagLine $k 'description')) { $out.Add('<description>' + $Description + '</description>' + $cr); $done++ }
            else { $out.Add($b) }
        }
        $buf.Clear()
    }
    $shown = ConvertFrom-SumelaByteString $SkillPath
    if ($bad) { throw (New-SumelaRegistryError 1 "${who}: a block for $shown does not hold exactly one <path> and one <description> line, or holds a loose tag line; $Registry left unchanged") }
    if ($done -eq 0) { throw (New-SumelaRegistryError 1 "${who}: no entry for $shown in $Registry") }
    Save-SumelaRegistryText -File $file -Text (Join-SumelaRegistryLines $out $read.FinalNewline) -Who $who -Added 0
    $again = Get-SumelaRegistryDescription -Registry $file -SkillPath $SkillPath
    if (($null -eq $again) -or (-not [string]::Equals($again, $Description, $ord))) {
        throw (New-SumelaRegistryError 1 "${who}: $Registry does not hold the new description of $shown after the write")
    }
}

function Add-SumelaRegistryEntry {
    [CmdletBinding()]
    param([string]$Registry, [string]$Name, [string]$SkillPath, [string]$Description)
    $who = 'Add-SumelaRegistryEntry'
    if (Test-SumelaRegistryReserved $Description) { throw (New-SumelaRegistryError 4 "${who}: refused: the description holds </description>, </skill> or a line break") }
    if ([string]::IsNullOrEmpty($Name) -or [string]::IsNullOrEmpty($SkillPath)) { throw (New-SumelaRegistryError 4 "${who}: refused: an empty name or path") }
    foreach ($s in @($Name, $SkillPath)) {
        if ($s.IndexOfAny([char[]]@(60, 62, 10, 13)) -ge 0) { throw (New-SumelaRegistryError 4 "${who}: refused: a name or path holding < > or a line break") }
    }
    $file = Resolve-SumelaRegistryFile $Registry
    if (-not [IO.File]::Exists($file)) { throw (New-SumelaRegistryError 1 "${who}: $Registry not found") }
    $ord = [StringComparison]::Ordinal
    $blank = [char[]]@(32, 9)
    $read = Read-SumelaRegistryLines $file
    $out = New-Object System.Collections.Generic.List[string]
    $done = $false
    $prev = ''
    foreach ($raw in $read.Lines) {
        $k = Remove-SumelaRegistryCR $raw
        if ((-not $done) -and [string]::Equals($k.Trim($blank), '</available_skills>', $ord)) {
            $cr = ''
            if ($raw.EndsWith([string][char]13, $ord)) { $cr = [string][char]13 }
            if (($out.Count -gt 0) -and (-not (Test-SumelaRegistryBlank $prev))) { $out.Add($cr) }
            $out.Add('<skill activation="lazy">' + $cr)
            $out.Add('<name>' + $Name + '</name>' + $cr)
            $out.Add('<description>' + $Description + '</description>' + $cr)
            $out.Add('<path>' + $SkillPath + '</path>' + $cr)
            $out.Add('</skill>' + $cr)
            $out.Add($cr)
            $done = $true
        }
        $out.Add($raw)
        $prev = $k
    }
    if (-not $done) { throw (New-SumelaRegistryError 1 "${who}: no </available_skills> line in $Registry; left unchanged") }
    Save-SumelaRegistryText -File $file -Text (Join-SumelaRegistryLines $out $read.FinalNewline) -Who $who -Added 6
    $again = Get-SumelaRegistryDescription -Registry $file -SkillPath $SkillPath
    if (($null -eq $again) -or (-not [string]::Equals($again, $Description, $ord))) {
        throw (New-SumelaRegistryError 1 "${who}: $Registry does not hold the new entry for $(ConvertFrom-SumelaByteString $SkillPath) after the write")
    }
}

function Write-SumelaRegistryRecord {
    [CmdletBinding()]
    param([string]$Root)
    if ($null -eq (Get-Command Add-SumelaRecordFiles -ErrorAction SilentlyContinue)) {
        throw (New-SumelaRegistryError 1 "sumela-registry: $sumelaRegistryProvenance is missing; the registry write in $Root is not recorded")
    }
    Add-SumelaRecordFiles -Path @('.sumela/SKILL_REGISTRY.md') -Record ($Root.TrimEnd([char]'/', [char]'\') + '/.sumela/.last-update.json')
}

function Register-SumelaRegistryPlugin {
    [CmdletBinding()]
    param([string]$Root, [string]$Name)
    $base = $Root.TrimEnd([char]'/', [char]'\')
    $reg = $base + '/.sumela/SKILL_REGISTRY.md'
    $skill = '.sumela/memory-plugins/' + $Name + '/SKILL.md'
    if (-not [IO.File]::Exists($reg)) { return [pscustomobject]@{ Code = 6; Message = '' } }
    try {
        $text = (Get-SumelaRegistryLatin1).GetString([IO.File]::ReadAllBytes($reg))
        $nameBytes = ConvertTo-SumelaByteString $Name
        if ($text.IndexOf('<name>' + $nameBytes + '</name>', [StringComparison]::Ordinal) -ge 0) { return [pscustomobject]@{ Code = 5; Message = '' } }
        if (-not [IO.File]::Exists($base + '/' + $skill)) { return [pscustomobject]@{ Code = 2; Message = '' } }
        $fm = Get-SumelaFmDescription -Path ($base + '/' + $skill)
        if (($fm.Code -ne 0) -or ([string]$fm.Value).Length -eq 0) { return [pscustomobject]@{ Code = 3; Message = '' } }
        Add-SumelaRegistryEntry -Registry $reg -Name $nameBytes -SkillPath (ConvertTo-SumelaByteString $skill) -Description $fm.Value
    } catch {
        $code = $_.Exception.Data['SumelaExitCode']
        if ($null -eq $code) { $code = 1 }
        return [pscustomobject]@{ Code = [int]$code; Message = $_.Exception.Message }
    }
    try { Write-SumelaRegistryRecord -Root $base }
    catch { return [pscustomobject]@{ Code = 7; Message = $_.Exception.Message } }
    return [pscustomobject]@{ Code = 0; Message = '' }
}
