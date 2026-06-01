#!/usr/bin/env bash
# test-watcher.sh — Foreground watcher for testing. Ctrl-C to stop.

set -euo pipefail

WINDSURF_CFG="${HOME}/.codeium/windsurf/mcp_config.json"
VSCODE_CFG="${HOME}/Library/Application Support/Code/User/mcp.json"
CURSOR_CFG="${HOME}/.cursor/mcp.json"
ZED_CFG="${HOME}/.config/zed/settings.json"
CLAUDE_CODE_CFG="${HOME}/.claude.json"
OPENCODE_CFG="${HOME}/.config/opencode/opencode.json"
CANON="${HOME}/.config/mcp-servers.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYNC_SCRIPT="$SCRIPT_DIR/sync-mcp.sh"

if ! command -v fswatch &>/dev/null; then
  echo "✗ fswatch not found — brew install fswatch"
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "✗ jq not found — brew install jq"
  exit 1
fi

WATCH_TARGETS=()

declare -A IDE_LABELS=(
  ["$WINDSURF_CFG"]="Windsurf"
  ["$VSCODE_CFG"]="VSCode"
  ["$CURSOR_CFG"]="Cursor"
  ["$ZED_CFG"]="Zed"
  ["$CLAUDE_CODE_CFG"]="Claude Code"
  ["$OPENCODE_CFG"]="OpenCode"
  ["$CANON"]="Canonical"
)

for path in "$WINDSURF_CFG" "$VSCODE_CFG" "$CURSOR_CFG" "$ZED_CFG" "$CLAUDE_CODE_CFG" "$OPENCODE_CFG" "$CANON"; do
  if [ -f "$path" ]; then
    WATCH_TARGETS+=("$path")
    echo "👀 Watching ${IDE_LABELS[$path]}: $path"
  fi
done

if [ ${#WATCH_TARGETS[@]} -eq 0 ]; then
  echo "✗ No MCP config files found to watch."
  echo "  Expected one of:"
  for path in "$WINDSURF_CFG" "$VSCODE_CFG" "$CURSOR_CFG" "$ZED_CFG" "$CLAUDE_CODE_CFG" "$OPENCODE_CFG"; do
    echo "    $path"
  done
  exit 1
fi

echo ""
echo "✓ fswatch running (FSEvents, zero-poll). Save an MCP config to trigger sync."
echo "  Press Ctrl-C to stop."
echo ""

# Run initial sync on start
"$SYNC_SCRIPT" || true

fswatch -o "${WATCH_TARGETS[@]}" | while read -r _; do
  "$SYNC_SCRIPT" || true
done
