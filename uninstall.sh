#!/usr/bin/env bash
# uninstall.sh — Completely remove mcp-sync from macOS.

set -euo pipefail

PLIST_LABEL="com.user.mcp-sync"
PLIST_PATH="${HOME}/Library/LaunchAgents/${PLIST_LABEL}.plist"
INSTALL_TARGET="${HOME}/.config/mcp-sync"
BIN_TARGET="${HOME}/.local/bin/mcp"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  mcp-sync uninstaller"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

read -p "This will remove mcp-sync completely. Continue? [y/N] " yn
if [[ ! "$yn" =~ ^[Yy]$ ]]; then
  echo "Cancelled."
  exit 0
fi

# 1. Unload launchd agent
if [ -f "$PLIST_PATH" ]; then
  launchctl unload "$PLIST_PATH" 2>/dev/null || true
  rm -f "$PLIST_PATH"
  ok "launchd agent unloaded and removed"
else
  warn "launchd plist not found (already removed?)"
fi

# 2. Remove scripts and config dir
if [ -d "$INSTALL_TARGET" ]; then
  rm -rf "$INSTALL_TARGET"
  ok "Removed $INSTALL_TARGET"
fi

# 3. Remove CLI
if [ -f "$BIN_TARGET" ]; then
  rm -f "$BIN_TARGET"
  ok "Removed CLI: $BIN_TARGET"
fi

# 4. Note about canonical file
echo ""
warn "The following files were NOT removed (your MCP configs):"
echo "  • ~/.config/mcp-servers.json (canonical config)"
echo "  • IDE-specific configs (Windsurf, VSCode, Cursor, etc.)"
echo ""
echo "  To remove the canonical file: rm ~/.config/mcp-servers.json"
echo ""
ok "mcp-sync uninstalled successfully"
echo ""
