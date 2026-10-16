# tests/test_migrate_runner.ps1 - the migration runner's PowerShell twin, scripts/sumela-migrate.ps1 (R1-08).
#
# The PowerShell half of tests/test_migrate_runner.sh: the same synthetic upstreams (tagged
# repositories whose notes run small tools), clones of them and projects whose
# .sumela/upstream.conf names the upstream, built with git commands only, run through the
# PowerShell runner. It pins the lint (the strict read-only shapes in plain ASCII words, for run,
# run.ps1, verify and verify.ps1 of a consent: none step, each refused class on its own), the selection
# (phase, version with an exclusive from, id, requires; post-update steps after the stamp; a
# teammate's skipped developer steps; until; declined steps; a resumed session; a 0.19 -> latest
# jump), the guards (requires met only by done, the upgrade worktree, a fail-closed consent gate,
# the read-only gate on the line that runs, rollback that restores a ledger entry), verification
# by artifact, both ledgers, the trust checks (clean clone, upstream origin or -TrustOrigin,
# ls-remote outside the clone, no fsmonitor, regular notes blobs only, credentials never printed,
# control characters refused), the state kept until the merge, the path quoting, the run.ps1 / Git Bash routing
# [RU-I13] and twin parity with the bash runner. Runs under Windows PowerShell 5.1 and pwsh 7,
# and under the tr-TR culture.
#
# Run:  pwsh -NoProfile -File tests/test_migrate_runner.ps1   (or: powershell -NoProfile -File ...)
# Exit 0 = all assertions passed, 1 = a failure (printed above). Keep this file ASCII-only.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repoRoot = Split-Path -Parent $PSScriptRoot
$runner = Join-Path $repoRoot 'scripts/sumela-migrate.ps1'
$bashRunner = Join-Path $repoRoot 'scripts/sumela-migrate.sh'
. (Join-Path $repoRoot 'scripts/lib/sumela-state.ps1')
. (Join-Path $repoRoot 'scripts/lib/sumela-provenance.ps1')

$script:pass = 0
$script:fail = 0
$script:rc = 0
$script:out = ''
$ord = [StringComparison]::Ordinal
function Get-Tail([string]$t) { $l = $t.Split([char]10); $n = [Math]::Max(0, $l.Length - 12); return [string]::Join(' | ', $l[$n..($l.Length - 1)]) }
function Ok([string]$m) { Write-Host "  PASS  $m"; $script:pass++ }
function Bad([string]$m) { Write-Host "  FAIL  $m"; $script:fail++ }
function Skip([string]$m) { Write-Host "  SKIP  $m" }
function Same([string]$label, $expected, $got) {
    if ([string]::Equals([string]$expected, [string]$got, [StringComparison]::Ordinal)) { Ok $label } else { Bad "$label (expected '$expected', got '$got')" }
}
function Has([string]$label, [string]$text, [string]$want) {
    if ($text.IndexOf($want, [StringComparison]::Ordinal) -ge 0) { Ok $label } else { Bad "$label (wanted '$want' in: $(Get-Tail $text))" }
}
function Lacks([string]$label, [string]$text, [string]$want) {
    if ($text.IndexOf($want, [StringComparison]::Ordinal) -lt 0) { Ok $label } else { Bad "$label (did not want '$want' in: $(Get-Tail $text))" }
}
function RcIs([string]$label, [int]$want) {
    if ($script:rc -eq $want) { Ok $label } else { Bad "$label (expected exit $want, got $($script:rc): $(Get-Tail $script:out))" }
}

