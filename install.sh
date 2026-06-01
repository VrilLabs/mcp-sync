#!/usr/bin/env bash
# install.sh — Run once to install mcp-sync on macOS.
# Installs brew deps, copies scripts, registers launchd agent, installs CLI helper.
# Supports: Windsurf, VSCode, Cursor, Zed, Claude Code, OpenCode

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_TARGET="${HOME}/.config/mcp-sync"
BIN_TARGET="${HOME}/.local/bin"
PLIST_DIR="${HOME}/Library/LaunchAgents"
PLIST_LABEL="com.user.mcp-sync"
PLIST_PATH="${PLIST_DIR}/${PLIST_LABEL}.plist"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
fail() { echo -e "${RED}✗${NC} $*"; exit 1; }
info() { echo -e "${CYAN}→${NC} $*"; }

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  mcp-sync installer"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── 1. Homebrew deps ──────────────────────────────────────────────
echo "→ Checking brew dependencies..."
command -v brew &>/dev/null || fail "Homebrew not found. Install from https://brew.sh"

for pkg in fswatch jq; do
  if brew list --formula "$pkg" &>/dev/null; then
    ok "$pkg already installed"
  else
    echo "  Installing $pkg..."
    brew install "$pkg" && ok "$pkg installed"
  fi
done

# ── 2. Copy scripts ───────────────────────────────────────────────
echo ""
echo "→ Installing scripts to $INSTALL_TARGET..."
mkdir -p "$INSTALL_TARGET/tmp" "$INSTALL_TARGET/scripts"
cp "$SCRIPT_DIR/scripts/sync-mcp.sh"    "$INSTALL_TARGET/scripts/"
cp "$SCRIPT_DIR/scripts/test-watcher.sh" "$INSTALL_TARGET/scripts/"
chmod +x "$INSTALL_TARGET/scripts/"*.sh
ok "Scripts installed"

# ── 3. Install Python CLI helper ─────────────────────────────────
echo ""
echo "→ Installing mcp CLI helper to $BIN_TARGET..."
mkdir -p "$BIN_TARGET"
cp "$SCRIPT_DIR/bin/mcp" "$BIN_TARGET/mcp"
chmod +x "$BIN_TARGET/mcp"
ok "mcp CLI installed → $BIN_TARGET/mcp"

# Check PATH
if [[ ":$PATH:" != *":$BIN_TARGET:"* ]]; then
  warn "$BIN_TARGET not in PATH."
  echo "  Add to ~/.zshrc:"
  echo ""
  echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
  echo ""
  read -p "  Append to ~/.zshrc now? [y/N] " yn
  if [[ "$yn" =~ ^[Yy]$ ]]; then
    echo '' >> ~/.zshrc
    echo '# mcp-sync CLI' >> ~/.zshrc
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
    ok "Appended to ~/.zshrc (run: source ~/.zshrc)"
  fi
fi

# ── 4. Bootstrap canonical file ──────────────────────────────────
echo ""
echo "→ Bootstrapping canonical MCP config..."
"$INSTALL_TARGET/scripts/sync-mcp.sh" || warn "Initial sync skipped (no source found yet)"

# ── 5. Register launchd agent ────────────────────────────────────
echo ""
echo "→ Registering launchd agent: $PLIST_LABEL..."
mkdir -p "$PLIST_DIR"

FSWATCH_BIN="$(command -v fswatch)"
SYNC_SCRIPT="$INSTALL_TARGET/scripts/sync-mcp.sh"

# All IDE config paths to watch
WINDSURF_CFG="${HOME}/.codeium/windsurf/mcp_config.json"
VSCODE_CFG="${HOME}/Library/Application Support/Code/User/mcp.json"
CURSOR_CFG="${HOME}/.cursor/mcp.json"
ZED_CFG="${HOME}/.config/zed/settings.json"
CLAUDE_CODE_CFG="${HOME}/.claude.json"
OPENCODE_CFG="${HOME}/.config/opencode/opencode.json"

# Build fswatch command watching all existing config directories
WATCH_PATHS=""
for cfg_path in "$WINDSURF_CFG" "$VSCODE_CFG" "$CURSOR_CFG" "$ZED_CFG" "$CLAUDE_CODE_CFG" "$OPENCODE_CFG"; do
  cfg_dir=$(dirname "$cfg_path")
  if [ -d "$cfg_dir" ] || [ -f "$cfg_path" ]; then
    WATCH_PATHS="$WATCH_PATHS \"$cfg_path\""
  fi
done

# Always ensure at least the common directories exist for watching
mkdir -p "${HOME}/.config/opencode"
mkdir -p "${HOME}/.config/zed" 2>/dev/null || true

cat > "$PLIST_PATH" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${PLIST_LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/sh</string>
    <string>-c</string>
    <string>${FSWATCH_BIN} -o "${WINDSURF_CFG}" "${VSCODE_CFG}" "${CURSOR_CFG}" "${ZED_CFG}" "${CLAUDE_CODE_CFG}" "${OPENCODE_CFG}" 2>/dev/null | while read f; do ${SYNC_SCRIPT}; done</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${HOME}/.config/mcp-sync/sync.log</string>
  <key>StandardErrorPath</key>
  <string>${HOME}/.config/mcp-sync/sync.err</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
    <key>HOME</key>
    <string>${HOME}</string>
  </dict>
</dict>
</plist>
PLIST

# Unload if already loaded, then reload
launchctl unload "$PLIST_PATH" 2>/dev/null || true
launchctl load   "$PLIST_PATH"
ok "launchd agent loaded (auto-starts on login)"

# ── 6. Detect installed IDEs ─────────────────────────────────────
echo ""
info "Detected IDE configurations:"
declare -A IDE_PATHS=(
  ["Windsurf"]="$WINDSURF_CFG"
  ["VSCode"]="$VSCODE_CFG"
  ["Cursor"]="$CURSOR_CFG"
  ["Zed"]="$ZED_CFG"
  ["Claude Code"]="$CLAUDE_CODE_CFG"
  ["OpenCode"]="$OPENCODE_CFG"
)
for ide in "Windsurf" "VSCode" "Cursor" "Zed" "Claude Code" "OpenCode"; do
  cfg="${IDE_PATHS[$ide]}"
  if [ -f "$cfg" ]; then
    ok "  $ide: $cfg"
  elif [ -d "$(dirname "$cfg")" ]; then
    warn "  $ide: directory exists, config will be created on sync"
  else
    echo -e "  ${YELLOW}○${NC} $ide: not installed"
  fi
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}  Installation complete!${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Usage:                        mcp --help"
echo "  Validate configs:             mcp doctor"
echo "  Test watcher (foreground):    $INSTALL_TARGET/scripts/test-watcher.sh"
echo "  Sync log:                     ~/.config/mcp-sync/sync.log"
echo "  Install MCP servers:          mcp search | mcp install <package>"
echo ""
