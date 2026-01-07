---
name: puppeteer-remote
description: Set up Chrome in debug mode for Puppeteer control. Supports local visible browser or remote machine setup.
---

# Puppeteer Browser Setup

This skill helps launch Chrome in remote debugging mode for Puppeteer control.

## Step 1: Determine Setup Type

Use AskUserQuestion to ask:

**Question:** What type of Puppeteer setup do you need?

**Options:**
- **Local Visible** - Launch Chrome visibly on THIS machine (see what Claude does)
- **Local Headless** - Run headless Chrome on THIS machine (SSH session, no display)
- **Remote Machine** - Control Chrome on a different machine (Windows/Mac/Linux)

---

## Local Visible Browser (Recommended)

For watching Claude control the browser in real-time on the current machine.

### Mac
```bash
/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome --remote-debugging-port=9222 --user-data-dir="/tmp/chrome-puppeteer" &
```

### Windows (PowerShell)
```powershell
& "C:\Program Files\Google\Chrome\Application\chrome.exe" --remote-debugging-port=9222 --user-data-dir="$env:TEMP\chrome-puppeteer"
```

**Alternative paths if Chrome not found:**
```powershell
# Try x86 path
& "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe" --remote-debugging-port=9222 --user-data-dir="$env:TEMP\chrome-puppeteer"
# Or user install
& "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe" --remote-debugging-port=9222 --user-data-dir="$env:TEMP\chrome-puppeteer"
```

### Linux
```bash
google-chrome --remote-debugging-port=9222 --user-data-dir="/tmp/chrome-puppeteer" &
# Or if using Chromium:
chromium-browser --remote-debugging-port=9222 --user-data-dir="/tmp/chrome-puppeteer" &
```

### Verify It's Running
```bash
curl http://localhost:9222/json/version
```

The Puppeteer MCP will automatically connect to port 9222 if a debug Chrome is already running.

---

## Local Headless Browser (SSH Sessions)

For running Chrome headlessly when SSH'd into a server or VM with no display.

### Linux (most common)
```bash
google-chrome --headless=new --no-sandbox --disable-gpu \
  --remote-debugging-port=9222 \
  --user-data-dir="/tmp/chrome-puppeteer" &

# Or Chromium
chromium-browser --headless=new --no-sandbox --disable-gpu \
  --remote-debugging-port=9222 \
  --user-data-dir="/tmp/chrome-puppeteer" &
```

### Mac (SSH'd in)
```bash
/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome \
  --headless=new --disable-gpu \
  --remote-debugging-port=9222 \
  --user-data-dir="/tmp/chrome-puppeteer" &
```

### Verify It's Running
```bash
curl http://localhost:9222/json/version
```

**Notes:**
- `--headless=new` uses Chrome's new headless mode (more compatible than old `--headless`)
- `--no-sandbox` often required when running as root or in containers
- `--disable-gpu` avoids GPU errors in headless environments
- Puppeteer MCP connects to `localhost:9222` automatically

---

## Remote Machine Setup

> **SECURITY WARNING:** Remote debugging exposes FULL browser control (read files, execute JS, access cookies) to anyone who can reach port 9222. This is effectively **remote code execution**. Only use on trusted private networks or via SSH tunnel.

### Option A: SSH Tunnel (Recommended - Secure)

This keeps port 9222 local on the remote machine and tunnels it securely.

**On remote machine** - Start Chrome bound to localhost only:
```bash
# Mac/Linux
google-chrome --remote-debugging-port=9222 --user-data-dir="/tmp/chrome-puppeteer" &

# Windows PowerShell
& "C:\Program Files\Google\Chrome\Application\chrome.exe" --remote-debugging-port=9222 --user-data-dir="$env:TEMP\chrome-puppeteer"
```

**On Claude's machine** - Create SSH tunnel:
```bash
ssh -L 9222:localhost:9222 user@remote-host -N &
```

Then Puppeteer connects to `localhost:9222` as if local.

