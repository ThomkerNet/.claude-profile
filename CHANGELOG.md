# Changelog

All notable changes to this Claude Code profile are documented here.

## [2026-01-01]

### Added
- **Firecrawl API key**: Configured Firecrawl MCP server with personal API key for usage tracking

## [2025-12-31]

### Added
- **Memory MCP Server**: Persistent knowledge graph across sessions using `@modelcontextprotocol/server-memory`
  - Stores entities, relations, and observations
  - Memory file gitignored (machine-specific)
- **Vault write operations**: `api-create` and `api-update` commands for credential management
- **Context7 documentation**: Guidelines for when to use Context7 vs training knowledge vs web search

### Changed
- Vault security hardening: password redaction, session TTL (30 min default), audit logging
- Combined vault unlock + start into single `/vault-start` command

### Fixed
- API response parsing for nested Bitwarden data structure

## [2025-12-30]

### Added
- Individual vault slash commands: `/vault`, `/vault-start`, `/vault-stop`, `/vault-get`, `/vault-search`
- Autonomous vault access via `bw serve` REST API on localhost:8087

## [2025-12-29]

### Added
- GitHub Copilot CLI integration for terminal assistance
- Vaultwarden integration for self-hosted password vault access
- Template-based slash command generation for portability

### Changed
- Use interactive login for Vaultwarden (master password not stored)
- Gitignore generated slash commands (use `.template.md` versions)

## [2025-12-28]

### Added
- Telegram two-way integration with remote control via bot
- Multi-LLM setup: Claude Code, Gemini CLI, Copilot CLI
- Portable profile structure for Windows/macOS/Linux

### Changed
- Template-based settings.json generation
- Cross-platform bun detection in setup scripts
