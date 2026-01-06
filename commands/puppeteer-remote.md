---
description: Set up Chrome in debug mode for Puppeteer control. Supports local visible browser or remote machine setup.
---

# Remote Puppeteer Setup

Set up Chrome in remote debugging mode for Puppeteer control.

## Setup Types

Ask the user which setup they need:

1. **Local Visible** - Launch Chrome visibly on THIS machine (watch Claude control it)
2. **Local Headless** - Run headless Chrome on THIS machine (SSH session, no display)
3. **Remote Machine** - Control Chrome on a different machine (Windows/Mac/Linux)

---

## Local Visible

### Mac
```bash
/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome --remote-debugging-port=9222 --user-data-dir="/tmp/chrome-puppeteer" &
```

### Windows (PowerShell)
```powershell
& "C:\Program Files\Google\Chrome\Application\chrome.exe" --remote-debugging-port=9222 --user-data-dir="$env:TEMP\chrome-puppeteer"
```

### Linux
```bash
google-chrome --remote-debugging-port=9222 --user-data-dir="/tmp/chrome-puppeteer" &
```

### Verify
```bash
curl http://localhost:9222/json/version
```

---

## Local Headless (SSH Sessions)

### Linux
```bash
google-chrome --headless=new --no-sandbox --disable-gpu --remote-debugging-port=9222 --user-data-dir="/tmp/chrome-puppeteer" &
```

### Mac
```bash
/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome --headless=new --disable-gpu --remote-debugging-port=9222 --user-data-dir="/tmp/chrome-puppeteer" &
```

---

## Remote Machine

> **SECURITY WARNING:** Remote debugging exposes FULL browser control to anyone who can reach port 9222. Use SSH tunnel or restrict firewall.

### Recommended: SSH Tunnel
On remote: Start Chrome normally (localhost only)
On local: `ssh -L 9222:localhost:9222 user@remote-host -N &`

### Direct (less secure)
Add `--remote-debugging-address=0.0.0.0` to Chrome command, then configure MCP with `PUPPETEER_BROWSER_WS_ENDPOINT`.

---

## Cleanup
```bash
pkill -f "chrome-puppeteer"  # Mac/Linux
```

See full docs: Load the `puppeteer-remote` skill for complete instructions.