$utf8 = New-Object System.Text.UTF8Encoding $false
$onWindows = [string]::Equals([string]$env:OS, 'Windows_NT', [StringComparison]::Ordinal)
$psHost = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$work = Join-Path ([IO.Path]::GetTempPath()) ('sumela-migrate-ps-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($work)
$work = ((Resolve-Path -LiteralPath $work).ProviderPath).Replace('\', '/')
if (-not $onWindows) {
    # The physical path, as git prints it (macOS: /var is a link to /private/var).
    $ErrorActionPreference = 'Continue'
    $phys = [string](& /bin/sh -c 'cd "$1" && pwd -P' sh $work)
    $ErrorActionPreference = 'Stop'
    if ($phys) { $work = $phys.Trim() }
}
$noHooks = $work + '/no-hooks'

function Write-Text([string]$path, [string]$text) {
    # LF and UTF-8 without BOM, whatever line ends this script was checked out with.
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
    [IO.File]::WriteAllText($path, $text.Replace("`r`n", "`n"), $utf8)
}
function Read-Text([string]$path) { if ([IO.File]::Exists($path)) { return [IO.File]::ReadAllText($path, $utf8) }; return '' }
function tgit {
    $ErrorActionPreference = 'Continue'
    $o = & git -c commit.gpgsign=false -c tag.gpgsign=false -c "core.hooksPath=$noHooks" -c init.defaultBranch=main @args 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git $($args -join ' ') failed: $o" }
}
function gitout {
    $ErrorActionPreference = 'Continue'
    $o = & git @args 2>$null
    return [string]::Join("`n", @($o | ForEach-Object { ([string]$_).TrimEnd([char]13) }))
}
function Set-EnvVar([string]$n, $v) {
    if ($null -eq $v) { [Environment]::SetEnvironmentVariable($n, [NullString]::Value) } else { [Environment]::SetEnvironmentVariable($n, [string]$v) }
}
function Invoke-Mig {
    # Runs the PowerShell runner (or the bash one) from <Dir> in its own process; $script:out, $script:rc.
    param([string]$Dir, [string[]]$MigArgs, [hashtable]$Env = @{}, [string]$Runner = $runner)
    $saved = @{}
    Push-Location -LiteralPath $Dir
    try {
        foreach ($k in $Env.Keys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k); Set-EnvVar $k $Env[$k] }
        $ErrorActionPreference = 'Continue'
        if ($Runner.EndsWith('.sh', $ord)) { $o = & $script:bash $Runner @MigArgs 2>&1 }
        else { $o = & $psHost -NoProfile -File $Runner @MigArgs 2>&1 }
        $script:rc = $LASTEXITCODE
        $script:out = [string]::Join("`n", @($o | ForEach-Object { ([string]$_).TrimEnd([char]13) }))
    } finally {
        foreach ($k in $saved.Keys) { Set-EnvVar $k $saved[$k] }
        Pop-Location
    }
}
function Get-PendingIds {
    $ids = New-Object System.Collections.Generic.List[string]
    foreach ($l in $script:out.Split([char]10)) {
        $m = [regex]::Match($l, '^    (\S+)  .*consent=')
        if ($m.Success) { $ids.Add($m.Groups[1].Value) }
    }
    return [string]::Join(' ', $ids.ToArray())
}
function Find-Bash {
    # Git Bash on Windows (the runner's two paths; never bash from PATH: that may be WSL); bash
    # from PATH elsewhere.
    if ($onWindows) {
        $ErrorActionPreference = 'Continue'
        $exec = [string](& git --exec-path)
        foreach ($rel in @('../../../bin/bash.exe', '../../../usr/bin/bash.exe')) {
            $p = [IO.Path]::GetFullPath((Join-Path $exec $rel))
            if ([IO.File]::Exists($p)) { return $p }
        }
        return $null
    }
    $cmd = Get-Command bash -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    return $null
}
$script:bash = Find-Bash

# --- Fixtures --------------------------------------------------------------------------------------
function Write-Tools([string]$dir) {
    Write-Text "$dir/tools/step.sh" @'
#!/usr/bin/env bash
# step.sh <name>: one step's effect, in the step's checkout
printf '%s\n' "$1" >> order.log
: > "done-$1"
echo "step $1 ran"
'@
    Write-Text "$dir/tools/dryrun.sh" @'
#!/usr/bin/env bash
# dryrun.sh --plan: the dry run, recorded as plan-<release>; --plan-check: its artifact (read-only)
v="$(tr -d '\r\n' < "$SUMELA_MIGRATE_SRC/.sumela/VERSION")"
if [ "${1:-}" = --plan-check ]; then if [ -f "done-plan-$v" ]; then echo ok; else echo "missing done-plan-$v"; fi; exit 0; fi
printf '%s\n' "plan-$v" >> order.log; : > "done-plan-$v"; echo "dry run for $v"
'@
    Write-Text "$dir/tools/validate.sh" @'
#!/usr/bin/env bash
# validate.sh --check: the validation, recorded as validate-<release>; --status: its artifact (read-only)
v="$(tr -d '\r\n' < "$SUMELA_MIGRATE_SRC/.sumela/VERSION")"
if [ "${1:-}" = --status ]; then if [ -f "done-validate-$v" ]; then echo ok; else echo "missing done-validate-$v"; fi; exit 0; fi
printf '%s\n' "validate-$v" >> order.log; : > "done-validate-$v"; echo "validated $v"
'@
    Write-Text "$dir/tools/check.sh" @'
#!/usr/bin/env bash
# check.sh <name>: the artifact step.sh leaves
if [ -f "done-$1" ]; then echo ok; else echo "missing done-$1"; fi
'@
    Write-Text "$dir/tools/apply.sh" @'
#!/usr/bin/env bash
# apply.sh <version>: the apply step stamps VERSION
printf '%s\n' "apply-$1" >> order.log
: > "done-apply-$1"
printf '%s\n' "$1" > .sumela/VERSION
'@
    Write-Text "$dir/tools/args.sh" @'
#!/usr/bin/env bash
# args.sh: its arguments, one per line, and the two runner variables
for a in "$@"; do printf 'arg=%s\n' "$a"; done
printf 'src=%s\nroot=%s\n' "$SUMELA_MIGRATE_SRC" "$SUMELA_MIGRATE_ROOT"
'@
    Write-Text "$dir/tools/step.ps1" @'
# step.ps1 <name>: step.sh for the PowerShell runner (the same bytes)
param([string]$Name)
$utf8 = New-Object System.Text.UTF8Encoding $false
[IO.File]::AppendAllText((Join-Path (Get-Location).ProviderPath 'order.log'), "$Name`n", $utf8)
[IO.File]::WriteAllText((Join-Path (Get-Location).ProviderPath "done-$Name"), '', $utf8)
Write-Output "step $Name ran"
'@
    Write-Text "$dir/tools/check.ps1" @'
# check.ps1 <name>: check.sh for the PowerShell runner
param([string]$Name)
if (Test-Path -LiteralPath (Join-Path (Get-Location).ProviderPath "done-$Name")) { Write-Output 'ok' } else { Write-Output "missing done-$Name" }
'@
}
$genericNotes = @'
# Synthetic upgrade procedure

```sumela-step
id: upgrade-01
title: Create the upgrade worktree for v{TARGET}
scope: repo
when: pre-update
consent: confirm
run: -
verify: git -C "{ROOT}" rev-parse --abbrev-ref HEAD
expect: match:upgrade-{TARGET}$
rollback: b="$(git -C "{ROOT}" rev-parse --abbrev-ref HEAD)" && c="$(git -C "{ROOT}" rev-parse --path-format=absolute --git-common-dir)" && cd "$c/.." && git worktree remove --force "{ROOT}" && git branch -D "$b"
agent: git worktree add --no-track -b <prefix>upgrade-{TARGET} <worktree> <base>, then set prefix= base= worktree=
```

```sumela-step
id: upgrade-02
title: Dry run
scope: repo
when: pre-update
requires: upgrade-01
consent: none
run: bash "{SRC}/tools/dryrun.sh" --plan
verify: bash "{SRC}/tools/dryrun.sh" --plan-check
expect: equals:ok
```

```sumela-step
id: upgrade-03
title: Apply
scope: repo
when: update
requires: upgrade-02
consent: confirm
run: bash "{SRC}/tools/apply.sh" "{TARGET}"
verify: bash "{SRC}/tools/check.sh" "apply-{TARGET}"
expect: equals:ok
rollback: bash -c "rm -f done-apply-{TARGET}"
```

```sumela-step
id: upgrade-04
title: Parity
scope: repo
when: post-update
requires: upgrade-03
consent: confirm
run: bash "{SRC}/tools/step.sh" "parity-{TARGET}"
run.ps1: & "{SRC}/tools/step.ps1" "parity-{TARGET}"
verify: bash "{SRC}/tools/check.sh" "parity-{TARGET}"
verify.ps1: & "{SRC}/tools/check.ps1" "parity-{TARGET}"
expect: equals:ok
rollback: bash -c "exit 7"
```

```sumela-step
id: upgrade-05
title: Mirrors
scope: repo
when: post-update
requires: upgrade-03
consent: confirm
run: bash "{SRC}/tools/step.sh" "mirrors-{TARGET}"
verify: bash "{SRC}/tools/check.sh" "mirrors-{TARGET}"
expect: equals:ok
```

```sumela-step
id: upgrade-06
title: Validate
scope: repo
when: post-update
requires: upgrade-04
consent: none
run: bash "{SRC}/tools/validate.sh" --check
verify: bash "{SRC}/tools/validate.sh" --status
expect: equals:ok
```

```sumela-step
id: upgrade-07
title: Commit
scope: repo
when: finalize
requires: upgrade-06
consent: confirm
ledger: none
run: -
verify: git -C "{ROOT}" log -1 --format=%s
expect: match:upgrade to v{TARGET}
rollback: git -C "{ROOT}" reset --soft HEAD~1
agent: commit with a subject containing upgrade to v{TARGET}
```
'@
$fence = '```'
function Get-StepBlock([string]$id, [string]$sc, [string]$wh, [string[]]$extra = @()) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("${fence}sumela-step`nid: $id`ntitle: Step $id`nscope: $sc`nwhen: $wh`nconsent: confirm`n")
    foreach ($l in $extra) { [void]$sb.Append($l + "`n") }
    if ($sc -ceq 'repo') { $r = '{SRC}' } else { $r = '{ROOT}' }
    [void]$sb.Append("run: bash `"$r/tools/step.sh`" `"v$id`"`nverify: bash `"$r/tools/check.sh`" `"v$id`"`nexpect: equals:ok`n$fence`n`n")
    return $sb.ToString()
}
function Get-Block([string]$body) { return "${fence}sumela-step`n$body`n$fence`n" }
function Write-Generic([string]$dir) { Write-Text "$dir/upgrade.md" $genericNotes }
function Write-Compose([string]$dir) {
    Write-Generic $dir
    Write-Text "$dir/0.20.0.md" ("# 0.20.0`n`n" + (Get-StepBlock '0.20.0-01' 'repo' 'post-update') + (Get-StepBlock '0.20.0-02' 'developer' 'first-session') + (Get-StepBlock '0.20.0-03' 'repo' 'post-update' @('until: 0.20.2')))
    Write-Text "$dir/0.20.1.md" ("# 0.20.1`n`n" + (Get-StepBlock '0.20.1-01' 'repo' 'post-update' @('requires: upgrade-04')) + (Get-StepBlock '0.20.1-02' 'repo' 'update' @('requires: upgrade-02')))
    Write-Text "$dir/0.20.2.md" ("# 0.20.2`n`n" + (Get-StepBlock '0.20.2-01' 'repo' 'pre-update' @('requires: upgrade-01')) + (Get-StepBlock '0.20.2-02' 'repo' 'post-update'))
}
function Copy-Notes([string]$from, [string]$to) {
    [void][IO.Directory]::CreateDirectory($to)
    foreach ($f in [IO.Directory]::GetFiles($from, '*.md')) { [IO.File]::Copy($f, (Join-Path $to ([IO.Path]::GetFileName($f))), $true) }
}
function New-Release([string]$dir, [string]$version, [string]$tag, [string]$notes) {
    [void][IO.Directory]::CreateDirectory($dir)
    tgit init -q $dir
    Write-Text "$dir/.sumela/VERSION" "$version`n"
    Write-Text "$dir/.gitattributes" "*.sh text eol=lf`n*.ps1 text eol=lf`n"
    Copy-Notes $notes "$dir/scripts/sumela-migrations"
    Write-Tools $dir
    tgit -C $dir add -A
    tgit -C $dir commit -qm "release $version"
    if ($tag -cne '-') { tgit -C $dir tag -a -m "release $tag" $tag }
}
function Get-Src([string]$release) {
    # <release>.clone: a clone of the upstream, at its HEAD, its tags fetched
    $c = $release + '.clone'
    $head = gitout -C $release rev-parse HEAD
    if (-not [IO.Directory]::Exists($c)) { tgit clone -q -- $release $c }
    tgit -C $c fetch -q --tags --force --prune --prune-tags origin
    tgit -C $c -c advice.detachedHead=false checkout -q --detach $head
    return $c
}
function New-Project([string]$dir, [string]$version, [string]$notes = '', [string]$up = '') {
    [void][IO.Directory]::CreateDirectory($dir)
    tgit init -q $dir
    Write-Text "$dir/.sumela/VERSION" "$version`n"
    Write-Text "$dir/app.txt" "app`n"
    Write-Text "$dir/.gitattributes" "*.sh text eol=lf`n*.ps1 text eol=lf`n"
    Write-Text "$dir/.gitignore" ".sumela/.last-update.json`n"
    if ($up) { Write-Text "$dir/.sumela/upstream.conf" "# upstream`n$up`n" }
    if ($notes) { Copy-Notes $notes "$dir/scripts/sumela-migrations"; Write-Tools $dir }
    tgit -C $dir add -A
    tgit -C $dir commit -qm "project at $version"
}
$script:stepLog = ''
function Invoke-Steps([string]$proj, [string]$wt, [string]$tgt, [string[]]$ids, [hashtable]$Env = @{}) {
    # show, run (or the scripted equivalent), verify, record done
    foreach ($id in $ids) {
        Invoke-Mig $proj @('show', $id) $Env
        if ($script:rc -ne 0) { $script:stepLog += " show ${id}: $($script:rc);"; continue }
        if ($id -ceq 'upgrade-01') {
            tgit -C $proj worktree add -q --no-track -b "sumela/upgrade-$tgt" $wt main
            Invoke-Mig $proj @('set', 'prefix=sumela/', 'base=main', "worktree=$wt") $Env
        } elseif ($id -ceq 'upgrade-07') {
            tgit -C $wt add -A
            tgit -C $wt commit -qm "chore(sumela): upgrade to v$tgt"
            $script:rc = 0
        } else { Invoke-Mig $proj @('run', $id) $Env }
        if ($script:rc -ne 0) { $script:stepLog += " run ${id}: $($script:rc) ($(Get-Tail $script:out));"; continue }
        Invoke-Mig $proj @('verify', $id) $Env
        if ($script:rc -ne 0) { $script:stepLog += " verify ${id}: $($script:rc) ($(Get-Tail $script:out));"; continue }
        Invoke-Mig $proj @('record', $id, 'done') $Env
        if ($script:rc -ne 0) { $script:stepLog += " record ${id}: $($script:rc);" }
    }
}
function Get-Mode([string]$p) {
    $ErrorActionPreference = 'Continue'
    $s = [string](& stat -c %a $p 2>$null)
    if ($LASTEXITCODE -ne 0) { $s = [string](& stat -f %Lp $p 2>$null) }
    return $s.Trim()
}

