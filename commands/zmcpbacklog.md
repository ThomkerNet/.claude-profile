# MCP Server Backlog Generator

> **Description:** Analyze session actions to identify MCP server improvement opportunities

## Usage

```bash
/zmcpbacklog              # Analyze current session, create GitHub issue
/zmcpbacklog --dry-run    # Show analysis without creating issue
```

## Purpose

Identifies actions taken during the session that should be implemented as MCP server tools for:

1. **Security segregation** - API keys/credentials managed by MCP server, not exposed to Claude
2. **Native capabilities** - Fast, pre-built tools instead of ad-hoc scripting
3. **Reusability** - Common patterns that could benefit other sessions

---

## What to Look For

### High Priority (Security)

Actions involving credentials or direct access:

| Pattern | MCP Opportunity |
|---------|-----------------|
| `curl` with API keys/tokens | New MCP server for that API |
| `ssh` commands | Remote execution MCP server |
| Reading secrets files | Secrets manager integration |
| `gh` CLI with auth | GitHub MCP server enhancement |
| Database connections | Database query MCP tools |
| Cloud CLI (`az`, `aws`, `gcloud`) | Cloud provider MCP servers |

### Medium Priority (Efficiency)

Complex multi-step operations:

| Pattern | MCP Opportunity |
|---------|-----------------|
| Repeated API call patterns | Dedicated endpoint tool |
| File + API combinations | Composite workflow tool |
| Parsing specific formats | Format-aware read tool |
| Multi-service orchestration | Orchestration tool |

### Lower Priority (Convenience)

Common utilities that could be faster:

| Pattern | MCP Opportunity |
|---------|-----------------|
| Repeated grep/glob patterns | Specialized search tool |
| Standard transformations | Transform utility tool |
| Status checking workflows | Health/status tool |

---

## Execution Steps

### Step 1: Analyze Session History

Review the conversation to identify:

1. **Direct API calls** - Any `curl`, `fetch`, or HTTP requests with auth
2. **Credential usage** - Reading from secrets, env vars, or credential files
3. **SSH/Remote access** - Direct shell access to remote systems
4. **CLI tools with auth** - `gh`, `az`, `aws`, `gcloud`, `kubectl`, etc.
5. **Multi-step patterns** - Repeated sequences that could be a single tool

### Step 2: Categorize Findings

For each finding, determine:

- **Service/API involved** - What external system was accessed
- **Credentials used** - What auth method was employed
- **Frequency** - One-off or repeated pattern
- **Complexity** - Simple wrapper vs complex logic
- **Existing MCP** - Does a TKNet MCP server already cover this?

### Step 3: Check Existing MCP Servers

Reference existing TKNet MCP servers to avoid duplicates:

```
tkn-cloudflare    - DNS/zones
tkn-unraid        - Unraid server management
tkn-aipeerreview  - AI code review
tkn-unifi         - Network management
tkn-portainer     - Docker/Portainer
tkn-tailscale     - VPN management
tkn-syncthing     - File sync
tkn-registry      - Docker registry
tkn-infisical     - Secrets management
```

### Step 4: Draft GitHub Issue

Create issue in `TKNet-MCPServer` repository:

```bash
gh issue create \
  --repo "ample-engineer/TKNet-MCPServer" \
  --title "MCP Backlog: <summary>" \
  --body "$(cat <<'EOF'
## Session Analysis

**Date:** YYYY-MM-DD
**Session context:** <what was being worked on>

## Identified MCP Opportunities

### 1. [Service/API Name]

**Current approach:** <how it was done in session>
**Security concern:** <credential exposure, direct access, etc.>
**Proposed MCP tool:**
- Tool name: `<tool_name>`
- Description: <what it does>
- Parameters: <input params>
- Returns: <output format>

**Priority:** High/Medium/Low
**Effort estimate:** Small/Medium/Large

### 2. [Next opportunity...]

...

## Implementation Notes

- <any technical considerations>
- <dependencies or prerequisites>
- <related existing tools>

## Labels

- `enhancement`
- `mcp-server`
- `security` (if credential-related)
EOF
)"
```

---

## Example Analysis

### Session: "Updating AI peer review models"

**Actions identified:**

1. **Web search for GitHub Copilot models**
   - Used: WebSearch tool (built-in)
   - MCP opportunity: None (already native)

2. **Fetching GitHub docs**
   - Used: WebFetch tool (built-in)
   - MCP opportunity: None (already native)

3. **No direct API/credential usage found**
   - Session used existing tools appropriately

**Result:** No new MCP backlog items for this session.

---

### Session: "Deploying to Azure"

**Actions identified:**

1. **Azure CLI commands with credentials**
   - Used: `az container app update --name X --resource-group Y`
   - Credential: Azure CLI auth (service principal)
   - MCP opportunity: `tkn-azure` MCP server
   - Priority: High (credential segregation)

2. **Reading deployment secrets**
   - Used: `Read ~/.azure/credentials`
   - MCP opportunity: Enhance `tkn-infisical` or dedicated Azure secrets

**GitHub Issue created:** `MCP Backlog: Azure Container Apps management`

---

## Output Format

```
🔍 Analyzing session for MCP opportunities...

📋 Session Summary:
   - Tools used: 15 Bash, 8 Read, 5 Edit, 2 WebFetch
   - External services: GitHub API, LiteLLM proxy
   - Credentials detected: None exposed directly

🎯 MCP Opportunities Found:

   1. ✅ Already covered: GitHub (use gh CLI via Bash)
   2. ✅ Already covered: LiteLLM (tkn-aipeerreview)
   3. ⚪ No new opportunities identified

📝 Result: No GitHub issue needed for this session.

---

OR if opportunities found:

🎯 MCP Opportunities Found:

   1. 🔴 HIGH: Azure Container Apps
      - Direct az CLI with service principal
      - Recommend: tkn-azure MCP server

   2. 🟡 MEDIUM: Custom webhook calls
      - Repeated curl pattern to internal API
      - Recommend: tkn-webhooks tool

📤 Creating GitHub issue...
   → Issue #42: "MCP Backlog: Azure + Webhooks"
   → URL: https://github.com/ample-engineer/TKNet-MCPServer/issues/42

✨ Done! Backlog items logged for future implementation.
```

---

## Notes

- Only create issues for genuine improvements, not every API call
- Group related opportunities into single issues
- Reference specific session context for implementation clarity
- Tag with appropriate labels for triage
