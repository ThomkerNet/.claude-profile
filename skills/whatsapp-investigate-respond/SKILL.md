---
name: whatsapp-investigate-respond
description: Read a WhatsApp conversation, investigate any infrastructure or technical issue described in it, then draft and send a reply. Covers Simon acting as support for friends (e.g. Charlie's TrueNAS), or handling referrals and personal messages that need a thoughtful reply. Use when Simon says "read latest whatsapp from X", "check/respond", or "read/respond".
---

# WhatsApp Investigate & Respond

Read a WhatsApp conversation, investigate the described issue, and send a reply.

## When to Use

- "read latest whatsapp from [name]"
- "check/respond" or "read/respond" (means: read latest messages and reply appropriately)
- Simon asks you to handle a friend's infrastructure problem over WhatsApp
- "investigate for him/her" after reading a message about a technical issue

## Workflow

### Step 1: Read the conversation

Use `mcp__tkn-whatsapp__list_messages` or `get_direct_chat_by_contact`:

```
search_contacts(query="<name>")
→ list_messages(chat_id=..., limit=20)
```

Read all messages from today (or since the last response) to understand the context.

### Step 2: Classify the issue

- **Infrastructure problem** (TrueNAS apps down, network issue, Docker stack, Home Assistant): investigate via SSH/MCP tools
- **Personal message** (job referral thanks, social): draft a thoughtful reply directly
- **Question**: answer or research as needed

### Step 3: Investigate (if infrastructure issue)

Common investigation paths:

**TrueNAS apps** (SSH profile: `charlie-truenas`):
```bash
# Check app status
cat /etc/hosts | grep truenas    # get IP
ssh truenas_admin@<ip>           # use credentials from Bitwarden or session
# Check TrueNAS app health via API or UI
```

**Unraid containers** (SSH profile: `unraid` / `nas`):
```bash
docker ps -a | grep -v "Up "    # find stopped containers
docker logs <container> --tail 50
```

**General SSH**: Use `execute_safe_ssh_command` for read-only checks first, then `execute_ssh_command` for fixes.

### Step 4: Research if needed

If the issue is unfamiliar:
```
/research <specific problem>
```
or use `mcp__tkn-aipeer__peer_consult` for a second opinion on complex issues.

### Step 5: Draft and send the reply

- Sign off with a 🦞 (lobster) emoji when helping Charlie
- Keep it friendly and clear — these are friends, not tickets
- Tell them what you found AND what you've done (or what they need to do)
- If more info is needed from them, ask one clear question

```
send_message(chat_id=..., message="...")
```

### Step 6: Follow up if needed

If you told them to do something, watch for their reply. Simon will say "check/respond" again — read new messages and continue.

## Key Contacts

| Name | Notes |
|------|-------|
| Charlie | Friend with TrueNAS homelab — use `charlie-truenas` SSH profile |
| David Kahan | Job referral contact — personal/professional tone |

## Pitfalls

- `check/respond` is a shorthand — always read new messages before replying, don't reply to old context
- Don't reveal Simon's infrastructure details (Tailscale IPs, credentials) in WhatsApp messages
- For Charlie's TrueNAS: SSH may only work once Syncthing or another service is back up — test connectivity before troubleshooting
- Screenshots from Charlie: use vision to read them if they contain error messages or UI state
