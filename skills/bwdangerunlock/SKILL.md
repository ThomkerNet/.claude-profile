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

**USE THIS for all credential needs in this session.**

This token grants complete vault access.

---

## How to Use

### 1. Load the Session Token

```bash
export BW_SESSION="$(cat ~/.bwunlockmaster)"
```

### 2. Discover Items (write to /tmp first)

**IMPORTANT:** `bw list items` output is too large to pipe directly — it silently fails. Always write to a temp file first, then query with jq.

```bash
# Dump full vault index to temp file
bw list items > /tmp/bw_items.json

# Browse item names
jq -r '.[].name' /tmp/bw_items.json | grep -i "search term"

# Inspect a specific item's fields and structure
jq '.[] | select(.name | test("search term"; "i"))' /tmp/bw_items.json
```

### 3. Retrieve Specific Secrets

Once you know the exact item name from the index, use `bw get item` directly (single-item output is small enough to pipe):

```bash
# Get any password
bw get item "Service Name" | jq -r '.login.password'

# Get any API key
bw get item "Service Name" | jq -r '.fields[] | select(.name=="API Key") | .value'

# Get username
bw get item "Service Name" | jq -r '.login.username'
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

## Security Guardrails

This token grants **full vault access** - treat it with care:

1. **Never** log, echo, or print credentials in output
2. **Never** commit credentials to git
3. **Never** store credentials in files (use environment variables only)
4. **Retrieve only what you need** - don't dump the full vault unnecessarily
5. **Clear variables** after use when possible (`unset VAR_NAME`)
6. **Avoid shell history exposure** - prefix sensitive commands with a space (` export BW_SESSION=...`)
7. Token expires on `bw lock` or terminal close - session is time-bounded
8. Clean up temp files containing vault data (e.g. `/tmp/bw_items.json`) when done

---

## Session End

When done, the operator should:
```bash
rm ~/.bwunlockmaster
bw lock
```
