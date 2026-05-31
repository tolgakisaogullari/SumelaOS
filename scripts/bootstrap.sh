#!/bin/bash
# OpenSkills Bootstrap — one-liner setup for existing projects
# Usage: curl -sSL https://raw.githubusercontent.com/tolgakisaogullari/openskills/master/scripts/bootstrap.sh | bash

set -e

REPO_URL="https://github.com/tolgakisaogullari/openskills.git"
TEMP_DIR=$(mktemp -d)

echo "📦 Cloning openskills..."
git clone --depth 1 "$REPO_URL" "$TEMP_DIR" 2>/dev/null

echo "📂 Copying files to current project..."
cp -r "$TEMP_DIR/.openskills" . 2>/dev/null || true
cp -r "$TEMP_DIR/scripts" . 2>/dev/null || true
cp "$TEMP_DIR/AGENTS.md.template" . 2>/dev/null || true
cp "$TEMP_DIR/CLAUDE.md.template" . 2>/dev/null || true
cp "$TEMP_DIR/.clinerules.template" . 2>/dev/null || true
cp -r "$TEMP_DIR/.cursor" . 2>/dev/null || true
cp -r "$TEMP_DIR/.kilocode" . 2>/dev/null || true
cp -r "$TEMP_DIR/.trae" . 2>/dev/null || true

# Create .gitkeep files for empty directories
mkdir -p docs/second-brain/template/raw_sources
mkdir -p docs/second-brain/template/artifacts/plans
mkdir -p docs/second-brain/template/artifacts/specs
touch docs/second-brain/template/raw_sources/.gitkeep
touch docs/second-brain/template/artifacts/plans/.gitkeep
touch docs/second-brain/template/artifacts/specs/.gitkeep

echo "🧹 Cleaning up temp files..."
rm -rf "$TEMP_DIR"

echo ""
echo "✅ OpenSkills installed! Next steps:"
echo ""
echo "  1. In your AI coding assistant, run:"
echo "     /initOpenSkills"
echo ""
echo "  2. The agent will auto-detect your stack and generate:"
echo "     - AGENTS.md (project configuration)"
echo "     - .openskills/RULE_REGISTRY.md (stack-specific rules)"
echo "     - docs/second-brain/wiki/ (knowledge base)"
echo "     - IDE pointer files"
echo ""
echo "  3. Or run setup manually:"
echo "     bash scripts/setup.sh"
echo ""
