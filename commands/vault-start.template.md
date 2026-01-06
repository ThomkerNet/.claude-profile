> **DEPRECATED:** Auto-start handles this. Use `/vault-get` or `/vault-search` directly.
> For RW operations, use `/bw-elevate` instead.

Unlock vault and start API server for autonomous access.

```bash
start powershell -NoExit -Command "{{BUN_PATH}} run {{CLAUDE_HOME}}/tools/vaultwarden/bw-wrapper.ts unlock; if ($?) { {{BUN_PATH}} run {{CLAUDE_HOME}}/tools/vaultwarden/bw-wrapper.ts start }"
```

Opens a new terminal window for master password entry, then starts the API server.
