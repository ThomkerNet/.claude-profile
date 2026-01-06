# Claude Profile Health Check

Run a comprehensive health check on the ~/.claude profile configuration.

## Instructions

Execute the following checks and report results in a formatted table:

### 1. Check Prerequisites
Run this command and capture output:
```bash
echo "git:$(git --version 2>/dev/null | cut -d' ' -f3 || echo 'MISSING')"
echo "node:$(node --version 2>/dev/null || echo 'MISSING')"
echo "jq:$(jq --version 2>/dev/null || echo 'MISSING')"
echo "tmux:$(tmux -V 2>/dev/null | cut -d' ' -f2 || echo 'MISSING')"
echo "bun:$($HOME/.bun/bin/bun --version 2>/dev/null || bun --version 2>/dev/null || echo 'MISSING')"
echo "claude:$(claude --version 2>/dev/null || echo 'MISSING')"
echo "gemini:$(command -v gemini &>/dev/null && echo 'installed' || echo 'MISSING')"
echo "copilot:$(command -v copilot &>/dev/null && echo 'installed' || echo 'MISSING')"
echo "bw:$(bw --version 2>/dev/null || echo 'MISSING')"
echo "bun_in_path:$(command -v bun &>/dev/null && echo 'yes' || echo 'no')"
```

### 2. Check MCP Servers
```bash
claude mcp list 2>/dev/null
```

### 3. Check Config Files
```bash
for f in settings.json secrets.json mcp-servers.json CLAUDE.md; do
  [ -f "$HOME/.claude/$f" ] && echo "$f:present" || echo "$f:MISSING"
done
```

### 4. Check Tmux Plugins
```bash
for p in tpm tmux-resurrect tmux-continuum; do
  [ -d "$HOME/.tmux/plugins/$p" ] && echo "$p:installed" || echo "$p:MISSING"
done
```

### 5. Check Telegram Integration
```bash
[ -d "$HOME/.claude/hooks/telegram-bun/node_modules" ] && echo "telegram_deps:installed" || echo "telegram_deps:MISSING"
[ -f "$HOME/.claude/hooks/telegram-bun/telegram-config.json" ] && echo "telegram_config:present" || echo "telegram_config:not configured"
```

### 6. Check Skills (SKILL.md based)
```bash
echo "=== Skills (skills/) ==="
for s in "$HOME/.claude/skills"/*/; do
  name=$(basename "$s")
  [ -f "$s/SKILL.md" ] && echo "skill:$name:valid" || echo "skill:$name:invalid (no SKILL.md)"
done
```

### 6b. Check Scripts (invokable by commands)
```bash
echo "=== Scripts (scripts/) ==="
for s in "$HOME/.claude/scripts"/*/; do
  name=$(basename "$s")
  [ -f "$s/index.ts" ] && echo "script:$name:valid" || echo "script:$name:invalid (no index.ts)"
done
```

### 7. Check Quota Fetcher (macOS)
```bash
[ -f "$HOME/Library/LaunchAgents/com.claude.quota-fetcher.plist" ] && echo "quota_plist:installed" || echo "quota_plist:MISSING"
launchctl list 2>/dev/null | grep -q quota && echo "quota_launchd:loaded" || echo "quota_launchd:not loaded"
[ -f "$HOME/.claude/.quota-cache" ] && echo "quota_data:present" || echo "quota_data:no data yet"
```

### 8. Check Statusline
```bash
[ -f "$HOME/.claude/statuslines/statusline.sh" ] && echo "statusline:present" || echo "statusline:MISSING"
echo '{}' | "$HOME/.claude/statuslines/statusline.sh" 2>&1 | head -1
```

### 9. Check Bitwarden Config
```bash
bw config server 2>/dev/null || echo "bw_server:not configured"
```

### 10. Check Memory Persistence
```bash
claude mcp get memory 2>/dev/null | grep -q "MEMORY_FILE_PATH" && echo "memory_persistence:configured" || echo "memory_persistence:NOT SET (memory won't persist)"
```

## Output Format

Present results as:

```
## Profile Health Report

### Prerequisites
| Tool | Status |
|------|--------|
| Git | version or MISSING |
| Node.js | version or MISSING |
| ... | ... |

### MCP Servers
| Server | Status |
|--------|--------|
| context7 | Connected/Failed |
| ... | ... |

### Configuration
| Component | Status |
|-----------|--------|
| settings.json | present/MISSING |
| ... | ... |

### Issues Found
- List any MISSING or failed items
- Suggest fixes for each issue

### Summary
X/Y components healthy
```

If issues are found, offer to fix them automatically where possible.
