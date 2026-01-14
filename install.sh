#!/usr/bin/env bash
# sshort installer
# https://github.com/USER/sshort

set -euo pipefail

INSTALL_DIR="${SSHORT_INSTALL_DIR:-$HOME/.local/bin}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/sshort"
REPO_URL="https://raw.githubusercontent.com/USER/sshort/main"

echo "🔐 Installing sshort..."
echo ""

# Create directories
mkdir -p "$INSTALL_DIR" "$CONFIG_DIR"

# Download or copy script
if [[ -f "./sshort" ]]; then
    echo "📦 Installing from local source..."
    cp ./sshort "$INSTALL_DIR/sshort"
else
    echo "📦 Downloading from GitHub..."
    curl -fsSL "$REPO_URL/sshort" -o "$INSTALL_DIR/sshort"
fi

chmod +x "$INSTALL_DIR/sshort"

# Check if in PATH
if ! echo "$PATH" | grep -q "$INSTALL_DIR"; then
    echo ""
    echo "⚠️  $INSTALL_DIR is not in your PATH"
    echo "   Add to ~/.bashrc or ~/.zshrc:"
    echo ""
    echo "   export PATH=\"$INSTALL_DIR:\$PATH\""
    echo ""
fi

# Create config if it doesn't exist
if [[ ! -f "$CONFIG_DIR/config" ]]; then
    echo "📝 Creating default config..."
    "$INSTALL_DIR/sshort" config init
fi

echo ""
echo "✅ sshort installed to $INSTALL_DIR/sshort"
echo ""
echo "Next steps:"
echo "  1. Edit config: sshort config edit"
echo "  2. Run doctor:  sshort doctor"
echo "  3. Get certs:   sshort github +8h"
echo ""
echo "Optional shell integration:"
echo "  eval \"\$(sshort shell-init)\""
