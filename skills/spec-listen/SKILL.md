# Spec Listen Command

> **Description:** Toggle autonomous spec polling on/off for agent-to-agent handoffs

## Usage

```bash
/spec-listen          # Enable polling (or show status if already enabled)
/spec-listen on       # Enable polling
/spec-listen off      # Disable polling
/spec-listen status   # Show current status
```

## Instructions for Claude

When the user runs `/spec-listen`, execute the appropriate bash command based on the argument:

**For `/spec-listen` or `/spec-listen on`:**
```bash
touch ~/.claude/.spec-poller-enabled && echo "✅ Spec listening ENABLED. I will poll for incoming specs when idle (3hr timeout)."
```

**For `/spec-listen off`:**
```bash
rm -f ~/.claude/.spec-poller-enabled && echo "⏹️ Spec listening DISABLED. Normal stop behavior restored."
```

**For `/spec-listen status`:**
```bash
if [ -f ~/.claude/.spec-poller-enabled ]; then echo "📡 Spec listening is ENABLED"; else echo "⏹️ Spec listening is DISABLED (default)"; fi
```

## What It Does

When **enabled**, this Claude session will:
- Poll `.claude-specs/` every 30 seconds when idle
- Automatically pick up new `*-SPEC.md` files from other agents
- Continue polling for up to 3 hours before timing out
- Process specs and ask for your approval before implementing

When **disabled** (default), Claude stops normally and waits for your input.

## Notes

- Polling is **OFF by default** - must be explicitly enabled each session
- Polling timeout is 3 hours, then Claude stops normally
- You can interrupt polling anytime by typing anything
- Use `/create-spec` from another agent to send work to this one
