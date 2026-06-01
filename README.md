# mcp-sync

> Zero-polling MCP config sync for macOS — Windsurf → canonical → OpenCode (and VSCode).  
> Uses Apple's native **FSEvents API** via `fswatch` for instant, battery-friendly file watching.

---

## What it does

```
~/.codeium/windsurf/mcp_config.json    ← source of truth (Windsurf)
~/Library/Application Support/Code/User/mcp.json  ← also watched (VSCode)
          │
          │  fswatch (FSEvents, zero-poll)
          ▼
~/.config/mcp-servers.json             ← canonical (single source of truth)
          │
          ├──► ~/.config/opencode/opencode.json     (OpenCode)
          └──► (extend sync-mcp.sh for more targets)
```

Every time you save an MCP config in Windsurf or VSCode, `fswatch` fires instantly,
`sync-mcp.sh` rewrites both targets **atomically** (via tmp files + mv), and the
`launchd` agent ensures it survives reboots.

---

## Requirements

- macOS (Apple Silicon or Intel)
- [Homebrew](https://brew.sh)
- Windsurf or VSCode already configured with MCP servers

---

## Install

```bash
chmod +x install.sh && ./install.sh
```

The installer will:
1. `brew install fswatch jq` (if not present)
2. Copy scripts to `~/.config/mcp-sync/scripts/`
3. Install the `mcp` CLI to `~/.local/bin/`
4. Bootstrap `~/.config/mcp-servers.json` from your Windsurf config
5. Register + load the `launchd` agent (auto-starts on login)

### Add to PATH (if prompted)

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc && source ~/.zshrc
```

---

## Test (foreground watcher)

```bash
~/.config/mcp-sync/scripts/test-watcher.sh
```

Save your Windsurf or VSCode MCP config — you'll see live output.  
Press `Ctrl-C` to stop.

---

## CLI Reference (`mcp`)

| Command | Description |
|---|---|
| `mcp list` | List all MCP servers from canonical config |
| `mcp status` | Full sync status (agent, fswatch, file freshness) |
| `mcp sync` | Manually trigger a sync right now |
| `mcp diff` | Compare canonical vs each sync target |
| `mcp logs` | Tail last 20 lines of sync log |
| `mcp logs -n 50` | Tail last N lines |
| `mcp agent start` | Start the launchd background agent |
| `mcp agent stop` | Stop the agent |
| `mcp agent restart` | Restart the agent |
| `mcp agent status` | Check if agent is running |
| `mcp add <name> <cmd> [args]` | Add a server to canonical and sync |
| `mcp remove <name>` | Remove a server from canonical and sync |
| `mcp paths` | Print all relevant config file paths |

### Examples

```bash
# List all configured MCP servers
mcp list

# Check everything is working
mcp status

# Force a manual sync
mcp sync

# Add a new server
mcp add filesystem npx -- -y @modelcontextprotocol/server-filesystem /tmp

# Add with env vars
mcp add github npx -- -y @modelcontextprotocol/server-github --env GITHUB_TOKEN=ghp_xxx

# Remove a server
mcp remove old-server

# View sync log
mcp logs

# Restart the background agent
mcp agent restart
```

---

## launchd Agent Management

```bash
# Check agent is running
launchctl list | grep mcp-sync

# View live log
tail -f ~/.config/mcp-sync/sync.log

# View errors
tail -f ~/.config/mcp-sync/sync.err

# Reload after editing scripts
launchctl unload ~/Library/LaunchAgents/com.user.mcp-sync.plist
launchctl load   ~/Library/LaunchAgents/com.user.mcp-sync.plist

# Or via CLI
mcp agent restart

# Stop permanently
launchctl unload ~/Library/LaunchAgents/com.user.mcp-sync.plist
```

---

## File Locations

| File | Purpose |
|---|---|
| `~/.config/mcp-servers.json` | Canonical single source of truth |
| `~/.codeium/windsurf/mcp_config.json` | Windsurf source (watched) |
| `~/Library/Application Support/Code/User/mcp.json` | VSCode source (watched) |
| `~/.config/opencode/opencode.json` | OpenCode sync target |
| `~/.config/mcp-sync/scripts/sync-mcp.sh` | Core sync script |
| `~/.config/mcp-sync/scripts/test-watcher.sh` | Foreground test watcher |
| `~/.config/mcp-sync/sync.log` | Sync activity log |
| `~/.config/mcp-sync/sync.err` | Error log |
| `~/Library/LaunchAgents/com.user.mcp-sync.plist` | launchd agent |
| `~/.local/bin/mcp` | CLI helper |

---

## Adding More Sync Targets

Edit `~/.config/mcp-sync/scripts/sync-mcp.sh` and add a new atomic write block:

```bash
# Example: sync to Cursor (~/.cursor/mcp.json)
CURSOR_TMP=$(mktemp "$TMPDIR_SYNC/cursor.XXXXXX.json")
jq '{"mcpServers": .}' "$CANON_TMP" > "$CURSOR_TMP"
mkdir -p ~/.cursor
mv "$CURSOR_TMP" ~/.cursor/mcp.json
```

Then run `mcp agent restart` to pick up the change.

---

## Agentic Directory Reference

| Tool | MCP config path |
|---|---|
| Windsurf | `~/.codeium/windsurf/mcp_config.json` |
| VSCode | `~/Library/Application Support/Code/User/mcp.json` |
| OpenCode | `~/.config/opencode/opencode.json` |
| Claude Desktop | `~/Library/Application Support/Claude/claude_desktop_config.json` |
| Claude Code | `~/.claude.json` |
| Cursor | `~/.cursor/mcp.json` |

Common agentic dirs: `.opencode/` `.claude/` `.agents/` `.codeium/windsurf/`
