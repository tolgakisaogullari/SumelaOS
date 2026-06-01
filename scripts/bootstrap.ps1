# SumelaOS Bootstrap - Windows/PowerShell
$ErrorActionPreference = "Stop"
$REPO_URL = "https://github.com/tolgakisaogullari/SumelaOS.git"
$TEMP_DIR = Join-Path $env:TEMP "SumelaOS-bootstrap-$(Get-Random)"
Write-Host "Cloning SumelaOS..." -ForegroundColor Cyan
git clone --depth 1 $REPO_URL $TEMP_DIR 2>$null
Write-Host "Copying files..." -ForegroundColor Cyan
Copy-Item -Path "$TEMP_DIR\.sumela" -Destination "." -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item -Path "$TEMP_DIR\scripts" -Destination "." -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item -Path "$TEMP_DIR\AGENTS.md.template" -Destination "." -Force -ErrorAction SilentlyContinue
Copy-Item -Path "$TEMP_DIR\CLAUDE.md.template" -Destination "." -Force -ErrorAction SilentlyContinue
Remove-Item -Path $TEMP_DIR -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "Done! Run /initSumela in your AI assistant." -ForegroundColor Green