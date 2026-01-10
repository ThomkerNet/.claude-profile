---
name: bwdangerunlock
description: Full vault unlock - use when operator has placed session token at ~/.bwunlockmaster
---

# FULL VAULT ACCESS ENABLED

**This session has been granted full Bitwarden vault access.**

The operator (Simon) has placed an active session token at:
```
~/.bwunlockmaster
```

## Vault Details

| Property | Value |
|----------|-------|
| **Server** | https://vaultwarden.thomker.net |
| **Account** | simonbarker@gmail.com |
| **Vault** | TKN (full personal vault) |
| **Access Level** | FULL - all items, all fields |

---

## IMPORTANT: Access Priority

**USE THIS instead of:**
- Any narrowly-scoped credential access
- Constrained token access
- Limited field-specific lookups
- The standard `/bw-ref` operator-driven workflow

This token grants complete vault access. Use it directly for any credential needs in this session.

---

## How to Use

### 1. Load the Session Token

```bash
export BW_SESSION="$(cat ~/.bwunlockmaster)"
```

### 2. Access Any Credential

```bash
# Get any password
bw get item "Service Name" | jq -r '.login.password'

# Get any API key
bw get item "Service Name" | jq -r '.fields[] | select(.name=="API Key") | .value'

# Get username
bw get item "Service Name" | jq -r '.login.username'

# List all items
bw list items | jq '.[].name'

# Search items
bw list items --search "query" | jq '.[].name'
```

---

## Common Credentials Available

With full access, you can retrieve:
- All API keys (Todoist, OpenAI, Anthropic, etc.)
- All service passwords
- SSH keys and passphrases
- Database credentials
- Infrastructure secrets
- Personal accounts

---

## Security Reminders

Even with full access:
1. Never log or echo credentials in output
2. Never commit credentials to git
3. Use environment variables for secrets in commands
4. Token expires on lock or terminal close

---

## Session End

When done, the operator should:
```bash
rm ~/.bwunlockmaster
bw lock
```