$savedEnv = @{}
foreach ($n in @('XDG_STATE_HOME', 'LOCALAPPDATA', 'GIT_ALLOW_PROTOCOL', 'GIT_AUTHOR_NAME', 'GIT_AUTHOR_EMAIL', 'GIT_COMMITTER_NAME', 'GIT_COMMITTER_EMAIL', 'GIT_DIR', 'GIT_WORK_TREE', 'PSExecutionPolicyPreference')) { $savedEnv[$n] = [Environment]::GetEnvironmentVariable($n) }
try {
    foreach ($n in @('GIT_DIR', 'GIT_WORK_TREE', 'PSExecutionPolicyPreference')) { Set-EnvVar $n $null }
    if ($onWindows) { $env:LOCALAPPDATA = $work + '/localappdata'; [void][IO.Directory]::CreateDirectory($env:LOCALAPPDATA) }
    else { $env:XDG_STATE_HOME = $work + '/state' }
    $env:GIT_ALLOW_PROTOCOL = 'file:https:ssh:git'
    $env:GIT_AUTHOR_NAME = 'Test'; $env:GIT_AUTHOR_EMAIL = 't@example.com'; $env:GIT_COMMITTER_NAME = 'Test'; $env:GIT_COMMITTER_EMAIL = 't@example.com'
    if (-not $script:bash) { Write-Host 'FAIL: bash (Git Bash on Windows) is required: the synthetic notes run bash tools'; exit 1 }

    $notes = "$work/notes"; Write-Compose $notes
    $gen = "$work/notes-generic"; Write-Generic $gen; Write-Text "$gen/0.20.0.md" (Get-StepBlock '0.20.0-01' 'repo' 'post-update')

    Write-Host 'Migration runner, PowerShell twin (scripts/sumela-migrate.ps1)'
    Write-Host "  host: $($PSVersionTable.PSVersion) $([Threading.Thread]::CurrentThread.CurrentCulture.Name)"

    Write-Host '== t_parse_and_validate_required_keys'
    Invoke-Mig $repoRoot @('lint', "$notes/upgrade.md", "$notes/0.20.0.md", "$notes/0.20.1.md", "$notes/0.20.2.md")
    RcIs 'the synthetic notes lint clean' 0
    Has '...a version file is reported with its step count' $script:out '0.20.0.md: ok (3 steps)'
    $bad = "$work/bad"; Copy-Notes $notes $bad
    $full = "id: 0.21.0-01`ntitle: T`nscope: repo`nwhen: post-update`nconsent: confirm`nrun: bash scripts/x.sh`nverify: bash scripts/x.sh --check`nexpect: exit0"
    function Get-None([string]$run) { return $full.Replace('consent: confirm', 'consent: none').Replace('run: bash scripts/x.sh', "run: $run") }
    function Test-LintCase([string]$label, [string]$want, [string]$content, [string]$name = '0.21.0.md') {
        Write-Text "$bad/$name" $content
        Invoke-Mig $repoRoot @('lint', "$bad/$name")
        if ($script:rc -eq 4) { Has "$label -> exit 4" $script:out $want } else { Bad "$label -> exit 4 (got $($script:rc): $(Get-Tail $script:out))" }
        [IO.File]::Delete("$bad/$name")
    }
    function Test-LintOk([string]$label, [string]$content, [string]$name = '0.21.0.md') {
        Write-Text "$bad/$name" $content
        Invoke-Mig $repoRoot @('lint', "$bad/$name")
        if ($script:rc -eq 0) { Ok $label } else { Bad "$label (exit $($script:rc): $(Get-Tail $script:out))" }
        [IO.File]::Delete("$bad/$name")
    }
    Test-LintCase 'a missing verify' 'missing verify' (Get-Block ($full.Replace("verify: bash scripts/x.sh --check`n", '')))
    Test-LintCase 'an unknown key' 'unknown key expects' (Get-Block ($full + "`nexpects: exit0"))
    Test-LintCase 'a duplicate id' 'duplicate id 0.21.0-01' ((Get-Block $full) + (Get-Block $full))
    Test-LintCase 'an unterminated block' 'unterminated sumela-step block' ("${fence}sumela-step`n$full`n")
    Test-LintCase 'a consent value in another case' 'consent must be none, confirm or explicit, not Explicit' (Get-Block ($full.Replace('consent: confirm', 'consent: Explicit')))
    Test-LintCase 'a ledger value other than none' 'ledger takes only none' (Get-Block ($full + "`nledger: yes"))
    Test-LintCase 'an until that is not X.Y.Z' 'until must be a version X.Y.Z, not 0.22' (Get-Block ($full + "`nuntil: 0.22"))
    Test-LintCase '{ROOT} in expect' 'expect cannot use {ROOT}' (Get-Block ($full.Replace('expect: exit0', 'expect: match:{ROOT}')))
    Test-LintCase 'a bad expect form' 'expect must be' (Get-Block ($full.Replace('expect: exit0', 'expect: nonzero')))
    Test-LintCase 'an invalid match pattern' 'not a valid extended regular expression' (Get-Block ($full.Replace('expect: exit0', 'expect: match:a(b')))
    Test-LintCase 'an unquoted {SRC}' 'must sit inside double quotes' (Get-Block ($full.Replace('run: bash scripts/x.sh', 'run: bash {SRC}/x.sh')))
    Test-LintCase 'a single-quoted {ROOT}' 'must sit inside double quotes' (Get-Block ($full.Replace('run: bash scripts/x.sh', "run: bash '{ROOT}/x.sh'")))
    Test-LintCase 'an escaped {SRC}' 'must sit inside double quotes' (Get-Block ($full.Replace('run: bash scripts/x.sh', 'run: bash "\{SRC}/x.sh"')))
    Test-LintOk 'a placeholder quoted inside $( ... ) is fine' (Get-Block ($full.Replace('run: bash scripts/x.sh', 'run: bash -c "$(git -C "{ROOT}" rev-parse HEAD)"')))
    Test-LintCase 'consent none on a writing run' 'consent: none needs' (Get-Block (Get-None 'bash scripts/x.sh'))
    Test-LintCase 'consent none with bash -c and a read-only flag tacked on' 'consent: none needs' (Get-Block (Get-None 'bash -c "rm -rf docs .sumela" --check'))
    Test-LintCase 'consent none with write flags beside the check flag' 'consent: none needs' (Get-Block (Get-None 'bash scripts/sumela-registry-parity.sh --sync --yes --check'))
    Test-LintCase 'consent none with a single-quoted command beside git config --get' 'consent: none needs' (Get-Block (Get-None "bash -c 'git config --unset-all user.name' git config --get"))
    Test-LintCase 'consent none with && after the check' 'consent: none needs' (Get-Block (Get-None 'bash scripts/x.sh --check && rm -rf docs'))
    Test-LintCase 'consent none with a writing run.ps1' 'consent: none needs a read-only run.ps1 too' (Get-Block ((Get-None 'bash scripts/update.sh --plan') + "`nrun.ps1: powershell -NoProfile -File scripts/update.ps1 -ApplyPlan"))
    Test-LintOk 'consent none on the read-only shapes, with the PowerShell twin' (Get-Block ((Get-None 'bash "{SRC}/scripts/update.sh" --source "{SRC}" --plan') + "`nrun.ps1: powershell -NoProfile -File `"{SRC}/scripts/update.ps1`" -SourceDir `"{SRC}`" -Plan"))
    Test-LintOk '...git config --local --get <key>, in both forms' (Get-Block ((Get-None 'git config --local --get sumela.k') + "`nrun.ps1: git config --local --get sumela.k"))
    # The read-only shapes take plain words only, so bash and PowerShell split a line alike: every
    # refused class on its own (a mutant that lets any one through fails here).
    function Get-NoneBlk([string]$run, [string]$verify, [string[]]$extra = @()) {
        $body = "id: 0.21.0-01`ntitle: T`nscope: repo`nwhen: post-update`nconsent: none`nrun: $run`nverify: $verify"
        foreach ($l in $extra) { $body += "`n$l" }
        return (Get-Block ($body + "`nexpect: exit0"))
    }
    $roV = 'bash scripts/x.sh --check'
    $lq = [string][char]0x201C; $rq = [string][char]0x201D; $lq9 = [string][char]0x201E
    $ls = [string][char]0x2018; $rs = [string][char]0x2019; $en = [string][char]0x2013; $nbsp = [string][char]0x00A0
    $roBad = [ordered]@{
        '$( ) inside a string' = 'bash scripts/x.sh --source "$(touch PWNED)" --check'
        'a backtick inside a string' = 'bash scripts/x.sh --source "a`touch PWNED`" --check'
        'a $ in a word' = 'bash scripts/x.sh --source $HOME --check'
        '# (bash drops the rest of the line, the mode flag with it)' = 'bash scripts/x.sh --source #x --check'
        'a ; inside a string' = 'bash scripts/x.sh --source "a;b" --check'
        'an & inside a string' = 'bash scripts/x.sh --source "a&b" --check'
        'a pipe' = 'bash scripts/x.sh --check | tee out'
        'a redirection' = 'bash scripts/x.sh --check > out'
        'parentheses' = 'bash scripts/x.sh --source (x) --check'
        'braces that are no placeholder' = 'bash scripts/x.sh --source {a,b} --check'
        'a single-quoted word' = "bash scripts/x.sh --source 'a b' --check"
        'a backslash' = 'bash scripts/x.sh --source a\ b --check'
        'a glob' = 'bash scripts/*.sh --check'
        'a tilde' = 'bash scripts/x.sh --source ~/x --check'
        'a quote inside a word' = 'bash scripts/x.sh --source a"b c"d --check'
        'a word glued to a string' = 'bash scripts/x.sh --source "a"b --check'
        'a string glued to a word' = 'bash scripts/x.sh --source a"b c" --check'
        'a brace that opens no placeholder' = 'bash scripts/x.sh --source a{b --check'
        'a word that starts with a brace (a script block in PowerShell)' = 'bash scripts/x.sh --source {b --check'
        'an empty string' = 'bash scripts/x.sh --source "" --check'
        'curly double quotes (U+201C, U+201D)' = "bash scripts/x.sh --source `"a$lq --sync ${rq}b`" --check"
        'a low double quote (U+201E)' = "bash scripts/x.sh --source `"a$lq9 --sync ${rq}b`" --check"
        'curly single quotes (U+2018, U+2019)' = "bash scripts/x.sh --source ${ls}a b$rs --check"
        'an en dash (U+2013)' = "bash scripts/x.sh $en${en}check"
        'a no-break space (U+00A0)' = "bash scripts/x.sh --check$nbsp--sync"
        'a comma outside a string (an array in PowerShell)' = 'bash scripts/x.sh --source a,b --check'
        'a word that starts with @ (splatting in PowerShell)' = 'bash scripts/x.sh --source @x --check'
        'git -C with an option for a directory' = 'git -C --exec-path=x config --get k'
    }
    foreach ($k in $roBad.Keys) { Test-LintCase "consent none refuses $k" 'consent: none needs run: - or a read-only run' (Get-NoneBlk $roBad[$k] $roV) }
    Test-LintCase 'consent none refuses a tab' 'a value holds a tab character' (Get-NoneBlk "bash scripts/x.sh`t--check" $roV)
    $roBadPs = [ordered]@{
        'curly quotes that close an ASCII quote in PowerShell' = "pwsh -NoProfile -File tools/x.ps1 -SourceDir `"a$lq -Sync ${lq}b`" -Check"
        'curly quotes around a git subcommand' = "git -C `".$lq branch -D feature -- $lq.`" config --get sumela.k"
        'a comma (PowerShell passes a,-Sync as two arguments)' = 'pwsh -NoProfile -File tools/x.ps1 -SourceDir a,-Sync -Check'
        'splatting' = 'pwsh -NoProfile -File tools/x.ps1 -SourceDir @x -Check'
        'a $ inside a string' = 'pwsh -NoProfile -File tools/x.ps1 -SourceDir "$env:TEMP" -Check'
        'a backtick-escaped quote' = 'pwsh -NoProfile -File tools/x.ps1 -SourceDir "a`" -Sync -Check'
        'an en dash for a parameter' = "pwsh -NoProfile -File tools/x.ps1 ${en}Sync -Check"
    }
    foreach ($k in $roBadPs.Keys) { Test-LintCase "consent none refuses, in run.ps1, $k" 'consent: none needs a read-only run.ps1 too' (Get-NoneBlk $roV $roV @("run.ps1: $($roBadPs[$k])")) }
    Test-LintOk 'plain words, whole strings with spaces and commas, @ and : inside a word' (Get-NoneBlk 'bash scripts/x.sh --source "{SRC}/a b,c" --check' 'bash scripts/x.sh --source user@host:x/y --check' @('run.ps1: pwsh -NoProfile -File "{SRC}/tools/x.ps1" -SourceDir "{SRC}/a b" -Check'))
    # consent: none runs its verify without asking too: verify and verify.ps1 take the same shapes.
    Test-LintCase 'consent none with a writing verify on a run: - step' 'consent: none needs a read-only verify too' (Get-NoneBlk '-' 'bash -c "touch PWNED"' @('agent: nothing to do'))
    Test-LintCase 'consent none with a writing verify beside a read-only run' 'consent: none needs a read-only verify too' (Get-NoneBlk $roV 'bash scripts/x.sh --sync')
    Test-LintCase 'consent none with a writing verify.ps1' 'consent: none needs a read-only verify.ps1 too' (Get-NoneBlk $roV $roV @('verify.ps1: pwsh -NoProfile -File tools/x.ps1 -Sync'))
    Test-LintOk 'consent none on a run: - step whose verify is read-only' (Get-NoneBlk '-' 'git -C "{ROOT}" config --local --get sumela.k' @('agent: nothing to do', 'verify.ps1: powershell -NoProfile -File "{SRC}/tools/x.ps1" -Check'))
    Test-LintCase 'a requires cycle' 'requires forms a cycle' ((Get-Block ($full + "`nrequires: 0.21.0-02")) + (Get-Block ($full.Replace('id: 0.21.0-01', 'id: 0.21.0-02') + "`nrequires: 0.21.0-01")))
    Test-LintCase 'a runnable step without run.ps1 or a bash line' 'needs run.ps1' (Get-Block ($full.Replace('run: bash scripts/x.sh', 'run: git config --local x y')))
    Test-LintCase '{SRC} in a developer step' 'a developer step cannot use {SRC}' (Get-Block ($full.Replace('scope: repo', 'scope: developer').Replace('when: post-update', 'when: first-session').Replace('run: bash scripts/x.sh', 'run: bash "{SRC}/x.sh"')))
    $crlf = (Read-Text "$notes/0.20.1.md").Replace("`n", "`r`n")
    [IO.File]::WriteAllText("$bad/0.20.1.md", $crlf, $utf8)
    Invoke-Mig $repoRoot @('lint', "$bad/0.20.1.md")
    RcIs 'CRLF notes lint clean' 0
    Has '...and parse to the same steps' $script:out '0.20.1.md: ok (2 steps)'
    $inv = "$work/inv-notes"; Write-Generic $inv; Write-Text "$inv/0.20.0.md" (Get-Block ($full.Replace("verify: bash scripts/x.sh --check`n", '').Replace('0.21.0', '0.20.0')))
    New-Release "$work/inv-rel" '0.20.0' 'v0.20.0' $inv
    New-Project "$work/inv-proj" '0.19.0' '' "$work/inv-rel"
    Invoke-Mig "$work/inv-proj" @('plan', '-Source', (Get-Src "$work/inv-rel"), '-Scope', 'repo')
    RcIs 'plan from a release whose notes fail the lint exits 4' 4
    Has '...naming the defect at its path in the clone' $script:out "$work/inv-rel.clone/scripts/sumela-migrations/0.20.0.md:1: step 0.20.0-01: missing verify"
    if (-not [IO.File]::Exists("$work/inv-proj/.sumela/.upgrade/migrate.state")) { Ok '...and writes no state' } else { Bad '...and writes no state' }

    Write-Host '== t_plan_orders_by_phase_version_requires'
    New-Release "$work/rel" '0.20.2' 'v0.20.2' $notes
    New-Project "$work/p1" '0.19.0' '' "$work/rel"
    $relSrc = Get-Src "$work/rel"
    Invoke-Mig "$work/p1" @('plan', '-Source', $relSrc, '-Scope', 'repo')
    RcIs 'plan -Source exits 0' 0
    Same 'phase, then version, then id, with requires respected (the bash runner''s order)' `
        'upgrade-01 0.20.2-01 upgrade-02 0.20.1-02 upgrade-03 0.20.0-01 0.20.2-02 upgrade-04 0.20.1-01 upgrade-05 upgrade-06 upgrade-07' (Get-PendingIds)
    Has '...it ends with the two counts' $script:out 'pending_repo=12 pending_developer=0'
    Invoke-Mig "$work/p1" @('run', 'upgrade-02')
    RcIs 'run refuses a step whose requires is not done' 1
    Has '...and names it' $script:out 'upgrade-01 (not done yet)'
    Invoke-Mig "$work/p1" @('run', '0.20.0-01')
    RcIs 'a repo step does not run in the main checkout' 1
    Has '...it needs the upgrade worktree' $script:out 'runs in the upgrade worktree, which upgrade-01 creates'
    Invoke-Mig "$work/p1" @('record', 'upgrade-01', 'not-applicable')
    RcIs '...nor is anything recorded there' 1

    Write-Host '== t_target_placeholder_composes_0_19_to_latest'
    Invoke-Mig "$work/p1" @('plan', '-Source', $relSrc, '-Scope', 'repo')
    $order = (Get-PendingIds).Split(' ')
    $script:stepLog = ''
    Invoke-Steps "$work/p1" "$work/p1-upgrade" '0.20.2' $order
    Same 'every step shows, runs, verifies and records in plan order' '' $script:stepLog
    $wt = "$work/p1-upgrade"
    Same 'one worktree on one branch named by {TARGET}' 'sumela/upgrade-0.20.2' (gitout -C $wt rev-parse --abbrev-ref HEAD)
    Same 'the steps ran in order, with {TARGET} substituted (upgrade-04 through run.ps1)' `
        'v0.20.2-01 plan-0.20.2 v0.20.1-02 apply-0.20.2 v0.20.0-01 v0.20.2-02 parity-0.20.2 v0.20.1-01 mirrors-0.20.2 validate-0.20.2' `
        ((Read-Text "$wt/order.log").Trim().Replace("`n", ' '))
    $names = @()
    if ([IO.Directory]::Exists("$wt/.sumela/migrations-applied")) { $names = @([IO.Directory]::GetFiles("$wt/.sumela/migrations-applied") | ForEach-Object { [IO.Path]::GetFileName($_) }) }
    [Array]::Sort($names, [StringComparer]::Ordinal)
    Same 'the ledgers: generic steps @target, version steps by id' `
        '0.20.0-01 0.20.1-01 0.20.1-02 0.20.2-01 0.20.2-02 upgrade-01@0.20.2 upgrade-02@0.20.2 upgrade-03@0.20.2 upgrade-04@0.20.2 upgrade-05@0.20.2 upgrade-06@0.20.2' ([string]::Join(' ', $names))
    Same 'the main checkout is untouched' '' (gitout -C "$work/p1" status --porcelain)
    Invoke-Mig "$work/p1" @('status')
    Same 'nothing is left' 'pending_repo=0 pending_developer=0' $script:out
    Invoke-Mig "$work/p1" @('plan', '-Source', $relSrc, '-Scope', 'repo')
    Has 'plan says every step is recorded (ledger: none included), the merge still to come' $script:out 'every repo step is recorded: merge the upgrade pull request'
    if ([IO.File]::Exists("$work/p1/.sumela/.upgrade/migrate.state")) { Ok '...and keeps its state until the main checkout has the merge' } else { Bad '...and keeps its state until the main checkout has the merge' }

    Write-Host '== t_post_update_steps_survive_stamp'
    New-Release "$work/rel20" '0.20.0' 'v0.20.0' $gen
    New-Project "$work/p2" '0.19.0' '' "$work/rel20"
    $rel20Src = Get-Src "$work/rel20"
    Invoke-Mig "$work/p2" @('plan', '--source', $rel20Src, '--scope', 'repo')
    $script:stepLog = ''
    Invoke-Steps "$work/p2" "$work/p2-upgrade" '0.20.0' @('upgrade-01', 'upgrade-02', 'upgrade-03')
    Same 'the first three steps pass (GNU-style options work too)' '' $script:stepLog
    Same 'the apply stamped VERSION in the worktree' '0.20.0' (Read-Text "$work/p2-upgrade/.sumela/VERSION").Trim()
    Invoke-Mig "$work/p2" @('plan', '-Source', $rel20Src, '-Scope', 'repo')
    Same 'the version step and steps 04-07 are still listed' '0.20.0-01 upgrade-04 upgrade-05 upgrade-06 upgrade-07' (Get-PendingIds)

    Write-Host '== t_requires_need_done_and_declined_is_listed'
    Invoke-Mig "$work/p2" @('record', '0.20.0-01', 'declined'); RcIs 'a step can be declined' 0
    Invoke-Mig "$work/p2" @('plan', '-Source', $rel20Src, '-Scope', 'repo')
    Has 'plan lists the declined step as still to do' $script:out 'declined (still to do; run <id> when ready): 0.20.0-01'
    Invoke-Mig "$work/p2" @('status')
    Has 'status reports it on a second line' $script:out 'declined_repo=1 declined_developer=0'
    Invoke-Mig "$work/p2" @('record', 'upgrade-04', 'declined')
    Invoke-Mig "$work/p2" @('run', 'upgrade-06')
    RcIs 'a step whose requires was declined does not run' 1
    Has '...and says so' $script:out 'upgrade-04 (declined)'
    Invoke-Mig "$work/p2" @('run', 'upgrade-04'); RcIs 'a declined step runs when the user is ready' 0
    Invoke-Mig "$work/p2" @('record', 'upgrade-04', 'done'); RcIs '...and records done' 0
    Invoke-Mig "$work/p2" @('run', 'upgrade-06'); RcIs '...which unblocks the step that requires it' 0

    Write-Host '== t_resume_in_new_session'
    New-Project "$work/p3" '0.19.0' '' "$work/rel20"
    tgit clone -q "$work/rel20" "$work/clone3"
    tgit -C "$work/clone3" -c advice.detachedHead=false checkout -q v0.20.0
    Invoke-Mig "$work/p3" @('plan', '-Source', "$work/clone3", '-Scope', 'repo')
    $script:stepLog = ''
    Invoke-Steps "$work/p3" "$work/p3-upgrade" '0.20.0' @('upgrade-01', 'upgrade-02')
    $state = Read-Text "$work/p3/.sumela/.upgrade/migrate.state"
    Has 'the state records where the upgrade started' $state 'from=0.19.0'
    Has '...and the branch the worktree is on' $state 'branch=sumela/upgrade-0.20.0'
    [IO.Directory]::Delete("$work/clone3", $true)
    Invoke-Mig "$work/p3" @('status')
    Has 'status is offline: a missing clone is not cloned' $script:out 'pending_repo=0 pending_developer=0'
    Invoke-Mig "$work/p3" @('plan', '-Scope', 'repo')
    RcIs 'a new session resumes from the state alone' 0
    Has '...cloning the recorded tag again' $script:out 'at v0.20.0 again'
    Same '...and lists what is left, in order' 'upgrade-03 0.20.0-01 upgrade-04 upgrade-05 upgrade-06' (Get-PendingIds)

    Write-Host '== t_worktree_gone_refuses_and_rollback_restores'
    $script:stepLog = ''
    Invoke-Steps "$work/p3" "$work/p3-upgrade" '0.20.0' @('upgrade-03', 'upgrade-04')
    Invoke-Mig "$work/p3" @('rollback', 'upgrade-04', '-ConfirmedByUser')
    RcIs 'a rollback whose line fails exits 1' 1
    if ([IO.File]::Exists("$work/p3-upgrade/.sumela/migrations-applied/upgrade-04@0.20.0")) { Ok '...and its ledger entry is restored' } else { Bad '...and its ledger entry is restored' }
    Invoke-Mig "$work/p3" @('rollback', 'upgrade-03', '--confirmed-by-user')
    RcIs 'a rollback whose line succeeds exits 0' 0
    if (-not [IO.File]::Exists("$work/p3-upgrade/.sumela/migrations-applied/upgrade-03@0.20.0")) { Ok '...its ledger entry is gone' } else { Bad '...its ledger entry is gone' }
    tgit -C "$work/p3" worktree remove --force "$work/p3-upgrade"
    Invoke-Mig "$work/p3" @('record', 'upgrade-05', 'not-applicable')
    RcIs 'once the recorded worktree is gone, repo steps refuse to record' 1
    Has '...and say why' $script:out 'no longer exists: repo steps neither run, record nor roll back without it'
    Invoke-Mig "$work/p3" @('rollback', 'upgrade-04', '-ConfirmedByUser')
    RcIs '...and to roll back' 1

    Write-Host '== t_rollback_removes_the_worktree_and_branch'
    New-Project "$work/p4" '0.19.0' '' "$work/rel20"
    Invoke-Mig "$work/p4" @('plan', '-Source', $rel20Src, '-Scope', 'repo')
    $script:stepLog = ''
    Invoke-Steps "$work/p4" "$work/p4-upgrade" '0.20.0' @('upgrade-01', 'upgrade-02')
    Write-Text "$work/p4-upgrade/untracked.txt" "stray`n"
    Invoke-Mig "$work/p4" @('rollback', 'upgrade-01', '-ConfirmedByUser')
    RcIs 'upgrade-01''s rollback runs' 0
    if (-not [IO.Directory]::Exists("$work/p4-upgrade")) { Ok '...the worktree is removed with everything in it' } else { Bad '...the worktree is removed' }
    Same '...the branch is deleted' '' (gitout -C "$work/p4" branch --list 'sumela/upgrade-0.20.0')
    Lacks '...and the state forgets the worktree' (Read-Text "$work/p4/.sumela/.upgrade/migrate.state") 'worktree='

    Write-Host '== t_complete_upgrade_retires_state'
    New-Project "$work/p5" '0.19.0' '' "$work/rel20"
    tgit clone -q "$work/rel20" "$work/clone5"
    tgit -C "$work/clone5" -c advice.detachedHead=false checkout -q v0.20.0
    Invoke-Mig "$work/p5" @('plan', '-Source', "$work/clone5", '-Scope', 'repo')
    $o5 = (Get-PendingIds).Split(' ')
    $script:stepLog = ''
    Invoke-Steps "$work/p5" "$work/p5-upgrade" '0.20.0' $o5
    Invoke-Mig "$work/p5" @('plan', '-Source', "$work/clone5", '-Scope', 'repo')
    Has 'with every step recorded and the merge still to come, plan says what is left' $script:out 'every repo step is recorded: merge the upgrade pull request, then update the main checkout'
    if ([IO.File]::Exists("$work/p5/.sumela/.upgrade/migrate.state")) { Ok '...and keeps the state: the rollbacks need it before the merge' } else { Bad '...and keeps the state: the rollbacks need it before the merge' }
    tgit -C "$work/p5" merge -q --no-ff -m 'Merge the upgrade' sumela/upgrade-0.20.0
    [IO.Directory]::Delete("$work/clone5", $true)
    Invoke-Mig "$work/p5" @('status')
    Same 'after the merge, status reports nothing pending, offline' 'pending_repo=0 pending_developer=0' $script:out
    Invoke-Mig "$work/p5" @('plan', '-Scope', 'repo')
    Has 'plan reports the upgrade complete from the main checkout''s VERSION' $script:out 'the upgrade to v0.20.0 is complete (the main checkout is at v0.20.0)'
    Lacks '...without cloning the release again' $script:out 'cloning'
    if (-not [IO.File]::Exists("$work/p5/.sumela/.upgrade/migrate.state")) { Ok '...and removes the state' } else { Bad '...and removes the state' }
    # Every step recorded, the pull request not merged: the user abandons it. The rollbacks still work.
    New-Project "$work/p5r" '0.19.0' '' "$work/rel20"
    Invoke-Mig "$work/p5r" @('plan', '-Source', $rel20Src, '-Scope', 'repo')
    $o5r = (Get-PendingIds).Split(' ')
    $script:stepLog = ''
    Invoke-Steps "$work/p5r" "$work/p5r-upgrade" '0.20.0' $o5r
    Invoke-Mig "$work/p5r" @('plan')
    $rlog = ''
    foreach ($id in @('upgrade-07', 'upgrade-03', 'upgrade-01')) { Invoke-Mig "$work/p5r" @('rollback', $id, '-ConfirmedByUser'); if ($script:rc -ne 0) { $rlog += " ${id}: $($script:rc) ($(Get-Tail $script:out));" } }
    Same 'after the last step and a plain plan, the rollbacks run before the merge' '' $rlog
    if (-not [IO.Directory]::Exists("$work/p5r-upgrade")) { Ok '...upgrade-01''s removes the worktree' } else { Bad '...upgrade-01''s removes the worktree' }

    Write-Host '== t_teammate_after_pull_sees_developer_steps'
    $tm = "$work/tm-notes"; Write-Generic $tm
    Write-Text "$tm/0.20.0.md" ((Get-StepBlock '0.20.0-01' 'developer' 'first-session' @('until: 0.20.2')) + (Get-StepBlock '0.20.0-02' 'developer' 'first-session' @('until: 0.20.1')) + (Get-StepBlock '0.20.0-03' 'repo' 'post-update'))
    Write-Text "$tm/0.20.1.md" (Get-StepBlock '0.20.1-01' 'developer' 'first-session')
    Write-Text "$tm/0.20.2.md" (Get-StepBlock '0.20.2-01' 'developer' 'first-session')
    New-Project "$work/tm" '0.20.1' $tm
    Invoke-Mig "$work/tm" @('plan', '-Scope', 'developer')
    RcIs 'plan -Scope developer needs no clone and no state' 0
    Same 'every skipped version''s developer steps are listed' '0.20.0-01 0.20.1-01' (Get-PendingIds)
    Invoke-Mig "$work/tm" @('run', '0.20.0-01'); RcIs 'a developer step runs from the installed notes' 0
    Invoke-Mig "$work/tm" @('record', '0.20.0-01', 'done'); RcIs '...and records done after its verify passes' 0
    Invoke-Mig "$work/tm" @('status', '-Scope', 'developer')
    Same 'status counts what is left' 'pending_developer=1' $script:out
    Invoke-Mig "$work/tm" @('show', '0.20.0-02')
    Has 'a developer step with until <= the installed version is moot' $script:out 'status: moot (until 0.20.1; this install is at v0.20.1)'
    Invoke-Mig "$work/tm" @('run', '0.20.0-02')
    RcIs 'run refuses a moot step' 1
    Has '...and says why' $script:out 'is moot'

    Write-Host '== t_presatisfied_developer_step_auto_recorded'
    $psn = "$work/ps-notes"
    Write-Text "$psn/0.20.0.md" @'
```sumela-step
id: 0.20.0-01
title: Record a dev key
scope: developer
when: first-session
consent: confirm
run: bash "{ROOT}/tools/step.sh" key
verify: git config --local --get sumela.testKey
expect: non-empty
agent: pick a key
```

```sumela-step
id: 0.20.0-02
title: A check that is not read-only by the allow-list
scope: developer
when: first-session
consent: confirm
run: bash "{ROOT}/tools/step.sh" other
verify: test -f app.txt
expect: exit0
```

```sumela-step
id: 0.20.0-03
title: PowerShell verify differs from the bash one
scope: developer
when: first-session
consent: explicit
run: bash "{ROOT}/tools/step.sh" y
verify: git config --local --get sumela.testKey
verify.ps1: New-Item -ItemType File -Path PS-PLAN-RAN-THIS | Out-Null; git config --local --get sumela.testKey
expect: non-empty
```
'@
    # A verify.ps1 whose curly quotes PowerShell reads as quotes: the lint would see one string.
    [IO.File]::AppendAllText("$psn/0.20.0.md", "`n${fence}sumela-step`nid: 0.20.0-04`ntitle: Curly quotes in verify.ps1`nscope: developer`nwhen: first-session`nconsent: explicit`nrun: bash `"{ROOT}/tools/step.sh`" z`nverify: git config --local --get sumela.testKey`nverify.ps1: pwsh -NoProfile -File tools/sync.ps1 -SourceDir `"a$lq -Sync ${lq}b`" -Check`nexpect: non-empty`n$fence`n", $utf8)
    New-Project "$work/ps" '0.20.0' $psn
    Write-Text "$work/ps/tools/sync.ps1" "param([string]`$SourceDir, [switch]`$Sync, [switch]`$Check)`nif (`$Sync) { [IO.File]::WriteAllText((Join-Path (Get-Location).ProviderPath 'PS-SYNC-RAN'), 'x') }`n'abc'`n"
    tgit -C "$work/ps" add -A
    tgit -C "$work/ps" commit -qm sync
    tgit -C "$work/ps" config --local sumela.testKey abc
    Invoke-Mig "$work/ps" @('plan', '-Scope', 'developer')
    Has 'a developer step whose read-only verify passes is recorded done (pre-satisfied)' $script:out 'recorded 0.20.0-01 done (pre-satisfied)'
    Same '...a verify outside the allow-list is never run by plan, nor a writing verify.ps1' '0.20.0-02 0.20.0-03 0.20.0-04' (Get-PendingIds)
    if (-not [IO.File]::Exists("$work/ps/PS-PLAN-RAN-THIS")) { Ok '...the gate checks the line that runs (verify.ps1)' } else { Bad '...the gate checks the line that runs (verify.ps1)' }
    if (-not [IO.File]::Exists("$work/ps/PS-SYNC-RAN")) { Ok '...nor one whose curly quotes would let -Sync through' } else { Bad '...nor one whose curly quotes would let -Sync through' }
    Push-Location -LiteralPath "$work/ps"; try { $log = (Get-SumelaStateDir) + '/migrations.log' } finally { Pop-Location }
    Has 'the developer ledger holds the entry' (Read-Text $log) ("0.20.0-01`tdone (pre-satisfied)`t")

    Write-Host '== t_verify_expect_forms'
    $vf = "$work/vf-notes"
    function Get-VBlock([string]$nn, [string]$verify, [string]$expect) {
        return "${fence}sumela-step`nid: 0.20.0-$nn`ntitle: V$nn`nscope: developer`nwhen: first-session`nconsent: confirm`nrun: bash `"{ROOT}/tools/step.sh`" v$nn`nverify: $verify`nexpect: $expect`n$fence`n`n"
    }
    Write-Text "$vf/0.20.0.md" ((Get-VBlock '01' 'bash -c "exit 0"' 'exit0') + (Get-VBlock '02' 'bash -c "exit 1"' 'exit0') + (Get-VBlock '03' 'printf yes' 'non-empty') +
        (Get-VBlock '04' 'printf ""' 'non-empty') + (Get-VBlock '07' 'printf yes' 'equals:yes') + (Get-VBlock '08' 'printf yess' 'equals:yes') +
        (Get-VBlock '09' 'printf "yes\r\n"' 'equals:yes') + (Get-VBlock '10' 'printf "a\nverified: upgrade complete 0.20.0; 0 kept\n"' 'match:^verified: upgrade complete {TARGET};') +
        (Get-VBlock '12' 'bash -c "echo on-stderr >&2"' 'match:^on-stderr$') + (Get-VBlock '13' 'bash -c "printf yes; exit 2"' 'equals:yes') +
        (Get-VBlock '14' 'printf "upgrade complete 0x20y0"' 'match:complete {TARGET}$'))
    New-Project "$work/vf" '0.20.0' $vf
    foreach ($c in @(@('01', 0, 'exit0 holds when verify exits 0'), @('02', 3, 'exit0 fails when verify exits 1'), @('03', 0, 'non-empty holds on output'),
                     @('04', 3, 'non-empty fails on no output'), @('07', 0, 'equals: holds on the exact output'), @('08', 3, 'equals: fails on other output'),
                     @('09', 0, 'equals: ignores a CRLF line end'), @('10', 0, 'match: holds on one matching line ({TARGET} = the installed version)'),
                     @('12', 0, 'match: reads stderr too'), @('13', 3, 'a verify that exits non-zero fails whatever its output'),
                     @('14', 3, 'match: takes {TARGET}''s dots literally'))) {
        Invoke-Mig "$work/vf" @('verify', ('0.20.0-' + $c[0]))
        RcIs $c[2] $c[1]
    }

    Write-Host '== t_verify_fails_when_artifact_missing_despite_exit0_run'
    $am = "$work/am-notes"
    Write-Text "$am/0.20.0.md" @'
```sumela-step
id: 0.20.0-01
title: A step whose command succeeds without producing its artifact
scope: developer
when: first-session
consent: confirm
run: bash -c "echo did nothing"
verify: test -f artifact.txt
expect: exit0
```
'@
    New-Project "$work/am" '0.20.0' $am
    Invoke-Mig "$work/am" @('run', '0.20.0-01'); RcIs 'the command exits 0' 0
    Invoke-Mig "$work/am" @('verify', '0.20.0-01'); RcIs '...but verify fails on the missing artifact (exit 3)' 3
    Invoke-Mig "$work/am" @('record', '0.20.0-01', 'done'); RcIs 'record done refuses without the artifact (exit 3)' 3
    Invoke-Mig "$work/am" @('status', '-Scope', 'developer'); Same '...so the step stays pending' 'pending_developer=1' $script:out

    Write-Host '== t_repo_ledger_recorded_in_provenance'
    $l = Read-Text "$work/p2-upgrade/.sumela/migrations-applied/upgrade-02@0.20.0"
    Same 'a generic step''s ledger holds status, at and version, LF only' 'status: done|at: |version: 0.20.0|' ([regex]::Replace($l, '(?m)^at: .*$', 'at: ').Replace("`n", '|'))
    if ($l -cmatch '(?m)^at: [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$') { Ok '...at is a UTC timestamp' } else { Bad "...at is a UTC timestamp ($l)" }
    $files = [string]::Join("`n", @(Get-SumelaRecordFiles -Record "$work/p2-upgrade/.sumela/.last-update.json"))
    Has 'every repo ledger entry is in the provenance record''s files' $files '.sumela/migrations-applied/upgrade-01@0.20.0'
    # Twin parity: the bash runner, on an identical project, plans the same steps and writes the same state.
    New-Project "$work/twin-ps" '0.19.0' '' "$work/rel20"; New-Project "$work/twin-sh" '0.19.0' '' "$work/rel20"
    Invoke-Mig "$work/twin-ps" @('plan', '-Source', $rel20Src, '-Scope', 'repo'); $planPs = Get-PendingIds
    Invoke-Mig "$work/twin-sh" @('plan', '--source', $rel20Src, '--scope', 'repo') -Runner $bashRunner; $planSh = Get-PendingIds
    Same 'the twins plan the same steps in the same order' $planSh $planPs
    $stPs = Read-Text "$work/twin-ps/.sumela/.upgrade/migrate.state"
    $stSh = Read-Text "$work/twin-sh/.sumela/.upgrade/migrate.state"
    Same 'the twins write the same state, byte for byte' $stSh $stPs
    $bytes = [IO.File]::ReadAllBytes("$work/twin-ps/.sumela/.upgrade/migrate.state")
    if (($bytes.Length -ge 3) -and ($bytes[0] -eq 0xEF) -and ($bytes[1] -eq 0xBB)) { Bad '...without a BOM' } else { Ok '...without a BOM' }

    Write-Host '== t_developer_ledger_mode_0600'
    Push-Location -LiteralPath "$work/tm"; try { $log = (Get-SumelaStateDir) + '/migrations.log' } finally { Pop-Location }
    if ($onWindows) { Skip 'POSIX modes (Windows: %LOCALAPPDATA% is per-user)' }
    else {
        Same 'the developer ledger is 0600' '600' (Get-Mode $log)
        Same '...inside a 0700 state directory' '700' (Get-Mode ([IO.Path]::GetDirectoryName($log)))
    }
    if ((Read-Text $log) -cmatch '(?m)^0\.20\.0-01\tdone\t[0-9T:Z-]+$') { Ok 'one <id><TAB><status><TAB><UTC> line per entry, as the bash runner writes it' } else { Bad "one <id><TAB><status><TAB><UTC> line per entry ($(Read-Text $log))" }

    Write-Host '== t_untagged_source_refused'
    New-Release "$work/untagged" '0.20.0' '-' $gen
    New-Project "$work/u" '0.19.0' '' "$work/untagged"
    Invoke-Mig "$work/u" @('plan', '-Source', (Get-Src "$work/untagged"), '-Scope', 'repo')
    RcIs 'a clone whose HEAD has no release tag is refused' 1
    Has '...naming the tag it needs' $script:out 'not at an annotated release tag v0.20.0'
    tgit -C "$work/untagged" tag v0.20.0
    Invoke-Mig "$work/u" @('plan', '-Source', (Get-Src "$work/untagged"), '-Scope', 'repo')
    RcIs 'a lightweight tag is refused' 1
    tgit -C "$work/untagged" tag -d v0.20.0
    $usrc = Get-Src "$work/untagged"
    tgit -C $usrc tag -a -m forged v0.20.0
    Invoke-Mig "$work/u" @('plan', '-Source', $usrc, '-Scope', 'repo')
    RcIs 'a tag made in the clone alone is refused: the upstream does not have it' 1
    Has '...git ls-remote says so' $script:out 'says v0.20.0 is absent'
    tgit -C $usrc tag -d v0.20.0
    Invoke-Mig "$work/u" @('plan', '-Source', $usrc, '-Scope', 'repo', '-AllowUntagged')
    RcIs '-AllowUntagged alone is refused: it is for maintainer tests only' 1
    Has '...which take SUMELA_MIGRATE_ALLOW_UNTAGGED=1 as well' $script:out 'SUMELA_MIGRATE_ALLOW_UNTAGGED=1'
    Invoke-Mig "$work/u" @('plan', '-Source', $usrc, '-Scope', 'repo', '-AllowUntagged') @{ SUMELA_MIGRATE_ALLOW_UNTAGGED = '1' }
    RcIs '-AllowUntagged with SUMELA_MIGRATE_ALLOW_UNTAGGED=1 (maintainer tests) proceeds' 0
    New-Project "$work/u2" '0.19.0'
    Invoke-Mig "$work/u2" @('plan', '-Source', $rel20Src, '-Scope', 'repo')
    RcIs 'a clone whose origin is not the project''s upstream is refused' 1
    Has '...naming the default upstream' $script:out 'else https://github.com/tolgakisaogullari/SumelaOS.git'
    Invoke-Mig "$work/u2" @('plan', '-Source', $rel20Src, '-Scope', 'repo', '-ConfirmedByUser')
    RcIs '-ConfirmedByUser does not trust another origin' 1
    Has '...the refusal names --trust-origin' $script:out 'pass --trust-origin <url> once the user confirms that source'
    Invoke-Mig "$work/u2" @('plan', '-Source', $rel20Src, '-Scope', 'repo', '-TrustOrigin', "$work/elsewhere")
    RcIs '-TrustOrigin with a URL that is not the clone''s origin is refused' 1
    Invoke-Mig "$work/u2" @('plan', '-Source', $rel20Src, '-Scope', 'repo', '--trust-origin', "$work/rel20")
    RcIs '--trust-origin <the clone''s origin> proceeds, once the user confirmed it' 0
    Has '...which the output records' $script:out 'which the user confirmed'
    # The upgrade branch tracks nothing but its own remote branch: else a push could land on the base.
    tgit -C "$work/u2" worktree add -q -b sumela/upgrade-0.20.0 "$work/u2-wt" main
    tgit -C "$work/u2" branch -q --set-upstream-to=main sumela/upgrade-0.20.0
    Invoke-Mig "$work/u2" @('set', "worktree=$work/u2-wt")
    RcIs 'set refuses a worktree whose branch tracks another branch (the base)' 1
    Has '...naming it and the fix' $script:out 'tracks refs/heads/main: a push could land there'
    tgit -C "$work/u2" branch -q --unset-upstream sumela/upgrade-0.20.0
    Invoke-Mig "$work/u2" @('set', "worktree=$work/u2-wt")
    RcIs '...and accepts it once it tracks nothing' 0
    Invoke-Mig "$work/u2" @('set', "prefix=a`tb/")
    RcIs 'set refuses a value with a control character' 1
    New-Project "$work/u3" '0.19.0' '' "$work/rel20"
    [IO.File]::AppendAllText("$rel20Src/tools/step.sh", "echo TAMPERED`n", $utf8)
    Invoke-Mig "$work/u3" @('plan', '-Source', $rel20Src, '-Scope', 'repo')
    RcIs 'a clone with a modified tool is refused' 1
    Has '...its local changes named' $script:out 'has local changes'
    tgit -C $rel20Src checkout -q -- tools/step.sh
    [IO.File]::AppendAllText("$rel20Src/scripts/sumela-migrations/upgrade.md", "`n# local edit`n", $utf8)
    Invoke-Mig "$work/u3" @('plan', '-Source', $rel20Src, '-Scope', 'repo')
    RcIs 'a clone whose notes differ from the tag is refused' 1
    tgit -C $rel20Src checkout -q -- scripts/sumela-migrations/upgrade.md
    tgit -C $rel20Src update-index --assume-unchanged scripts/sumela-migrations/upgrade.md
    [IO.File]::AppendAllText("$rel20Src/scripts/sumela-migrations/upgrade.md", "`n# hidden edit`n", $utf8)
    Invoke-Mig "$work/u3" @('plan', '-Source', $rel20Src, '-Scope', 'repo')
    RcIs 'a clone that hides an edit (assume-unchanged) is refused' 1
    Has '...and says how' $script:out 'hides local changes'
    tgit -C $rel20Src update-index --no-assume-unchanged scripts/sumela-migrations/upgrade.md
    tgit -C $rel20Src checkout -q -- scripts/sumela-migrations/upgrade.md
    $canary = 's3cr3tCANARY'
    tgit -C $rel20Src config remote.origin.url "https://alice:$canary@example.invalid/x/SumelaOS.git"
    Invoke-Mig "$work/u3" @('plan', '-Source', $rel20Src, '-Scope', 'repo')
    RcIs 'a credentialed origin that is not the upstream is refused' 1
    Has '...the URL is shown without the credential' $script:out 'comes from https://example.invalid/x/SumelaOS.git, not from'
    $canaryOut = $script:out
    Invoke-Mig "$work/u3" @('plan', '-Source', $rel20Src, '-Scope', 'repo', '-TrustOrigin', "https://alice:$canary@example.invalid/x/SumelaOS.git") @{ GIT_ALLOW_PROTOCOL = 'file' }
    RcIs 'a confirmed origin that cannot be asked for the tag is refused (the tag check needs it)' 1
    Has '...naming it without the credential' $script:out 'cannot ask https://example.invalid/x/SumelaOS.git for v0.20.0'
    $canaryOut += $script:out + (Read-Text "$work/u3/.sumela/.upgrade/migrate.state")
    Lacks 'the canary credential appears in no output, nor in any state file' $canaryOut $canary
    tgit -C $rel20Src config remote.origin.url "$work/rel20"
    # The clone's own git configuration is not trusted: no fsmonitor hook runs, and no
    # url.<x>.insteadOf can make the tag check ask another repository.
    tgit -C $rel20Src config core.fsmonitor "touch `"$work/PS-FSMONITOR-RAN`"; false"
    Invoke-Mig "$work/u3" @('plan', '-Source', $rel20Src, '-Scope', 'repo')
    RcIs 'a clean clone with an fsmonitor hook in its config is checked' 0
    if (-not [IO.File]::Exists("$work/PS-FSMONITOR-RAN")) { Ok '...without running that hook' } else { Bad '...without running that hook' }
    tgit -C $rel20Src config --unset core.fsmonitor
    tgit clone -q "$work/rel20" "$work/psfork"
    [IO.File]::AppendAllText("$work/psfork/tools/step.sh", "echo FORK`n", $utf8)
    tgit -C "$work/psfork" commit -qam fork
    tgit -C "$work/psfork" tag -a -f -m fork v0.20.0
    tgit clone -q "$work/psfork" "$work/psfork.clone"
    tgit -C "$work/psfork.clone" -c advice.detachedHead=false checkout -q v0.20.0
    tgit -C "$work/psfork.clone" remote set-url origin "$work/rel20"
    tgit -C "$work/psfork.clone" config "url.$work/psfork.insteadOf" "$work/rel20"
    [IO.File]::Delete("$work/u3/.sumela/.upgrade/migrate.state")
    Invoke-Mig "$work/u3" @('plan', '-Source', "$work/psfork.clone", '-Scope', 'repo')
    RcIs 'a fork''s commit under the upstream''s URL is refused, insteadOf in the clone or not' 1
    Has '...the upstream itself says the tag is elsewhere' $script:out "$work/rel20 says v0.20.0 is $(gitout -C "$work/rel20" rev-parse 'v0.20.0^{commit}')"
    if (-not $onWindows) {
        $nl = "$work/psclone`nworktree=$work/evil"
        tgit clone -q "$work/rel20" $nl
        tgit -C $nl -c advice.detachedHead=false checkout -q v0.20.0
        Invoke-Mig "$work/u3" @('plan', '-Source', $nl, '-Scope', 'repo')
        RcIs 'a clone path with a newline is refused' 1
        Has '...saying why' $script:out 'holds a control character'
        Lacks '...and nothing reaches the state' (Read-Text "$work/u3/.sumela/.upgrade/migrate.state") "worktree=$work/evil"
    }
    Invoke-Mig $rel20Src @('plan', '-Source', $rel20Src, '-Scope', 'repo')
    RcIs 'the runner refuses to run inside the release clone itself' 1
    Has '...saying so' $script:out 'the release clone is this repository'
    Invoke-Mig "$work/u3" @('status', '-Source', $rel20Src)
    RcIs 'only plan takes -Source' 1

    Write-Host '== t_rc_tag_accepted'
    New-Release "$work/rc" '0.20.0' 'v0.20.0-rc.1' $gen
    New-Project "$work/rcp" '0.19.0' '' "$work/rc"
    Invoke-Mig "$work/rcp" @('plan', '-Source', (Get-Src "$work/rc"), '-Scope', 'repo')
    RcIs 'an annotated v<target>-rc.<n> tag is accepted' 0
    Has '...and recorded' (Read-Text "$work/rcp/.sumela/.upgrade/migrate.state") "tag=v0.20.0-rc.1`n"

    Write-Host '== t_modified_installed_notes_refused'
    New-Project "$work/mod" '0.20.1' $tm
    Invoke-Mig "$work/mod" @('plan', '-Scope', 'developer'); RcIs 'unmodified installed notes are read' 0
    [IO.File]::AppendAllText("$work/mod/scripts/sumela-migrations/0.20.0.md", "`n# local edit`n", $utf8)
    Invoke-Mig "$work/mod" @('plan', '-Scope', 'developer')
    RcIs 'installed notes that differ from HEAD are refused' 1
    Has '...naming the fix' $script:out 'differ from HEAD'
    # A notes file committed as a symlink would point outside HEAD: it is refused.
    New-Project "$work/sym" '0.20.1' $tm
    Write-Text "$work/outside.md" (Get-StepBlock '0.19.9-01' 'developer' 'first-session')
    Write-Text "$work/link-target.txt" "$work/outside.md"
    $linkBlob = gitout -C "$work/sym" hash-object -w "$work/link-target.txt"
    tgit -C "$work/sym" update-index --add --cacheinfo "120000,$linkBlob,scripts/sumela-migrations/0.19.9.md"
    tgit -C "$work/sym" commit -qm 'notes as a symlink'
    tgit -C "$work/sym" checkout -q -- scripts/sumela-migrations/0.19.9.md
    Invoke-Mig "$work/sym" @('plan', '-Scope', 'developer')
    RcIs 'a notes file committed as a symlink is refused' 1
    Has '...saying why' $script:out 'is not a regular file (mode 120000'

    Write-Host '== t_explicit_consent_requires_flag'
    $ex = "$work/ex-notes"
    Write-Text "$ex/0.20.0.md" @'
```sumela-step
id: 0.20.0-01
title: An invasive step
scope: developer
when: first-session
consent: explicit
run: bash "{ROOT}/tools/step.sh" invasive
verify: bash "{ROOT}/tools/check.sh" invasive
expect: equals:ok
rollback: bash -c "rm -f done-invasive"
```

```sumela-step
id: 0.20.0-02
title: Loosen a control (agent-performed)
scope: developer
when: first-session
consent: explicit
run: -
verify: git config --local --get sumela.loose
expect: equals:yes
agent: run git config --local sumela.loose yes
```
'@
    New-Project "$work/ex" '0.20.0' $ex
    Invoke-Mig "$work/ex" @('run', '0.20.0-02')
    RcIs 'an explicit run: - step refuses without -ConfirmedByUser too (exit 2)' 2
    Lacks '...and does not hand out its agent: line' $script:out 'agent: run git config'
    Invoke-Mig "$work/ex" @('run', '0.20.0-02', '-ConfirmedByUser')
    RcIs 'with -ConfirmedByUser it prints the agent: line' 0
    Has '...the instruction itself' $script:out 'agent: run git config --local sumela.loose yes'
    Invoke-Mig "$work/ex" @('run', '0.20.0-01')
    RcIs 'an explicit step refuses without -ConfirmedByUser (exit 2)' 2
    if (-not [IO.File]::Exists("$work/ex/done-invasive")) { Ok '...and runs nothing' } else { Bad '...and runs nothing' }
    Invoke-Mig "$work/ex" @('run', '0.20.0-01', '-ConfirmedByUser')
    RcIs 'with -ConfirmedByUser it runs' 0
    Invoke-Mig "$work/ex" @('record', '0.20.0-01', 'done'); RcIs '...and records' 0
    Invoke-Mig "$work/ex" @('rollback', '0.20.0-01')
    RcIs 'rollback needs the confirmation too (exit 2)' 2
    Invoke-Mig "$work/ex" @('rollback', '0.20.0-01', '--confirmed-by-user')
    RcIs 'rollback --confirmed-by-user runs the rollback line' 0
    Invoke-Mig "$work/ex" @('status', '-Scope', 'developer')
    Same '...and the step is pending again (beside the agent-performed one)' 'pending_developer=2' $script:out

    Write-Host '== t_until_makes_step_moot_and_from_is_exclusive'
    Invoke-Mig "$work/p2" @('show', '0.20.0-01')
    $ut = "$work/until-notes"; Write-Generic $ut
    Write-Text "$ut/0.20.0.md" ((Get-StepBlock '0.20.0-01' 'repo' 'post-update' @('until: 0.20.1')) + (Get-StepBlock '0.20.0-02' 'repo' 'post-update' @('until: 0.20.2')))
    Write-Text "$ut/0.20.1.md" (Get-StepBlock '0.20.1-01' 'repo' 'post-update')
    New-Release "$work/until-rel" '0.20.1' 'v0.20.1' $ut
    New-Project "$work/up" '0.19.0' '' "$work/until-rel"
    Invoke-Mig "$work/up" @('plan', '-Source', (Get-Src "$work/until-rel"), '-Scope', 'repo')
    Lacks 'a jump past until drops the step' $script:out '0.20.0-01 '
    Has '...a later until keeps it' $script:out '0.20.0-02 '
    New-Project "$work/up2" '0.20.0' '' "$work/until-rel"
    Invoke-Mig "$work/up2" @('plan', '-Source', (Get-Src "$work/until-rel"), '-Scope', 'repo')
    Lacks 'a version step at the version the upgrade starts from is not selected (from is exclusive)' $script:out '0.20.0-02 '
    Has '...the next version''s is' $script:out '0.20.1-01 '

    Write-Host '== t_agent_step_needs_the_worktree'
    $ag = "$work/agent-notes"; Write-Generic $ag
    Write-Text "$ag/0.20.0.md" (Get-Block ("id: 0.20.0-01`ntitle: An agent step without requires`nscope: repo`nwhen: post-update`nconsent: confirm`nrun: -`n" +
        "verify: bash `"{SRC}/tools/check.sh`" agent`nexpect: equals:ok`nagent: edit the settings file in {ROOT}"))
    New-Release "$work/agent-rel" '0.20.0' 'v0.20.0' $ag
    New-Project "$work/ag" '0.19.0' '' "$work/agent-rel"
    Invoke-Mig "$work/ag" @('plan', '-Source', (Get-Src "$work/agent-rel"), '-Scope', 'repo')
    RcIs 'plan lists the agent step' 0
    Invoke-Mig "$work/ag" @('run', '0.20.0-01')
    RcIs 'a run: - repo step other than upgrade-01 is refused in the main checkout' 1
    Has '...it needs the upgrade worktree' $script:out 'runs in the upgrade worktree, which upgrade-01 creates'
    Lacks '...and its agent: line, which names {ROOT}, is not printed' $script:out 'agent: edit the settings file'
    Invoke-Mig "$work/ag" @('show', '0.20.0-01')
    Has 'show says what works in the main checkout' $script:out '(no upgrade worktree yet: only upgrade-01 and verify work here)'
    Invoke-Mig "$work/ag" @('run', 'upgrade-01')
    RcIs 'upgrade-01''s agent: line is printed there' 0

    Write-Host '== t_subst_quotes_paths_with_spaces_and_quotes'
    $sq = "$work/sq-notes"; Write-Generic $sq
    Write-Text "$sq/0.20.0.md" @'
```sumela-step
id: 0.20.0-01
title: Paths reach the step intact
scope: repo
when: post-update
consent: confirm
run: bash "{SRC}/tools/args.sh" "{ROOT}" "{SRC}/x y" v{TARGET}
verify: bash "{SRC}/tools/args.sh" "{ROOT}"
expect: match:^arg=
agent: the clone is {SRC} and the checkout {ROOT}
```
'@
    $odd = "$work/odd dir 'a' `$x ``b"
    [void][IO.Directory]::CreateDirectory($odd)
    New-Release "$odd/rel" '0.20.0' 'v0.20.0' $sq
    New-Project "$odd/proj" '0.19.0' '' "$odd/rel"
    $oddSrc = Get-Src "$odd/rel"
    Invoke-Mig "$odd/proj" @('plan', '-Source', $oddSrc, '-Scope', 'repo'); RcIs 'plan accepts a clone path with spaces and quotes' 0
    $script:stepLog = ''
    Invoke-Steps "$odd/proj" "$odd/proj upgrade" '0.20.0' @('upgrade-01')
    Same 'the worktree path is recorded' '' $script:stepLog
    Invoke-Mig "$odd/proj" @('run', '0.20.0-01')
    RcIs 'the step runs' 0
    Has '{ROOT} arrives as one argument, byte for byte' $script:out "arg=$odd/proj upgrade"
    Has '{SRC} inside a longer quoted word too' $script:out "arg=$oddSrc/x y"
    Has '{TARGET} is substituted literally' $script:out 'arg=v0.20.0'

    Write-Host '== t_restricted_policy_routes_through_git_bash'
    $rp = "$work/rp-notes"
    Write-Text "$rp/0.20.0.md" @'
```sumela-step
id: 0.20.0-01
title: A step with both forms
scope: developer
when: first-session
consent: confirm
run: bash "{ROOT}/tools/step.sh" via-bash
run.ps1: & "{ROOT}/tools/step.ps1" via-ps
verify: bash "{ROOT}/tools/check.sh" via-bash
verify.ps1: & "{ROOT}/tools/check.ps1" via-ps
expect: equals:ok
```
'@
    New-Project "$work/rp" '0.20.0' $rp
    New-Project "$work/rp2" '0.20.0' $rp
    if ($onWindows) {
        # The Windows client default: a -File script does not run at all. README step 0 then
        # routes every command through Git Bash.
        Invoke-Mig "$work/rp" @('status') @{ PSExecutionPolicyPreference = 'Restricted' }
        if ($script:rc -ne 0) { Ok 'under Restricted, powershell -File cannot start the PowerShell runner' } else { Skip 'this host runs -File scripts under Restricted (a policy set by Group Policy wins)' }
        Invoke-Mig "$work/rp" @('run', '0.20.0-01') @{ PSExecutionPolicyPreference = 'Restricted' } -Runner $bashRunner
        RcIs 'README step 0: the bash runner through Git Bash (from git --exec-path) runs the step' 0
        Invoke-Mig "$work/rp" @('record', '0.20.0-01', 'done') @{ PSExecutionPolicyPreference = 'Restricted' } -Runner $bashRunner
        RcIs '...verifies and records it' 0
        Has '...with the step''s bash line' (Read-Text "$work/rp/order.log") 'via-bash'
        if ($script:bash.EndsWith('bash.exe', $ord) -and ($script:bash.IndexOf('System32', [StringComparison]::OrdinalIgnoreCase) -lt 0)) { Ok "Git Bash is found from git --exec-path ($($script:bash)), never WSL's bash" } else { Bad "Git Bash is found from git --exec-path (got $($script:bash))" }
    } else {
        # pwsh outside Windows always runs scripts; the runner still reads the policy a step's
        # process would inherit and routes through bash.
        Invoke-Mig "$work/rp" @('run', '0.20.0-01') @{ PSExecutionPolicyPreference = 'Restricted' }
        RcIs 'under PSExecutionPolicyPreference=Restricted the PowerShell runner runs the step' 0
        Has '...with its bash line, through bash' $script:out '$ bash "${SUMELA_MIGRATE_ROOT}/tools/step.sh" via-bash'
        Invoke-Mig "$work/rp" @('record', '0.20.0-01', 'done') @{ PSExecutionPolicyPreference = 'Restricted' }
        RcIs '...verifies it through bash too' 0
        Has '...the bash line wrote the artifact' (Read-Text "$work/rp/order.log") 'via-bash'
    }
    Invoke-Mig "$work/rp2" @('run', '0.20.0-01')
    RcIs 'with scripts allowed, the step runs its run.ps1' 0
    Has '...the PowerShell line' $script:out '$ & "${env:SUMELA_MIGRATE_ROOT}/tools/step.ps1" via-ps'
    Invoke-Mig "$work/rp2" @('record', '0.20.0-01', 'done'); RcIs '...and verifies with verify.ps1' 0
    Has '...which wrote the artifact' (Read-Text "$work/rp2/order.log") 'via-ps'
} finally {
    foreach ($n in $savedEnv.Keys) { Set-EnvVar $n $savedEnv[$n] }
    try { [IO.Directory]::Delete($work, $true) } catch { }
}

Write-Host ''
Write-Host "Result: $($script:pass) passed, $($script:fail) failed"
if ($script:fail -gt 0) { exit 1 }
exit 0
