# SumelaOS Bootstrap - Windows/PowerShell
# Brings a fresh project to parity with bootstrap.sh: clones the framework, copies
# the essential payload (.sumela + scripts) and every IDE template, then prints
# next steps. Essential copies fail loudly; optional IDE files are best-effort.
$ErrorActionPreference = "Stop"
$REPO_URL = "https://github.com/tolgakisaogullari/SumelaOS.git"
$TEMP_DIR = Join-Path $env:TEMP "SumelaOS-bootstrap-$(Get-Random)"

try {
    Write-Host "Cloning SumelaOS..." -ForegroundColor Cyan
    git clone --depth 1 $REPO_URL $TEMP_DIR
    if ($LASTEXITCODE -ne 0) { throw "Failed to clone $REPO_URL - check your network and that git is installed." }

    Write-Host "Copying files to current project..." -ForegroundColor Cyan
    # Essential payload — stop if these don't land (a half-install is worse than none).
    Copy-Item -Path "$TEMP_DIR\.sumela"  -Destination "." -Recurse -Force
    Copy-Item -Path "$TEMP_DIR\scripts"  -Destination "." -Recurse -Force
    # Optional template / IDE pointer files — best-effort.
    foreach ($item in @("AGENTS.md.template", "CLAUDE.md.template", ".clinerules.template",
                        ".cursor", ".kilocode", ".trae", ".opencode")) {
        Copy-Item -Path "$TEMP_DIR\$item" -Destination "." -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Create empty-directory placeholders (parity with bootstrap.sh).
    foreach ($d in @("docs/second-brain/template/raw_sources",
                     "docs/second-brain/template/artifacts/plans",
                     "docs/second-brain/template/artifacts/specs")) {
        New-Item -ItemType Directory -Force -Path $d | Out-Null
        New-Item -ItemType File -Force -Path (Join-Path $d ".gitkeep") | Out-Null
    }
}
finally {
    if (Test-Path $TEMP_DIR) { Remove-Item -Path $TEMP_DIR -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ""
Write-Host "SumelaOS installed! Next steps:" -ForegroundColor Green
Write-Host ""
Write-Host "  1. In your AI coding assistant, run:  /initSumela"
Write-Host "  2. Or run setup manually:             pwsh scripts/setup.ps1"
Write-Host ""
