#!/bin/bash

set -e

echo "🚀 Setting up development environment..."

# Install Claude Code CLI
echo "📦 Installing Claude Code CLI..."
wget -q https://claude.ai/install.sh -O /tmp/claude-install.sh
bash /tmp/claude-install.sh
rm -f /tmp/claude-install.sh

# Add Claude Code to PATH
if ! grep -q 'export PATH="$HOME/.local/bin:$PATH"' ~/.bashrc; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
fi

# Source bashrc to make claude available immediately
source ~/.bashrc

# Verify installation
if command -v claude &> /dev/null; then
    echo "✅ Claude Code CLI installed successfully ($(claude --version))"
else
    echo "⚠️  Claude Code CLI installation may require PATH update"
fi

echo "🔬 logthis Development Environment Ready!"
