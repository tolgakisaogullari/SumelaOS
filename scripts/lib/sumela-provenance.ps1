# sumela-provenance.ps1 - the provenance record, .sumela/.last-update.json (v0.20.0+). Dot-source it:
#   . (Join-Path $PSScriptRoot 'lib/sumela-provenance.ps1')
#
# The PowerShell twin of sumela-provenance.sh, which holds the full contract: the layout, the
# "carry" list, what a write carries from the record it replaces [RU-M4], and what is refused.
# Both twins write the same bytes (LF, UTF-8 without BOM, arrays sorted by UTF-8 bytes) from the
# same inputs. Windows PowerShell 5.1 and pwsh 7; culture-independent: every path, record line
# and value is compared ordinally ([string]::Equals with Ordinal, ordinal hash sets). Never -ceq,
# -cne, -in or switch: they compare linguistically and treat 'a.md' and 'a<U+00AD>.md' as equal.
# Formatting is invariant.
#
#   Get-SumelaRecordPath [-Root <install-root>]
#       The record path, or $null when there is no install root.
#   Get-SumelaRecordValue -Key <key> [-Record <file>]
#       A string, a number or boolean as written, or the elements of an array ("kept" elements
#       are "<path>`t<why>"). "files" is read as Get-SumelaRecordFiles reads it. $null when the
#       record or the key is absent, or the record is unreadable (a warning names it).
#   Get-SumelaRecordFiles [-Record <file>]
#       The "files" array only; nothing when there is no record, it is unreadable, or its
#       "files" is not an array of strings (a warning names the last two).
#   Add-SumelaRecordFiles -Path <path[]> [-Record <file>]
#       Call it right after a framework tool wrote the paths (see the bash twin).
#   Write-SumelaRecord -Version <v> -State complete|partial [-PendingRerun] [-BaseVersion <v>]
#       [-UpstreamCommit <hex>] [-Files <path[]>] [-Merged <path[]>] [-Kept <"path`twhy"[]>]
#       [-TheirsOverFork <path[]>] [-Removed <path[]>] [-Record <file>]
#       List parameters take arrays, or newline-separated strings as the bash twin does.
# The two writers throw on failure. The exception's Data['SumelaExitCode'] holds the code the bash
# twin returns: 1 write failed, 2 input refused, 3 record unreadable. What the bash twin says on
# stderr, these say with Write-Warning.

function New-SumelaRecordError {
    param([int]$Code, [string]$Message)
    $e = New-Object System.InvalidOperationException $Message
    $e.Data['SumelaExitCode'] = $Code
    return $e
}

function Test-SumelaRecordEq {
    # Ordinal equality of two strings.
    param([string]$A, [string]$B)
    return [string]::Equals($A, $B, [StringComparison]::Ordinal)
}

