#!/usr/bin/env bash
# sync-mcp.sh — Triggered by fswatch whenever any IDE MCP config changes.
# Reads canonical ~/.config/mcp-servers.json then projects to all IDE targets atomically.
# If canonical doesn't exist, bootstraps from the best available source.

set -euo pipefail

# ── Paths ──────────────────────────────────────────────────────────────────────
CANON="${HOME}/.config/mcp-servers.json"
WINDSURF_CFG="${HOME}/.codeium/windsurf/mcp_config.json"
VSCODE_CFG="${HOME}/Library/Application Support/Code/User/mcp.json"
CURSOR_CFG="${HOME}/.cursor/mcp.json"
ZED_CFG="${HOME}/.config/zed/settings.json"
CLAUDE_CODE_CFG="${HOME}/.claude.json"
OPENCODE_CFG="${HOME}/.config/opencode/opencode.json"
LOG="${HOME}/.config/mcp-sync/sync.log"
LOCK="${HOME}/.config/mcp-sync/.sync.lock"
TMPDIR_SYNC="${HOME}/.config/mcp-sync/tmp"

mkdir -p "$(dirname "$LOG")" "$TMPDIR_SYNC"

ts() { date '+%Y-%m-%d %H:%M:%S'; }
log() { echo "$(ts) $*" | tee -a "$LOG"; }

# ── Lock to prevent re-entrant loops ──────────────────────────────────────────
# When we write to IDE configs, fswatch fires again. This lock prevents loops.
if [ -f "$LOCK" ]; then
  lock_age=$(( $(date +%s) - $(stat -f %m "$LOCK" 2>/dev/null || echo 0) ))
  if [ "$lock_age" -lt 5 ]; then
    exit 0
  fi
  rm -f "$LOCK"
fi

acquire_lock() { touch "$LOCK"; }
release_lock() { rm -f "$LOCK"; }
trap release_lock EXIT

acquire_lock

# ── Dependency check ──────────────────────────────────────────────────────────
if ! command -v jq &>/dev/null; then
  log "✗ jq not found — brew install jq"
  exit 1
fi

# ── Bootstrap canonical from best available source ────────────────────────────
bootstrap_from_source() {
  local RAW=""
  local SRC_LABEL=""

  if [ -f "$WINDSURF_CFG" ]; then
    RAW=$(jq -e '.mcpServers // empty' "$WINDSURF_CFG" 2>/dev/null || true)
    SRC_LABEL="Windsurf"
  fi

  if [ -z "$RAW" ] || [ "$RAW" = "null" ] || [ "$RAW" = "{}" ]; then
    if [ -f "$VSCODE_CFG" ]; then
      RAW=$(jq -e '(.servers // .mcpServers // empty) | with_entries(.value |= del(.type))' "$VSCODE_CFG" 2>/dev/null || true)
      SRC_LABEL="VSCode"
    fi
  fi

  if [ -z "$RAW" ] || [ "$RAW" = "null" ] || [ "$RAW" = "{}" ]; then
    if [ -f "$CURSOR_CFG" ]; then
      RAW=$(jq -e '.mcpServers // empty' "$CURSOR_CFG" 2>/dev/null || true)
      SRC_LABEL="Cursor"
    fi
  fi

  if [ -z "$RAW" ] || [ "$RAW" = "null" ] || [ "$RAW" = "{}" ]; then
    if [ -f "$CLAUDE_CODE_CFG" ]; then
      RAW=$(jq -e '.mcpServers // empty' "$CLAUDE_CODE_CFG" 2>/dev/null || true)
      SRC_LABEL="Claude Code"
    fi
  fi

  if [ -z "$RAW" ] || [ "$RAW" = "null" ] || [ "$RAW" = "{}" ]; then
    log "✗ No MCP source found to bootstrap from"
    exit 1
  fi

  mkdir -p "$(dirname "$CANON")"
  echo "$RAW" | jq '.' > "$CANON"
  chmod 600 "$CANON"
  log "✓ Bootstrapped canonical from $SRC_LABEL"
}

if [ ! -f "$CANON" ] || [ ! -s "$CANON" ]; then
  bootstrap_from_source
fi

# ── Detect which file changed and update canonical ────────────────────────────
CHANGED_FILE="${1:-}"

update_canonical_from() {
  local src_file="$1"
  local src_label="$2"
  local jq_filter="$3"
  local new_data

  [ -f "$src_file" ] || return 1

  new_data=$(jq -e "$jq_filter" "$src_file" 2>/dev/null || true)
  if [ -z "$new_data" ] || [ "$new_data" = "null" ] || [ "$new_data" = "{}" ]; then
    return 1
  fi

  # Only update if different from current canonical
  local current_canon=""
  [ -f "$CANON" ] && current_canon=$(jq -Sc '.' "$CANON" 2>/dev/null || true)
  local new_sorted
  new_sorted=$(echo "$new_data" | jq -Sc '.')

  if [ "$current_canon" != "$new_sorted" ]; then
    local tmp
    tmp=$(mktemp "$TMPDIR_SYNC/canon.XXXXXX.json")
    echo "$new_data" | jq '.' > "$tmp"
    chmod 600 "$tmp"
    mv "$tmp" "$CANON"
    log "✓ Updated canonical from $src_label"
  fi
  return 0
}

