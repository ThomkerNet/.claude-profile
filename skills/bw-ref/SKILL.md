---
name: bw-ref
description: Bitwarden credential access via bw CLI. Load when accessing secrets.
---

# Bitwarden Reference

## Vault

| Vault | Server | Account |
|-------|--------|---------|
| **TKN** (personal) | vaultwarden.thomker.net | simonbarker@gmail.com |

Access is operator-driven - Simon unlocks and provides session token.

---

## Workflow

1. **Simon runs:** `bw unlock --raw` → copies session token
2. **Claude uses:** Session token for BW commands
3. **After session:** `bw lock`

---

## Commands

```bash
bw login                  # First-time setup
bw unlock --raw           # Get session token
bw lock                   # End session
bw get item "name"        # With active session
```

---

## Using Session Token

```bash
export BW_SESSION="<token-from-operator>"
bw get item "Todoist" | jq -r '.fields[] | select(.name=="API Key") | .value'
```

---

## Common Patterns

### Get API Key from Item

```bash
bw get item "Service Name" | jq -r '.fields[] | select(.name=="API Key") | .value'
```

### Get Password

```bash
bw get item "Service Name" | jq -r '.login.password'
```

### Get Username

```bash
bw get item "Service Name" | jq -r '.login.username'
```

### List Items

```bash
bw list items | jq '.[].name'
```

---

## Session Management

- Sessions expire on `bw lock` or new terminal

---

## Security Notes

1. Never log or echo credentials
2. Never commit credentials to git
3. Use environment variables, not command-line args for secrets