function Invoke-SumelaRecordGit {
    # git -C <dir> <args> with UTF-8 output and the hook variables cleared (see sumela-state.ps1).
    # Returns ExitCode, Lines (stdout) and Err (stderr), CRs dropped. Never throws for a git
    # failure: callers decide, and name git's reason.
    param([string]$Dir, [string[]]$GitArgs)
    $ErrorActionPreference = 'Continue'
    $names = @('GIT_DIR', 'GIT_WORK_TREE', 'GIT_COMMON_DIR', 'GIT_INDEX_FILE', 'GIT_PREFIX')
    $saved = @{}
    foreach ($n in $names) {
        $saved[$n] = [Environment]::GetEnvironmentVariable($n)
        [Environment]::SetEnvironmentVariable($n, [NullString]::Value)   # never $null: it arrives as ""
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

function Get-SumelaRecordGitReason {
    # git's first non-blank stderr line, for a one-line warning.
    param($Result)
    foreach ($l in @($Result.Err)) { if ($l -cmatch '\S') { return [string]$l } }
    return 'git gave no reason'
}

function Get-SumelaRecordInstallRoot {
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
        if ((-not $parent) -or (Test-SumelaRecordEq $parent $p)) { break }
        $p = $parent
    }
    return $null
}

function Get-SumelaRecordPath {
    [CmdletBinding()]
    param([string]$Root)
    $r = Get-SumelaRecordInstallRoot -Root $Root
    if (-not $r) { return $null }
    return (Join-Path (Join-Path $r '.sumela') '.last-update.json')
}

function Resolve-SumelaRecordFile {
    # A relative -Record is taken from the current location, as bash takes it from $PWD.
    param([string]$Record)
    if ([IO.Path]::IsPathRooted($Record)) { return $Record }
    return (Join-Path (Get-Location -PSProvider FileSystem).ProviderPath $Record)
}

function Get-SumelaRecordRootOf {
    # The install a record belongs to: the directory above its .sumela/ (bash: dirname of dirname).
    param([string]$Record)
    $d = [IO.Path]::GetDirectoryName($Record)
    if ([string]::IsNullOrEmpty($d)) { $d = [IO.Path]::GetPathRoot($Record) }
    $r = [IO.Path]::GetDirectoryName($d)
    if ([string]::IsNullOrEmpty($r)) { $r = $d }
    return $r
}

function Join-SumelaRecordPath {
    # <root>/<path> as bash spells "$root/$p": an absolute <path> stays under <root>.
    param([string]$Root, [string]$Path)
    return ($Root.TrimEnd([char]'/', [char]'\') + '/' + $Path)
}

function ConvertFrom-SumelaRecordText {
    # The grammar of the bash parser, line for line: Members (Key, Type k|b, Raw, Elements), or
    # Ok = $false with the reason.
    param([string]$Text, [string]$Name)
    $ord = [StringComparison]::Ordinal
    $members = New-Object System.Collections.ArrayList
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $st = 0
    $cur = $null
    $n = 0
    foreach ($line in $Text.Split([char]10)) {
        $n++
        $l = $line
        if ($l.EndsWith([string][char]13, $ord)) { $l = $l.Substring(0, $l.Length - 1) }
        if ($l -cmatch '^[ \t]*\z') { continue }
        $why = $null
        if ($l -cmatch '[\x00-\x1F\x7F]') { $why = 'control character' }
        elseif ($st -eq 0) { if ([string]::Equals($l, '{', $ord)) { $st = 1; continue }; $why = 'expected {' }
        elseif ($st -eq 3) { $why = 'text after the closing }' }
        elseif ($st -eq 2) {
            if ($l -cmatch '^  \],?\z') { $st = 1; continue }
            if ($l -cmatch '^    "[^"\\]*",?\z') {
                $v = $l.Substring(5)
                if ($v.EndsWith(',', $ord)) { $v = $v.Substring(0, $v.Length - 1) }
                [void]$cur.Elements.Add($v.Substring(0, $v.Length - 1))
                continue
            }
            $why = 'not an array element'
        }
        elseif ([string]::Equals($l, '}', $ord)) { $st = 3; continue }
        elseif ($l -cnotmatch '^  "[a-z_][a-z0-9_]*": ') { $why = 'not a member line' }
        else {
            $rest = $l.Substring(3)
            $key = $rest.Substring(0, $rest.IndexOf([char]'"'))
            if (-not $seen.Add($key)) { $why = "duplicate key $key" }
            else {
                $raw = $l.Substring($key.Length + 6)
                if ([string]::Equals($raw, '[', $ord)) {
                    $cur = [pscustomobject]@{ Key = $key; Type = 'b'; Raw = ''; Elements = (New-Object System.Collections.Generic.List[string]) }
                    [void]$members.Add($cur)
                    $st = 2
                    continue
                }
                if ($raw.EndsWith(',', $ord)) { $raw = $raw.Substring(0, $raw.Length - 1) }
                if ($raw.Length -eq 0) { $why = 'empty value' }
                else {
                    [void]$members.Add([pscustomobject]@{ Key = $key; Type = 'k'; Raw = $raw; Elements = $null })
                    continue
                }
            }
        }
        return [pscustomobject]@{ Ok = $false; Error = "sumela-provenance: ${Name}: line ${n}: $why"; Members = $members }
    }
    if ($st -ne 3) { return [pscustomobject]@{ Ok = $false; Error = "sumela-provenance: ${Name}: no closing }"; Members = $members } }
    return [pscustomobject]@{ Ok = $true; Error = ''; Members = $members }
}

function Read-SumelaRecord {
    # $null when the file is absent; otherwise the parse result.
    param([string]$Record)
    if (-not [IO.File]::Exists($Record)) { return $null }
    $text = [IO.File]::ReadAllText($Record, (New-Object System.Text.UTF8Encoding $false))   # a BOM is dropped
    return (ConvertFrom-SumelaRecordText -Text $text -Name $Record)
}

function ConvertFrom-SumelaRecordArray {
    # A one-line array: Kind 's' strings, 'o' kept objects ("<path>`t<why>"). $null for any other
    # shape. Elements hold no '"' (refused on write), so splitting on '"' is exact.
    param([string]$Raw, [string]$Kind)
    $ord = [StringComparison]::Ordinal
    $list = New-Object System.Collections.Generic.List[string]
    if ([string]::Equals($Raw, '[]', $ord)) { return ,$list }
    $q = $Raw.Split([char]'"')
    $n = $q.Length
    if ([string]::Equals($Kind, 's', $ord)) {
        if ($n -lt 3 -or ($n % 2) -eq 0 -or (-not [string]::Equals($q[0], '[', $ord))) { return $null }
        for ($j = 1; $j -lt $n - 1; $j += 2) {
            $sep = ', '
            if ($j + 1 -eq $n - 1) { $sep = ']' }
            if (-not [string]::Equals($q[$j + 1], $sep, $ord)) { return $null }
            $list.Add($q[$j])
        }
        return ,$list
    }
    if ($n -lt 9 -or (($n - 1) % 8) -ne 0 -or (-not [string]::Equals($q[0], '[{', $ord))) { return $null }
    for ($j = 0; $j -lt $n - 1; $j += 8) {
        if ((-not [string]::Equals($q[$j + 1], 'path', $ord)) -or (-not [string]::Equals($q[$j + 2], ': ', $ord)) -or
            (-not [string]::Equals($q[$j + 4], ', ', $ord)) -or (-not [string]::Equals($q[$j + 5], 'why', $ord)) -or
            (-not [string]::Equals($q[$j + 6], ': ', $ord))) { return $null }
        $end = '}, {'
        if ($j + 8 -eq $n - 1) { $end = '}]' }
        if (-not [string]::Equals($q[$j + 8], $end, $ord)) { return $null }
        $list.Add($q[$j + 3] + "`t" + $q[$j + 7])
    }
    return ,$list
}

function Find-SumelaRecordMember {
    param($Parsed, [string]$Key)
    if ($null -eq $Parsed) { return $null }
    foreach ($m in $Parsed.Members) { if (Test-SumelaRecordEq $m.Key $Key) { return $m } }
    return $null
}

function Read-SumelaRecordMember {
    # The bash _sumela_rec_values <key> <shape>. Present: the key exists. Ok: it has the shape
    # (Values then holds what bash prints; nothing otherwise). Shape '' any value, as
    # Get-SumelaRecordValue prints it; 's' an array of strings (multi-line or one-line); 'o' an
    # array of kept objects; 'str' a string, unquoted; 'raw' a number or boolean as written. An
    # array that is neither strings nor kept objects yields nothing in any shape.
    param($Parsed, [string]$Key, [string]$Shape = '')
    $ord = [StringComparison]::Ordinal
    $any = [string]::Equals($Shape, '', $ord)
    $vals = New-Object System.Collections.Generic.List[string]
    $m = Find-SumelaRecordMember -Parsed $Parsed -Key $Key
    if ($null -eq $m) { return [pscustomobject]@{ Present = $false; Ok = $false; Values = $vals.ToArray() } }
    $ok = $true
    if ([string]::Equals([string]$m.Type, 'b', $ord)) {
        if ($any -or [string]::Equals($Shape, 's', $ord)) { foreach ($e in $m.Elements) { if ($e.Length -gt 0) { $vals.Add($e) } } }
        else { $ok = $false }
    } else {
        $raw = [string]$m.Raw
        if ($raw -cmatch '^"[^"\\]*"\z') {
            if ($any -or [string]::Equals($Shape, 'str', $ord)) { $vals.Add($raw.Substring(1, $raw.Length - 2)) } else { $ok = $false }
        } elseif ($raw.StartsWith('[', $ord)) {
            $items = $null
            if ($any -or [string]::Equals($Shape, 's', $ord)) { $items = ConvertFrom-SumelaRecordArray -Raw $raw -Kind 's' }
            if (($null -eq $items) -and ($any -or [string]::Equals($Shape, 'o', $ord))) { $items = ConvertFrom-SumelaRecordArray -Raw $raw -Kind 'o' }
            if ($null -eq $items) { if (-not $any) { $ok = $false } }
            else { foreach ($i in $items) { if ($i.Length -gt 0) { $vals.Add($i) } } }
        } elseif ($any -or [string]::Equals($Shape, 'raw', $ord)) {
            $vals.Add($raw)
        } else {
            $ok = $false
        }
    }
    if (-not $ok) { $vals.Clear() }
    return [pscustomobject]@{ Present = $true; Ok = $ok; Values = $vals.ToArray() }
}

function Test-SumelaRecordMemberIs {
    # One string value of <key> (shape 'str' or 'raw') equals <value>, ordinally.
    param($Parsed, [string]$Key, [string]$Shape, [string]$Value)
    $r = Read-SumelaRecordMember -Parsed $Parsed -Key $Key -Shape $Shape
    return ($r.Ok -and ($r.Values.Count -eq 1) -and (Test-SumelaRecordEq $r.Values[0] $Value))
}

function Get-SumelaRecordValue {
    [CmdletBinding()]
    param([string]$Key, [string]$Record)
    if ($Key -cnotmatch '^[a-z0-9_]+\z') { throw (New-SumelaRecordError 2 "Get-SumelaRecordValue: invalid key '$Key'") }
    if (-not $Record) { $Record = Get-SumelaRecordPath; if (-not $Record) { return $null } }
    $Record = Resolve-SumelaRecordFile $Record
    $parsed = Read-SumelaRecord -Record $Record
    if ($null -eq $parsed) { return $null }
    if (-not $parsed.Ok) { Write-Warning $parsed.Error; return $null }
    if (Test-SumelaRecordEq $Key 'files') {                 # the guard's array: never anything but strings
        if ($null -eq (Find-SumelaRecordMember -Parsed $parsed -Key 'files')) { return $null }
        Get-SumelaRecordFiles -Record $Record
        return
    }
    $r = Read-SumelaRecordMember -Parsed $parsed -Key $Key
    if (-not $r.Present) { return $null }
    foreach ($v in $r.Values) { $v }
}

function Get-SumelaRecordFiles {
    # The ONE array the self-modification guard trusts: an array of strings, or nothing.
    [CmdletBinding()]
    param([string]$Record)
    if (-not $Record) { $Record = Get-SumelaRecordPath; if (-not $Record) { return } }
    $Record = Resolve-SumelaRecordFile $Record
    $parsed = Read-SumelaRecord -Record $Record
    if ($null -eq $parsed) { return }
    if (-not $parsed.Ok) { Write-Warning $parsed.Error; return }
    $r = Read-SumelaRecordMember -Parsed $parsed -Key 'files' -Shape 's'
    if ($r.Present -and (-not $r.Ok)) {
        Write-Warning "sumela-provenance: ${Record}: `"files`" is not an array of strings; it vouches for nothing"
        return
    }
    foreach ($v in $r.Values) { $v }
}

function Test-SumelaRecordValue {
    # The bash _sumela_rec_check, one value: $null when acceptable, else the refusal message.
    param([string]$Kind, [string]$Value)
    $ord = [StringComparison]::Ordinal
    $ok = $false
    $what = $Kind
    if ([string]::Equals($Kind, 'path', $ord)) {
        $ok = ($Value.Length -gt 0) -and ($Value -cnotmatch '[\x00-\x1F\x7F"\\]')
        $what = 'path (empty, or holds a quote, a backslash or a control character)'
    } elseif ([string]::Equals($Kind, 'version', $ord)) {
        $ok = $Value -cmatch '^[0-9A-Za-z][0-9A-Za-z.+-]*\z'
    } elseif ([string]::Equals($Kind, 'base', $ord)) {
        $ok = ($Value.Length -eq 0) -or ($Value -cmatch '^[0-9A-Za-z][0-9A-Za-z.+-]*\z'); $what = 'base version'
    } elseif ([string]::Equals($Kind, 'commit', $ord)) {
        $ok = $Value -cmatch '^[0-9a-f]*\z'; $what = 'upstream commit (lowercase hex)'
    } elseif ([string]::Equals($Kind, 'why', $ord)) {
        $ok = $Value -cmatch '^[a-z][a-z0-9:-]*\z'; $what = 'kept reason'
    } else {
        $what = 'row'
    }
    if ($Value.Contains("`t")) { $ok = $false; $what = "$Kind (holds a TAB)" }
    if ($ok) { return $null }
    return "sumela-provenance: refused ${what}: `"$Value`""
}

function Split-SumelaRecordList {
    # Arrays or newline-separated strings -> lines, one trailing CR dropped, empty lines skipped.
    param([string[]]$Items)
    foreach ($item in @($Items)) {
        if ($null -eq $item) { continue }
        foreach ($l in ([string]$item).Split([char]10)) {
            if ($l.EndsWith([string][char]13, [StringComparison]::Ordinal)) { $l = $l.Substring(0, $l.Length - 1) }
            if ($l.Length -gt 0) { $l }
        }
    }
}

function Sort-SumelaRecordRows {
    # Byte order of the UTF-8 encoding, as `LC_ALL=C sort` orders lines; -Unique drops repeats
    # (byte-identical rows only).
    param([string[]]$Rows, [switch]$Unique)
    $present = @($Rows | Where-Object { $null -ne $_ })
    if ($present.Count -eq 0) { return }
    $utf8 = New-Object System.Text.UTF8Encoding $false
    $keys = New-Object 'string[]' $present.Count
    $items = New-Object 'string[]' $present.Count
    for ($i = 0; $i -lt $present.Count; $i++) {
        $items[$i] = [string]$present[$i]
        $keys[$i] = [BitConverter]::ToString($utf8.GetBytes($items[$i])).Replace('-', '')
    }
    [Array]::Sort($keys, $items, [StringComparer]::Ordinal)
    for ($i = 0; $i -lt $items.Count; $i++) {
        if ($Unique -and ($i -gt 0) -and [string]::Equals($keys[$i], $keys[$i - 1], [StringComparison]::Ordinal)) { continue }
        $items[$i]
    }
}

# --- git's view of the install, for the carry (the bash twin's helpers) -----------------------

function Get-SumelaRecordHead {
    # Ok and Head: HEAD's commit, or '' on an unborn branch. Ok = $false and Error when git fails.
    param([string]$Root)
    $r = Invoke-SumelaRecordGit -Dir $Root -GitArgs @('rev-parse', '--verify', '-q', 'HEAD')
    $out = [string]::Join("`n", $r.Lines)
    if ($r.ExitCode -eq 0) {
        if ($out -cmatch '^[0-9a-f]+\z') { return [pscustomobject]@{ Ok = $true; Head = $out; Error = '' } }
        return [pscustomobject]@{ Ok = $false; Head = ''; Error = "git rev-parse printed an unexpected HEAD: $out" }
    }
    if (($r.ExitCode -eq 1) -and ($out.Length -eq 0) -and ($r.Err.Count -eq 0)) {   # --verify -q: an unborn branch, silently
        return [pscustomobject]@{ Ok = $true; Head = ''; Error = '' }
    }
    return [pscustomobject]@{ Ok = $false; Head = ''; Error = (Get-SumelaRecordGitReason $r) }
}

function Select-SumelaRecordUncommitted {
    # Ok and Paths: the given paths that differ from HEAD (staged, unstaged or untracked) and are
    # present, as the bash _sumela_rec_dirty decides it: one `git status -z`, the install prefix
    # cut from its paths. Ok = $false and Error when git fails.
    param([string]$Root, [string[]]$Paths)
    $found = New-Object System.Collections.Generic.List[string]
    $asked = @(@($Paths) | Where-Object { -not [string]::IsNullOrEmpty($_) })
    if ($asked.Count -eq 0) { return [pscustomobject]@{ Ok = $true; Paths = $found.ToArray(); Error = '' } }
    $pre = Invoke-SumelaRecordGit -Dir $Root -GitArgs @('rev-parse', '--show-prefix')
    if ($pre.ExitCode -ne 0) { return [pscustomobject]@{ Ok = $false; Paths = $found.ToArray(); Error = (Get-SumelaRecordGitReason $pre) } }
    $prefix = ''
    if ($pre.Lines.Count -ge 1) { $prefix = [string]$pre.Lines[0] }
    # The pathspecs are the paths' top-level names, a handful however long the list: a command
    # line of hundreds of paths would pass Windows' 32K limit.
    $tops = @(Sort-SumelaRecordRows -Rows @($asked | ForEach-Object { $_.Split([char]'/')[0] } | Where-Object { $_ }) -Unique)
    if ($tops.Count -eq 0) { return [pscustomobject]@{ Ok = $true; Paths = $found.ToArray(); Error = '' } }
    $gitArgs = @('--no-optional-locks', '--literal-pathspecs', 'status', '--porcelain=v1', '-z',
                 '--no-renames', '--untracked-files=all', '--') + $tops
    $st = Invoke-SumelaRecordGit -Dir $Root -GitArgs $gitArgs
    if ($st.ExitCode -ne 0) { return [pscustomobject]@{ Ok = $false; Paths = $found.ToArray(); Error = (Get-SumelaRecordGitReason $st) } }
    $want = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($a in $asked) { [void]$want.Add($a) }
    $done = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    # A line break inside a listed name stays inside its entry here, so it never matches a path.
    $text = [string]::Join("`n", $st.Lines)
    foreach ($entry in $text.Split([char]0)) {
        if ($entry.Length -lt 4) { continue }
        $p = $entry.Substring(3)
        if (($prefix.Length -gt 0) -and $p.StartsWith($prefix, [StringComparison]::Ordinal)) { $p = $p.Substring($prefix.Length) }
        if ($want.Contains($p) -and $done.Add($p)) {
            if ([IO.File]::Exists((Join-SumelaRecordPath $Root $p))) { $found.Add($p) }
        }
    }
    return [pscustomobject]@{ Ok = $true; Paths = $found.ToArray(); Error = '' }
}

function Get-SumelaRecordBlobs {
    # Ok and Map: path -> `git hash-object --no-filters`, '-' when the path is not a regular file.
    # Ok = $false and Error when git fails. On the command line, in chunks well under Windows' 32K
    # limit: --stdin-paths would resolve the paths from the repository top, not from a monorepo
    # install's root.
    param([string]$Root, [string[]]$Paths)
    $map = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::Ordinal)
    $regular = New-Object System.Collections.Generic.List[string]
    foreach ($p in @($Paths)) {
        if ([string]::IsNullOrEmpty($p)) { continue }
        if ([IO.File]::Exists((Join-SumelaRecordPath $Root $p))) { $regular.Add($p) } else { $map[$p] = '-' }
    }
    $i = 0
    while ($i -lt $regular.Count) {
        $chunk = New-Object System.Collections.Generic.List[string]
        $len = 0
        while (($i -lt $regular.Count) -and ($len -lt 8000)) { $chunk.Add($regular[$i]); $len += $regular[$i].Length + 1; $i++ }
        $r = Invoke-SumelaRecordGit -Dir $Root -GitArgs (@('hash-object', '--no-filters', '--') + $chunk.ToArray())
        if ($r.ExitCode -ne 0) { return [pscustomobject]@{ Ok = $false; Map = $map; Error = (Get-SumelaRecordGitReason $r) } }
        $bad = $r.Lines.Count -ne $chunk.Count
        for ($j = 0; (-not $bad) -and ($j -lt $chunk.Count); $j++) {
            if ($r.Lines[$j] -cnotmatch '^[0-9a-f]+\z') { $bad = $true } else { $map[$chunk[$j]] = $r.Lines[$j] }
        }
        if ($bad) { return [pscustomobject]@{ Ok = $false; Map = $map; Error = 'git hash-object printed an unexpected answer' } }
    }
    return [pscustomobject]@{ Ok = $true; Map = $map; Error = '' }
}

function Get-SumelaRecordCarryEntries {
    # The valid "carry" entries as "<path>`t<blob>", in the record's order; an invalid entry is
    # dropped with a warning (the bash _sumela_rec_carry_entries).
    param($Parsed, [string]$Who)
    $out = New-Object System.Collections.Generic.List[string]
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($e in (Read-SumelaRecordMember -Parsed $Parsed -Key 'carry' -Shape 's').Values) {
        $m = [regex]::Match($e, '^([0-9a-f]+|-) ')
        $blob = ''
        $path = ''
        if ($m.Success) { $blob = $m.Groups[1].Value; $path = $e.Substring($m.Length) }
        if (($blob.Length -eq 0) -or ($path.Length -eq 0) -or ($path -cmatch '[\x00-\x1F\x7F"\\]') -or (-not $seen.Add($path))) {
            Write-Warning "${Who}: dropped an invalid carry entry: $e"
            continue
        }
        $out.Add($path + "`t" + $blob)
    }
    return ,$out
}

function Test-SumelaRecordSameList {
    # Two lists hold the same strings in the same order, ordinally.
    param([string[]]$A, [string[]]$B)
    $x = @($A); $y = @($B)
    if ($x.Count -ne $y.Count) { return $false }
    for ($i = 0; $i -lt $x.Count; $i++) { if (-not (Test-SumelaRecordEq $x[$i] $y[$i])) { return $false } }
    return $true
}

function ConvertTo-SumelaRecordCarryText {
    # Rows "<path>`t<blob>" -> the one-line "carry" array, elements "<blob> <path>".
    param([string[]]$Rows)
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($row in @($Rows)) {
        if ($null -eq $row) { continue }
        $tab = $row.IndexOf([char]9)
        $parts.Add('"' + $row.Substring($tab + 1) + ' ' + $row.Substring(0, $tab) + '"')
    }
    return '[' + [string]::Join(', ', $parts.ToArray()) + ']'
}

function Save-SumelaRecordText {
    # A temp file beside the record, then a rename; UTF-8 without BOM, the text exactly as given.
    param([string]$Record, [string]$Text)
    $tmp = $Record + '.sumela-tmp.' + $PID
    try {
        [IO.File]::WriteAllText($tmp, $Text, (New-Object System.Text.UTF8Encoding $false))
        if ([IO.File]::Exists($Record)) { [IO.File]::Replace($tmp, $Record, [NullString]::Value) }
        else { [IO.File]::Move($tmp, $Record) }
    } catch {
        if ([IO.File]::Exists($tmp)) { [IO.File]::Delete($tmp) }
        throw (New-SumelaRecordError 1 "sumela-provenance: cannot write ${Record}: $($_.Exception.Message)")
    }
}

function ConvertTo-SumelaRecordArrayText {
    param([string[]]$Items)
    $parts = @(@($Items) | Where-Object { $null -ne $_ } | ForEach-Object { '"' + $_ + '"' })
    return '[' + [string]::Join(', ', $parts) + ']'
}

function Add-SumelaRecordFiles {
    [CmdletBinding()]
    param([string[]]$Path, [string]$Record)
    $paths = @($Path | Where-Object { $null -ne $_ })
    if ($paths.Count -eq 0) { throw (New-SumelaRecordError 2 'Add-SumelaRecordFiles: no path given') }
    foreach ($p in $paths) {
        if ($p.Contains("`n") -or $p.Contains("`r")) { throw (New-SumelaRecordError 2 'sumela-provenance: refused path (a line break)') }
        $msg = Test-SumelaRecordValue -Kind 'path' -Value $p
        if ($msg) { throw (New-SumelaRecordError 2 $msg) }
    }
    if (-not $Record) {
        $Record = Get-SumelaRecordPath
        if (-not $Record) { throw (New-SumelaRecordError 1 'Add-SumelaRecordFiles: no install root (.sumela/) above the current location; pass -Record') }
    }
    $Record = Resolve-SumelaRecordFile $Record
    $new = @(Sort-SumelaRecordRows -Rows $paths -Unique)
    $parsed = Read-SumelaRecord -Record $Record
    $members = New-Object System.Collections.ArrayList
    $oldFiles = @()
    if ($null -ne $parsed) {
        if (-not $parsed.Ok) { throw (New-SumelaRecordError 3 ($parsed.Error + "; $Record left unchanged")) }
        $fm = Read-SumelaRecordMember -Parsed $parsed -Key 'files' -Shape 's'
        if (-not $fm.Ok) { throw (New-SumelaRecordError 3 "Add-SumelaRecordFiles: $Record has no `"files`" array of strings; left unchanged") }
        $oldFiles = @($fm.Values)
        foreach ($m in $parsed.Members) { [void]$members.Add($m) }
    }
    $files = @(Sort-SumelaRecordRows -Rows (@($oldFiles) + $new) -Unique)

    # The carry entries: this HEAD, and the content the tool just wrote. Entries recorded at
    # another HEAD belong to a finished run and are dropped; a path added again takes its new blob.
    $root = Get-SumelaRecordRootOf $Record
    $gitOk = $false
    $headNow = ''
    $carry = @()
    $h = Get-SumelaRecordHead -Root $root
    $reason = $h.Error
    if ($h.Ok) {
        $b = Get-SumelaRecordBlobs -Root $root -Paths $new
        if ($b.Ok) {
            $gitOk = $true
            $headNow = $h.Head
            $map = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::Ordinal)
            if (Test-SumelaRecordMemberIs -Parsed $parsed -Key 'carry_head' -Shape 'str' -Value $headNow) {
                foreach ($row in (Get-SumelaRecordCarryEntries -Parsed $parsed -Who 'Add-SumelaRecordFiles')) {
                    $tab = $row.IndexOf([char]9)
                    $map[$row.Substring(0, $tab)] = $row.Substring($tab + 1)
                }
            }
            foreach ($p in $new) { $map[$p] = $b.Map[$p] }
            $rows = New-Object System.Collections.Generic.List[string]
            foreach ($k in $map.Keys) { $rows.Add($k + "`t" + $map[$k]) }
            $carry = @(Sort-SumelaRecordRows -Rows $rows.ToArray())
        } else {
            $reason = $b.Error
        }
    }
    if (-not $gitOk) {
        Write-Warning "Add-SumelaRecordFiles: cannot read the git state of ${root} ($reason); the path(s) are in `"files`", but the next write will not carry them"
    }

    # Member by member in the record's own order (the bash twin's renderer).
    if ($null -eq (Find-SumelaRecordMember -Parsed $parsed -Key 'files')) { [void]$members.Add([pscustomobject]@{ Key = 'files'; Type = 'b'; Raw = ''; Elements = $null }) }
    if ($gitOk -and ($null -eq (Find-SumelaRecordMember -Parsed $parsed -Key 'carry_head'))) { [void]$members.Add([pscustomobject]@{ Key = 'carry_head'; Type = 'k'; Raw = ''; Elements = $null }) }
    if ($gitOk -and ($null -eq (Find-SumelaRecordMember -Parsed $parsed -Key 'carry'))) { [void]$members.Add([pscustomobject]@{ Key = 'carry'; Type = 'k'; Raw = ''; Elements = $null }) }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("{`n")
    for ($i = 0; $i -lt $members.Count; $i++) {
        $m = $members[$i]
        $c = ''
        if ($i -lt $members.Count - 1) { $c = ',' }
        if (Test-SumelaRecordEq $m.Key 'files') {
            [void]$sb.Append("  `"files`": [`n")
            for ($j = 0; $j -lt $files.Count; $j++) {
                $sep = ''
                if ($j -lt $files.Count - 1) { $sep = ',' }
                [void]$sb.Append('    "' + $files[$j] + '"' + $sep + "`n")
            }
            [void]$sb.Append('  ]' + $c + "`n")
        } elseif ($gitOk -and (Test-SumelaRecordEq $m.Key 'carry_head')) {
            [void]$sb.Append('  "carry_head": "' + $headNow + '"' + $c + "`n")
        } elseif ($gitOk -and (Test-SumelaRecordEq $m.Key 'carry')) {
            [void]$sb.Append('  "carry": ' + (ConvertTo-SumelaRecordCarryText -Rows $carry) + $c + "`n")
        } elseif (Test-SumelaRecordEq $m.Type 'b') {
            [void]$sb.Append('  "' + $m.Key + "`": [`n")
            $els = @($m.Elements)
            for ($j = 0; $j -lt $els.Count; $j++) {
                $sep = ''
                if ($j -lt $els.Count - 1) { $sep = ',' }
                [void]$sb.Append('    "' + $els[$j] + '"' + $sep + "`n")
            }
            [void]$sb.Append('  ]' + $c + "`n")
        } else {
            [void]$sb.Append('  "' + $m.Key + '": ' + $m.Raw + $c + "`n")
        }
    }
    [void]$sb.Append("}`n")
    $text = $sb.ToString()
    $utf8 = New-Object System.Text.UTF8Encoding $false
    if ([IO.File]::Exists($Record)) {
        $old = [IO.File]::ReadAllBytes($Record)
        $nb = $utf8.GetBytes($text)
        if (($old.Length -eq $nb.Length) -and (Test-SumelaRecordEq ([Convert]::ToBase64String($old)) ([Convert]::ToBase64String($nb)))) { return }   # already recorded
    }
    Save-SumelaRecordText -Record $Record -Text $text

    # Re-read the artifact: every requested path in "files" and, with git's answer, the carry as
    # rendered.
    $check = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($f in @(Get-SumelaRecordFiles -Record $Record)) { [void]$check.Add($f) }
    foreach ($p in $paths) {
        if (-not $check.Contains($p)) { throw (New-SumelaRecordError 1 "Add-SumelaRecordFiles: $p is missing from $Record after the write") }
    }
    if ($gitOk) {
        $again = Read-SumelaRecord -Record $Record
        $same = ($null -ne $again) -and $again.Ok
        if ($same) {
            $got = Get-SumelaRecordCarryEntries -Parsed $again -Who 'Add-SumelaRecordFiles'   # a List: never wrap it in @()
            $same = (Test-SumelaRecordSameList -A $got.ToArray() -B $carry) -and
                    (Test-SumelaRecordMemberIs -Parsed $again -Key 'carry_head' -Shape 'str' -Value $headNow)
        }
        if (-not $same) { throw (New-SumelaRecordError 1 "Add-SumelaRecordFiles: $Record does not hold the carry entries just written") }
    }
}

function Write-SumelaRecord {
    [CmdletBinding()]
    param(
        [string]$Version,
        [string]$State,
        [switch]$PendingRerun,
        [AllowEmptyString()][string]$BaseVersion,
        [AllowEmptyString()][string]$UpstreamCommit,
        [string[]]$Files,
        [string[]]$Merged,
        [string[]]$Kept,
        [string[]]$TheirsOverFork,
        [string[]]$Removed,
        [string]$Record
    )
    if (-not ((Test-SumelaRecordEq $State 'complete') -or (Test-SumelaRecordEq $State 'partial'))) {
        throw (New-SumelaRecordError 2 "Write-SumelaRecord: -State must be complete or partial, not '$State'")
    }
    $bvSet = $PSBoundParameters.ContainsKey('BaseVersion')
    $ucSet = $PSBoundParameters.ContainsKey('UpstreamCommit')
    $bv = ''; if ($bvSet) { $bv = [string]$BaseVersion }
    $uc = ''; if ($ucSet) { $uc = [string]$UpstreamCommit }
    if (-not $Record) {
        $Record = Get-SumelaRecordPath
        if (-not $Record) { throw (New-SumelaRecordError 1 'Write-SumelaRecord: no install root (.sumela/) above the current location; pass -Record') }
    }
    $Record = Resolve-SumelaRecordFile $Record
    $unfinished = (Test-SumelaRecordEq $State 'partial') -or [bool]$PendingRerun

    # 1. This write's rows, "<class>`t<path>[`t<why>]", checked as the bash twin checks them.
    $new = New-Object System.Collections.Generic.List[string]
    foreach ($p in @(Split-SumelaRecordList -Items $Files)) { $new.Add("files`t$p") }
    foreach ($p in @(Split-SumelaRecordList -Items $Merged)) { $new.Add("merged`t$p") }
    foreach ($p in @(Split-SumelaRecordList -Items $TheirsOverFork)) { $new.Add("theirs_over_fork`t$p") }
    foreach ($p in @(Split-SumelaRecordList -Items $Removed)) { $new.Add("removed`t$p") }
    foreach ($row in @(Split-SumelaRecordList -Items $Kept)) {
        $tab = $row.IndexOf([char]9)
        if ($tab -lt 0) { $new.Add("kept`t$row`t") }
        else { $new.Add("kept`t" + $row.Substring(0, $tab) + "`t" + $row.Substring($tab + 1)) }
    }
    $checks = New-Object System.Collections.Generic.List[string[]]
    $checks.Add([string[]]@('version', [string]$Version))
    $checks.Add([string[]]@('base', $bv))
    $checks.Add([string[]]@('commit', $uc))
    foreach ($row in $new) {
        $f = $row.Split([char]9)
        if (-not (Test-SumelaRecordEq $f[0] 'kept')) { $checks.Add([string[]]@('path', $row.Substring($f[0].Length + 1))) }
        elseif ($f.Length -ne 3) { $checks.Add([string[]]@('path', $row.Substring(5))) }
        else { $checks.Add([string[]]@('path', $f[1])); $checks.Add([string[]]@('why', $f[2])) }
    }
    foreach ($c in $checks) {
        $msg = Test-SumelaRecordValue -Kind $c[0] -Value $c[1]
        if ($msg) { throw (New-SumelaRecordError 2 $msg) }
    }

    # 2. What the replaced record lends this write [RU-M4].
    $parsed = Read-SumelaRecord -Record $Record
    if (($null -ne $parsed) -and (-not $parsed.Ok)) {
        Write-Warning ($parsed.Error + "; Write-SumelaRecord replaces it, nothing carried")
        $parsed = $null
    }
    $open = (Test-SumelaRecordMemberIs -Parsed $parsed -Key 'pending_rerun' -Shape 'raw' -Value 'true') -or
            (Test-SumelaRecordMemberIs -Parsed $parsed -Key 'partial_upgrade' -Shape 'raw' -Value 'true')
    $carry = New-Object System.Collections.Generic.List[string]
    if ($open) {
        foreach ($klass in @('theirs_over_fork', 'merged', 'kept', 'removed')) {   # precedence: a path keeps its first class
            $shape = 's'
            if (Test-SumelaRecordEq $klass 'kept') { $shape = 'o' }
            foreach ($v in (Read-SumelaRecordMember -Parsed $parsed -Key $klass -Shape $shape).Values) { $carry.Add("$klass`t$v") }
        }
        if (-not $bvSet) { $bv = [string]::Join("`n", (Read-SumelaRecordMember -Parsed $parsed -Key 'base_version' -Shape 'str').Values) }
        # upstream_commit is the release commit of the record's version: kept for that version only.
        if ((-not $ucSet) -and (Test-SumelaRecordMemberIs -Parsed $parsed -Key 'version' -Shape 'str' -Value $Version)) {
            $uc = [string]::Join("`n", (Read-SumelaRecordMember -Parsed $parsed -Key 'upstream_commit' -Shape 'str').Values)
        }
    }
    # "files": the carry entries recorded at this HEAD whose content is still what was recorded.
    $root = Get-SumelaRecordRootOf $Record
    $cand = Get-SumelaRecordCarryEntries -Parsed $parsed -Who 'Write-SumelaRecord'
    $headOk = $false
    $headNow = ''
    $gitMsg = ''
    if (($cand.Count -gt 0) -or $unfinished) {
        $h = Get-SumelaRecordHead -Root $root
        if ($h.Ok) { $headOk = $true; $headNow = $h.Head } else { $gitMsg = $h.Error }
    }
    if ($cand.Count -gt 0) {
        $n = $cand.Count
        if (-not $headOk) {
            Write-Warning "Write-SumelaRecord: cannot read the git state of ${root} ($gitMsg); $n earlier path(s) not carried"
        } elseif (Test-SumelaRecordMemberIs -Parsed $parsed -Key 'carry_head' -Shape 'str' -Value $headNow) {
            $was = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::Ordinal)
            $order = New-Object System.Collections.Generic.List[string]
            foreach ($row in $cand) {
                $tab = $row.IndexOf([char]9)
                $was[$row.Substring(0, $tab)] = $row.Substring($tab + 1)
                $order.Add($row.Substring(0, $tab))
            }
            $d = Select-SumelaRecordUncommitted -Root $root -Paths $order.ToArray()
            $bl = $null
            if ($d.Ok) { $bl = Get-SumelaRecordBlobs -Root $root -Paths $d.Paths }
            if ($d.Ok -and $bl.Ok) {
                foreach ($p in $d.Paths) {
                    $now = $null
                    [void]$bl.Map.TryGetValue($p, [ref]$now)
                    if (($null -ne $now) -and (-not (Test-SumelaRecordEq $now '-')) -and (Test-SumelaRecordEq $was[$p] $now)) { $carry.Add("files`t$p") }
                    else { Write-Warning "Write-SumelaRecord: $p changed after it was recorded; not carried (its diff is reviewed as authored)" }
                }
            } else {
                $why = $d.Error
                if ($d.Ok) { $why = $bl.Error }
                Write-Warning "Write-SumelaRecord: cannot list the uncommitted paths in ${root} ($why); $n earlier path(s) not carried"
            }
        }   # recorded at another HEAD: a finished run's paths, never carried
    }
    # Carried values came from an earlier writer: re-check them like new ones.
    $carryOk = New-Object System.Collections.Generic.List[string]
    foreach ($row in $carry) {
        $f = $row.Split([char]9)
        $isKept = Test-SumelaRecordEq $f[0] 'kept'
        $expect = 2; if ($isKept) { $expect = 3 }
        $bad = ($f.Length -ne $expect) -or ($f[1].Length -eq 0) -or ($f[1] -cmatch '[\x00-\x1F\x7F"\\]')
        if ($isKept -and (($f.Length -lt 3) -or ($f[2] -cnotmatch '^[a-z][a-z0-9:-]*\z'))) { $bad = $true }
        if ($bad) { Write-Warning "Write-SumelaRecord: dropped an invalid carried $($f[0]) row: $($f[1])" }
        else { $carryOk.Add($row) }
    }
    if ((-not $bvSet) -and (Test-SumelaRecordValue -Kind 'base' -Value $bv)) {
        Write-Warning 'Write-SumelaRecord: dropped the carried base_version'; $bv = ''
    }
    if ((-not $ucSet) -and (Test-SumelaRecordValue -Kind 'commit' -Value $uc)) {
        Write-Warning 'Write-SumelaRecord: dropped the carried upstream_commit'; $uc = ''
    }

    # 3. One class per path: this write's rows (a path given twice is refused), then the carried
    #    rows in precedence order wherever the path is still unclassified.
    $cls = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::Ordinal)
    $why = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::Ordinal)
    $order = New-Object System.Collections.Generic.List[string]
    foreach ($row in $new) {
        $f = $row.Split([char]9)
        $w = ''; if (Test-SumelaRecordEq $f[0] 'kept') { $w = $f[2] }
        if ($cls.ContainsKey($f[1])) {
            if ((-not (Test-SumelaRecordEq $cls[$f[1]] $f[0])) -or (-not (Test-SumelaRecordEq $why[$f[1]] $w))) {
                throw (New-SumelaRecordError 2 "Write-SumelaRecord: $($f[1]) is given two classes ($($cls[$f[1]]) and $($f[0]))")
            }
            continue
        }
        $cls[$f[1]] = $f[0]; $why[$f[1]] = $w; $order.Add($f[1])
    }
    foreach ($row in $carryOk) {
        $f = $row.Split([char]9)
        if ($cls.ContainsKey($f[1])) { continue }
        $w = ''; if (Test-SumelaRecordEq $f[0] 'kept') { $w = $f[2] }
        $cls[$f[1]] = $f[0]; $why[$f[1]] = $w; $order.Add($f[1])
    }
    $rows = New-Object System.Collections.Generic.List[string]
    foreach ($p in $order) {
        if (Test-SumelaRecordEq $cls[$p] 'kept') { $rows.Add("kept`t$p`t" + $why[$p]) } else { $rows.Add($cls[$p] + "`t" + $p) }
    }
    $final = @(Sort-SumelaRecordRows -Rows $rows.ToArray())
    $outFiles = New-Object System.Collections.Generic.List[string]
    $outKept = New-Object System.Collections.Generic.List[string]
    $outLists = @{
        merged           = (New-Object System.Collections.Generic.List[string])
        theirs_over_fork = (New-Object System.Collections.Generic.List[string])
        removed          = (New-Object System.Collections.Generic.List[string])
    }
    foreach ($row in $final) {
        $f = $row.Split([char]9)
        if (Test-SumelaRecordEq $f[0] 'files') { $outFiles.Add($f[1]) }
        elseif (Test-SumelaRecordEq $f[0] 'kept') { $outKept.Add('{"path": "' + $f[1] + '", "why": "' + $f[2] + '"}') }
        else { $outLists[$f[0]].Add($f[1]) }
    }

    # 4. An unfinished run lists its files in "carry", for the write that completes it.
    $finalCarry = @()
    $withCarry = $false
    if ($unfinished) {
        $bl2 = $null
        if ($headOk) { $bl2 = Get-SumelaRecordBlobs -Root $root -Paths $outFiles.ToArray() }
        if ($headOk -and $bl2.Ok) {
            $rowsC = New-Object System.Collections.Generic.List[string]
            foreach ($p in $outFiles) { $rowsC.Add($p + "`t" + $bl2.Map[$p]) }
            $finalCarry = @(Sort-SumelaRecordRows -Rows $rowsC.ToArray())
            $withCarry = $true
        } else {
            if ($headOk) { $gitMsg = $bl2.Error }
            Write-Warning "Write-SumelaRecord: cannot read the git state of ${root} ($gitMsg); the write that completes this run will not carry its files"
        }
    }

    # 5. Render the canonical v2 layout. (PowerShell names are case-insensitive: no $F beside $f.)
    $ts = [DateTime]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture)
    $pend = 'false'; if ($PendingRerun) { $pend = 'true' }
    $part = 'false'; if (Test-SumelaRecordEq $State 'partial') { $part = 'true' }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("{`n")
    [void]$sb.Append("  `"updater_schema`": 2,`n")
    [void]$sb.Append('  "version": "' + $Version + "`",`n")
    [void]$sb.Append('  "base_version": "' + $bv + "`",`n")
    [void]$sb.Append('  "upstream_commit": "' + $uc + "`",`n")
    [void]$sb.Append('  "updated_at": "' + $ts + "`",`n")
    [void]$sb.Append('  "pending_rerun": ' + $pend + ",`n")
    [void]$sb.Append('  "partial_upgrade": ' + $part + ",`n")
    [void]$sb.Append("  `"files`": [`n")
    for ($j = 0; $j -lt $outFiles.Count; $j++) {
        $sep = ''
        if ($j -lt $outFiles.Count - 1) { $sep = ',' }
        [void]$sb.Append('    "' + $outFiles[$j] + '"' + $sep + "`n")
    }
    [void]$sb.Append("  ],`n")
    [void]$sb.Append('  "merged": ' + (ConvertTo-SumelaRecordArrayText -Items $outLists['merged'].ToArray()) + ",`n")
    [void]$sb.Append('  "kept": [' + [string]::Join(', ', $outKept.ToArray()) + "],`n")
    [void]$sb.Append('  "theirs_over_fork": ' + (ConvertTo-SumelaRecordArrayText -Items $outLists['theirs_over_fork'].ToArray()) + ",`n")
    $afterRemoved = ''; if ($withCarry) { $afterRemoved = ',' }
    [void]$sb.Append('  "removed": ' + (ConvertTo-SumelaRecordArrayText -Items $outLists['removed'].ToArray()) + $afterRemoved + "`n")
    if ($withCarry) {
        [void]$sb.Append('  "carry_head": "' + $headNow + "`",`n")
        [void]$sb.Append('  "carry": ' + (ConvertTo-SumelaRecordCarryText -Rows $finalCarry) + "`n")
    }
    [void]$sb.Append("}`n")
    Save-SumelaRecordText -Record $Record -Text $sb.ToString()

    # 6. Re-read the artifact: the version, the exact "files" list and, for an unfinished run, the
    #    carry as rendered.
    $gotVersion = @(Get-SumelaRecordValue -Key 'version' -Record $Record)
    $same = ($gotVersion.Count -eq 1) -and (Test-SumelaRecordEq $gotVersion[0] $Version) -and
            (Test-SumelaRecordSameList -A @(Get-SumelaRecordFiles -Record $Record) -B $outFiles.ToArray())
    if (-not $same) { throw (New-SumelaRecordError 1 "Write-SumelaRecord: $Record does not hold what was written") }
    if ($withCarry) {
        $again = Read-SumelaRecord -Record $Record
        $same = ($null -ne $again) -and $again.Ok
        if ($same) {
            $got = Get-SumelaRecordCarryEntries -Parsed $again -Who 'Write-SumelaRecord'   # a List: never wrap it in @()
            $same = (Test-SumelaRecordSameList -A $got.ToArray() -B $finalCarry) -and
                    (Test-SumelaRecordMemberIs -Parsed $again -Key 'carry_head' -Shape 'str' -Value $headNow)
        }
        if (-not $same) { throw (New-SumelaRecordError 1 "Write-SumelaRecord: $Record does not hold the carry entries written") }
    }
}