if [ -n "$CHANGED_FILE" ]; then
  case "$CHANGED_FILE" in
    *windsurf*|*codeium*)
      update_canonical_from "$WINDSURF_CFG" "Windsurf" '.mcpServers // empty' || true
      ;;
    *"Code/User"*|*vscode*)
      update_canonical_from "$VSCODE_CFG" "VSCode" '(.servers // .mcpServers // empty) | with_entries(.value |= del(.type))' || true
      ;;
    *cursor*)
      update_canonical_from "$CURSOR_CFG" "Cursor" '.mcpServers // empty' || true
      ;;
    *zed*)
      update_canonical_from "$ZED_CFG" "Zed" '.context_servers // empty | with_entries(.value |= del(.source))' || true
      ;;
    *.claude.json)
      update_canonical_from "$CLAUDE_CODE_CFG" "Claude Code" '.mcpServers // empty' || true
      ;;
    *opencode*)
      update_canonical_from "$OPENCODE_CFG" "OpenCode" '.mcpServers // .mcp // empty' || true
      ;;
  esac
fi

# ── Read canonical ────────────────────────────────────────────────────────────
CANON_DATA=$(jq '.' "$CANON" 2>/dev/null || true)
if [ -z "$CANON_DATA" ] || [ "$CANON_DATA" = "null" ] || [ "$CANON_DATA" = "{}" ]; then
  log "⚠ Canonical file is empty — skipping sync"
  exit 0
fi

SERVER_COUNT=$(echo "$CANON_DATA" | jq 'keys | length')

# ── Atomic write helper ───────────────────────────────────────────────────────
atomic_write() {
  local dest="$1"
  local content="$2"
  mkdir -p "$(dirname "$dest")"
  local tmp
  tmp=$(mktemp "$TMPDIR_SYNC/target.XXXXXX.json")
  echo "$content" > "$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$dest"
}

# ── Write to all targets ──────────────────────────────────────────────────────

# 1. Windsurf: {"mcpServers": {...}}
if [ -d "$(dirname "$WINDSURF_CFG")" ] || [ -f "$WINDSURF_CFG" ]; then
  windsurf_out=$(echo "$CANON_DATA" | jq '{mcpServers: .}')
  atomic_write "$WINDSURF_CFG" "$windsurf_out"
fi

# 2. VSCode: {"servers": {...}} — adds "type":"stdio" for command-based, "type":"http" for url-based
if [ -d "$(dirname "$VSCODE_CFG")" ] || [ -f "$VSCODE_CFG" ]; then
  vscode_out=$(echo "$CANON_DATA" | jq '{servers: with_entries(.value |= (if .url then {type:"http"} + . else {type:"stdio"} + . end))}')
  atomic_write "$VSCODE_CFG" "$vscode_out"
fi

# 3. Cursor: {"mcpServers": {...}}
if [ -d "$(dirname "$CURSOR_CFG")" ] || [ -f "$CURSOR_CFG" ]; then
  cursor_out=$(echo "$CANON_DATA" | jq '{mcpServers: .}')
  atomic_write "$CURSOR_CFG" "$cursor_out"
fi

# 4. Zed: merge "context_servers" into existing settings.json, adding source:"custom"
if [ -d "$(dirname "$ZED_CFG")" ]; then
  zed_servers=$(echo "$CANON_DATA" | jq 'with_entries(.value += {source: "custom"})')
  if [ -f "$ZED_CFG" ]; then
    zed_out=$(jq --argjson servers "$zed_servers" '.context_servers = $servers' "$ZED_CFG" 2>/dev/null || echo "{\"context_servers\": $zed_servers}")
  else
    zed_out=$(echo "$zed_servers" | jq '{context_servers: .}')
  fi
  atomic_write "$ZED_CFG" "$zed_out"
fi

# 5. Claude Code: merge "mcpServers" into existing ~/.claude.json
if [ -f "$CLAUDE_CODE_CFG" ]; then
  claude_out=$(jq --argjson servers "$CANON_DATA" '.mcpServers = $servers' "$CLAUDE_CODE_CFG" 2>/dev/null || echo "{\"mcpServers\": $CANON_DATA}")
  atomic_write "$CLAUDE_CODE_CFG" "$claude_out"
else
  claude_out=$(echo "$CANON_DATA" | jq '{mcpServers: .}')
  atomic_write "$CLAUDE_CODE_CFG" "$claude_out"
fi

# 6. OpenCode: {"mcpServers": {...}}
opencode_out=$(echo "$CANON_DATA" | jq '{mcpServers: .}')
atomic_write "$OPENCODE_CFG" "$opencode_out"

log "✓ Synced $SERVER_COUNT server(s) → Windsurf, VSCode, Cursor, Zed, Claude Code, OpenCode"
