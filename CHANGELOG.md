# Changelog

All notable changes to this Claude Code profile are documented here.

## [2026-02-08]

### Changed
- **MCP server connectivity**: All TKN servers now use Tailscale HTTPS (`mcp-remote` via `gate-hexatonic.ts.net`)
- **AI Peer Review**: Migrated from local scripts to `tkn-aipeerreview` MCP server
- **Bitwarden access**: Consolidated to `/bwdangerunlock` only (removed `/bw-ref`, `/vault-*` commands)
- **Profile cleanup**: Removed stale references to Copilot CLI, Gemini CLI, Telegram, LiteLLM

### Removed
- `commands/aipeerreview.md`, `commands/review.md` - replaced by MCP server tools
- `scripts/aipeerreview/` - 6 TypeScript files (~1200 lines) replaced by MCP server
- `skills/solution-review/`, `skills/bw-ref/` - consolidated
- Gemini CLI and Copilot CLI installation from `install.ps1` and `setup.sh`
- LiteLLM environment variables from setup scripts and secrets template

### Added
- `tkn-gmail` MCP server (37 tools, Tailscale HTTPS)
- `tkn-komodo`, `tkn-authentik`, `tkn-firecrawl` MCP servers
- `/tts` skill for Azure AI Speech text-to-speech
- `/zcicd`, `/zdoc`, `/zmcpbacklog` commands
- Expanded Bitwarden security guardrails (8 specific rules)

## [2026-02-01]

### Added
- **MCP DSC Operations**: `--mcpdsc` flag in `setup.sh` for programmatic MCP server management
- `/zupdatetknmcpservers` skill: Auto-sync deployed TKN MCP servers from compose.yaml
- `tkn-haos` and `tkn-media` MCP servers

## [2026-01-31]

### Changed
- **Model routing**: Added `opusplan` model (Opus for plan mode, Sonnet for execution)
- **Cross-platform fix**: Replaced hardcoded macOS paths with portable `~` tilde expansion

## [2026-01-01]

### Added
- **Firecrawl API key**: Configured Firecrawl MCP server with personal API key

## [2025-12-31]

### Added
- **Memory MCP Server**: Persistent knowledge graph across sessions
- **Context7 documentation**: Guidelines for library documentation lookups

## [2025-12-30]

### Added
- **v2.0 Architecture**: Two-phase setup (`~/.claude-profile/` repo + `~/.claude/` runtime)
- Cross-platform support (Windows, macOS, Linux)
- Status line with model, git branch, session label, token usage
