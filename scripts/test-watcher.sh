#!/usr/bin/env bash
# test-watcher.sh — Foreground watcher for testing. Ctrl-C to stop.

set -euo pipefail

WINDSURF_SRC="${HOME}/.codeium/windsurf/mcp_config.json"
VSCODE_SRC="${HOME}/Library/Application Support/Code/User/mcp.json"
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
[ -f "$WINDSURF_SRC" ] && WATCH_TARGETS+=("$WINDSURF_SRC") && echo "👀 Watching Windsurf: $WINDSURF_SRC"
[ -f "$VSCODE_SRC"   ] && WATCH_TARGETS+=("$VSCODE_SRC")   && echo "👀 Watching VSCode:   $VSCODE_SRC"

if [ ${#WATCH_TARGETS[@]} -eq 0 ]; then
  echo "✗ No MCP config files found to watch."
  echo "  Expected: $WINDSURF_SRC"
  echo "         or $VSCODE_SRC"
  exit 1
fi

echo ""
echo "✓ fswatch running (FSEvents, zero-poll). Save an MCP config to trigger sync."
echo "  Press Ctrl-C to stop."
echo ""

# Run initial sync on start
"$SYNC_SCRIPT"

fswatch -o "${WATCH_TARGETS[@]}" | xargs -n1 -I{} "$SYNC_SCRIPT"
