Check vault API status and show available commands.

```bash
{{BUN_PATH}} run {{CLAUDE_HOME}}/tools/vaultwarden/bw-wrapper.ts api-status
```

## Vault Commands

| Command | Description |
|---------|-------------|
| `/vault` | Check API status |
| `/vault-start` | Unlock + start server (enter password once) |
| `/vault-stop` | Stop API server |
| `/vault-get <name>` | Get credential by name |
| `/vault-search <query>` | Search credentials |

## Quick Start

Run `/vault-start`, enter master password, then use `/vault-get` or `/vault-search`.
