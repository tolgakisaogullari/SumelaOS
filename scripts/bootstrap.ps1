# OpenSkills Bootstrap - Windows/PowerShell
$ErrorActionPreference = "Stop"
$REPO_URL = "https://github.com/tolgakisaogullari/openskills.git"
$TEMP_DIR = Join-Path $env:TEMP "openskills-bootstrap-$(Get-Random)"
Write-Host "Cloning openskills..." -ForegroundColor Cyan
git clone --depth 1 $REPO_URL $TEMP_DIR 2>$null
Write-Host "Copying files..." -ForegroundColor Cyan
Copy-Item -Path "$TEMP_DIR\.openskills" -Destination "." -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item -Path "$TEMP_DIR\scripts" -Destination "." -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item -Path "$TEMP_DIR\AGENTS.md.template" -Destination "." -Force -ErrorAction SilentlyContinue
Copy-Item -Path "$TEMP_DIR\CLAUDE.md.template" -Destination "." -Force -ErrorAction SilentlyContinue
Remove-Item -Path $TEMP_DIR -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "Done! Run /initOpenSkills in your AI assistant." -ForegroundColor Green