### Option B: Port Forwarding (Less Secure)

> **Note:** Chrome removed `--remote-debugging-address=0.0.0.0` for security reasons in recent versions. Use port forwarding instead.

Only for isolated/trusted networks.

**On remote machine - Start Chrome normally (localhost):**
```bash
# Mac/Linux
google-chrome --remote-debugging-port=9222 --user-data-dir="/tmp/chrome-puppeteer" &

# Windows PowerShell
& "C:\Program Files\Google\Chrome\Application\chrome.exe" --remote-debugging-port=9222 --user-data-dir="$env:TEMP\chrome-puppeteer"
```

**Then forward the port to 0.0.0.0:**

**Windows (netsh - run as Admin):**
```powershell
netsh interface portproxy add v4tov4 listenport=9222 listenaddress=0.0.0.0 connectport=9222 connectaddress=127.0.0.1
```

**Linux (socat):**
```bash
socat TCP-LISTEN:9223,fork,bind=0.0.0.0 TCP:127.0.0.1:9222 &
# Connect to port 9223 from remote
```

**To remove Windows port forwarding later:**
```powershell
netsh interface portproxy delete v4tov4 listenport=9222 listenaddress=0.0.0.0
```

**Get remote IP:**
```bash
# Mac
ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1

# Linux
hostname -I | awk '{print $1}'

# Windows PowerShell
(Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -notlike "*Loopback*" -and $_.IPAddress -notlike "169.*"}).IPAddress | Select-Object -First 1
```

**Firewall (restrict to Claude's IP only!):**
```powershell
# Windows - replace YOUR_CLAUDE_IP with actual IP
New-NetFirewallRule -DisplayName "Chrome Remote Debug" -Direction Inbound -Protocol TCP -LocalPort 9222 -RemoteAddress YOUR_CLAUDE_IP -Action Allow
```

### Why SSH Tunnel is Required

> **WARNING:** The standard `@modelcontextprotocol/server-puppeteer` does NOT support connecting to remote browsers. It only supports `PUPPETEER_LAUNCH_OPTIONS` for launching local browsers, not `browserWSEndpoint` for connecting to existing ones.

**Bottom line:** For remote Puppeteer control, use SSH tunnel to make the remote port appear local. The MCP will then connect to `localhost:9222` which tunnels to the remote Chrome.

---

## Workflow for This Skill

1. Ask user: Local Visible, Local Headless, or Remote?
2. If local visible: Display platform-specific command, verify with curl
3. If local headless: Display headless command with appropriate flags, verify with curl
4. If remote: Recommend SSH tunnel, show commands, get IP, show MCP config (with caveat)
5. Test with `curl http://<host>:9222/json/version`
6. Proceed with Puppeteer navigation

---

## Cleanup

Kill debug Chrome when done:

```bash
# Mac/Linux - find and kill by user-data-dir
pkill -f "chrome-puppeteer"

# Windows PowerShell
Get-Process chrome | Where-Object {$_.CommandLine -like "*chrome-puppeteer*"} | Stop-Process
```

Remove temp profile:
```bash
rm -rf /tmp/chrome-puppeteer          # Mac/Linux
Remove-Item -Recurse "$env:TEMP\chrome-puppeteer"  # Windows
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "Address already in use" | Another Chrome using port 9222. Kill it or use `--remote-debugging-port=9223` |
| Connection refused | Check Chrome is running with debug flag, check firewall |
| Chrome listening on 127.0.0.1 only | Chrome removed `--remote-debugging-address=0.0.0.0`. Use SSH tunnel or netsh port forwarding |
| Timeout from remote | Use SSH tunnel or port forwarding (netsh/socat). Check firewall allows port 9222 |
| Can't find Chrome | Run `which google-chrome` (Linux), `where chrome` (Win), check alternate paths above |
| MCP ignores remote config | Standard MCP doesn't support `browserWSEndpoint`. Use SSH tunnel instead |
| Zombie Chrome processes | Use cleanup commands above |

