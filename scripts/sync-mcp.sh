#!/usr/bin/env bash
# sync-mcp.sh — Triggered by fswatch whenever Windsurf or VSCode MCP config changes.
# Rewrites canonical ~/.config/mcp-servers.json then projects to all targets atomically.

set -euo pipefail

WINDSURF_SRC="${HOME}/.codeium/windsurf/mcp_config.json"
VSCODE_SRC="${HOME}/Library/Application Support/Code/User/mcp.json"
CANON="${HOME}/.config/mcp-servers.json"
OPENCODE_OUT="${HOME}/.config/opencode/opencode.json"
LOG="${HOME}/.config/mcp-sync/sync.log"
TMPDIR_SYNC="${HOME}/.config/mcp-sync/tmp"

mkdir -p "$(dirname "$LOG")" "$TMPDIR_SYNC"

ts() { date '+%Y-%m-%d %H:%M:%S'; }

log() { echo "$(ts) $*" | tee -a "$LOG"; }

if ! command -v jq &>/dev/null; then
  log "✗ jq not found — brew install jq"
  exit 1
fi

# Determine best source of truth: prefer Windsurf, fall back to VSCode
if [ -f "$WINDSURF_SRC" ]; then
  RAW=$(jq '.mcpServers // {}' "$WINDSURF_SRC")
  SRC_LABEL="Windsurf"
elif [ -f "$VSCODE_SRC" ]; then
  # VSCode uses "servers" key with slightly different shape — normalise to mcpServers
  RAW=$(jq '.servers // .mcpServers // {}' "$VSCODE_SRC")
  SRC_LABEL="VSCode"
else
  log "✗ No MCP source found (Windsurf: $WINDSURF_SRC | VSCode: $VSCODE_SRC)"
  exit 1
fi

if [ -z "$RAW" ] || [ "$RAW" = "null" ] || [ "$RAW" = "{}" ]; then
  log "⚠ Source parsed but empty — skipping write"
  exit 0
fi

# Write atomically via tmp files
CANON_TMP=$(mktemp "$TMPDIR_SYNC/mcp-servers.XXXXXX.json")
OPENCODE_TMP=$(mktemp "$TMPDIR_SYNC/opencode.XXXXXX.json")

echo "$RAW" > "$CANON_TMP"
jq '{"mcp": .}' "$CANON_TMP" > "$OPENCODE_TMP"

mkdir -p "$(dirname "$CANON")" "$(dirname "$OPENCODE_OUT")"
mv "$CANON_TMP"    "$CANON"
mv "$OPENCODE_TMP" "$OPENCODE_OUT"

SERVER_COUNT=$(jq 'keys | length' "$CANON")
log "✓ Synced from $SRC_LABEL — $SERVER_COUNT server(s) → canonical + OpenCode"
