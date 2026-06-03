#!/bin/bash
# SumelaOS Bootstrap — one-liner setup for existing projects
# Usage: curl -sSL https://raw.githubusercontent.com/tolgakisaogullari/SumelaOS/master/scripts/bootstrap.sh | bash

set -euo pipefail

REPO_URL="https://github.com/tolgakisaogullari/SumelaOS.git"
TEMP_DIR="$(mktemp -d)"
# Always clean up the clone, even on early failure.
trap 'rm -rf "$TEMP_DIR"' EXIT

echo "📦 Cloning SumelaOS..."
if ! git clone --depth 1 "$REPO_URL" "$TEMP_DIR"; then
  echo "❌ Failed to clone $REPO_URL — check your network and that git is installed." >&2
  exit 1
fi

echo "📂 Copying files to current project..."
# Essential payload — fail loudly if these don't land (a half-install is worse than none).
cp -r "$TEMP_DIR/.sumela" . || { echo "❌ Failed to copy .sumela" >&2; exit 1; }
cp -r "$TEMP_DIR/scripts" . || { echo "❌ Failed to copy scripts" >&2; exit 1; }
# Optional template/IDE files — best-effort (a missing one just means that IDE isn't wired).
cp "$TEMP_DIR/AGENTS.md.template" .   2>/dev/null || true
cp "$TEMP_DIR/CLAUDE.md.template" .   2>/dev/null || true
cp "$TEMP_DIR/.clinerules.template" . 2>/dev/null || true
cp -r "$TEMP_DIR/.cursor" .   2>/dev/null || true
cp -r "$TEMP_DIR/.kilocode" . 2>/dev/null || true
cp -r "$TEMP_DIR/.trae" .     2>/dev/null || true
cp -r "$TEMP_DIR/.opencode" . 2>/dev/null || true
# Second-brain template (wiki scaffolding) — /initSumela materializes the live wiki from it.
cp -r "$TEMP_DIR/docs" .      2>/dev/null || true

# Create .gitkeep files for empty directories
mkdir -p docs/second-brain/template/raw_sources
mkdir -p docs/second-brain/template/artifacts/plans
mkdir -p docs/second-brain/template/artifacts/specs
touch docs/second-brain/template/raw_sources/.gitkeep
touch docs/second-brain/template/artifacts/plans/.gitkeep
touch docs/second-brain/template/artifacts/specs/.gitkeep

echo "🧹 Cleaning up temp files..."

echo ""
echo "✅ SumelaOS installed! Next steps:"
echo ""
echo "  1. In your AI coding assistant, run:"
echo "     /initSumela"
echo ""
echo "  2. The agent will auto-detect your stack and generate:"
echo "     - AGENTS.md (project configuration)"
echo "     - .sumela/RULE_REGISTRY.md (stack-specific rules)"
echo "     - docs/second-brain/wiki/ (knowledge base)"
echo "     - IDE pointer files"
echo ""
echo "  3. Or run setup manually:"
echo "     bash scripts/setup.sh"
echo ""
