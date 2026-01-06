# Google Workspace MCP Server Setup

## Overview

Provides Claude Code access to:
- **Gmail**: Read emails, search, send
- **Drive**: List, read, create files
- **Calendar**: View, create events
- **Docs/Sheets**: Read and edit

## Configuration

Added to `~/.claude/mcp-servers.json`:

```json
{
  "name": "google-workspace",
  "command": "uvx workspace-mcp --tool-tier core",
  "description": "Google Workspace: Gmail, Drive, Calendar, Docs",
  "env": {
    "GOOGLE_OAUTH_CLIENT_ID": "{{GOOGLE_OAUTH_CLIENT_ID}}",
    "GOOGLE_OAUTH_CLIENT_SECRET": "{{GOOGLE_OAUTH_CLIENT_SECRET}}",
    "USER_GOOGLE_EMAIL": "simon@boroughnexus.com",
    "OAUTHLIB_INSECURE_TRANSPORT": "1"
  }
}
```

## Setup Steps

### 1. Create Google Cloud Project

1. Go to https://console.cloud.google.com/projectcreate
2. Name: `borough-nexus-mcp`
3. Click **Create**

### 2. Enable APIs

Enable these APIs at https://console.cloud.google.com/apis/library:

- Gmail API
- Google Drive API
- Google Calendar API
- Google Docs API
- Google Sheets API

Or use direct links:
- https://console.cloud.google.com/apis/library/gmail.googleapis.com
- https://console.cloud.google.com/apis/library/drive.googleapis.com
- https://console.cloud.google.com/apis/library/calendar-json.googleapis.com
- https://console.cloud.google.com/apis/library/docs.googleapis.com
- https://console.cloud.google.com/apis/library/sheets.googleapis.com

### 3. Configure OAuth Consent Screen

1. Go to https://console.cloud.google.com/apis/credentials/consent
2. Select **Internal** (if using Google Workspace) or **External**
3. Fill in:
   - App name: `Claude Code MCP`
   - User support email: your email
   - Developer contact: your email
4. Click **Save and Continue**
5. Add scopes:
   - `https://www.googleapis.com/auth/gmail.readonly`
   - `https://www.googleapis.com/auth/gmail.send`
   - `https://www.googleapis.com/auth/drive`
   - `https://www.googleapis.com/auth/calendar`
   - `https://www.googleapis.com/auth/documents`
   - `https://www.googleapis.com/auth/spreadsheets`
6. Add test users (your email)

### 4. Create OAuth Credentials

1. Go to https://console.cloud.google.com/apis/credentials
2. Click **+ CREATE CREDENTIALS** → **OAuth client ID**
3. Application type: **Desktop app**
4. Name: `Claude Code MCP`
5. Click **Create**
6. Copy the **Client ID** and **Client Secret**

### 5. Store Credentials

Add to `~/.claude/secrets.json`:

```json
{
  "GOOGLE_OAUTH_CLIENT_ID": "your-client-id.apps.googleusercontent.com",
  "GOOGLE_OAUTH_CLIENT_SECRET": "your-client-secret"
}
```

Or export as environment variables:

```bash
export GOOGLE_OAUTH_CLIENT_ID="your-client-id.apps.googleusercontent.com"
export GOOGLE_OAUTH_CLIENT_SECRET="your-client-secret"
```

### 6. First Run Authentication

On first use, the MCP server will:
1. Open a browser for OAuth consent
2. Ask you to authorize access
3. Store tokens in `~/.credentials/` for future use

## Troubleshooting

### "Access blocked" error
- Add yourself as a test user in OAuth consent screen
- Or publish the app (if using External)

### "Invalid client" error
- Double-check Client ID and Secret
- Ensure no trailing whitespace

### Token refresh issues
- Delete `~/.credentials/` folder
- Re-authenticate

## Security Notes

- Never commit `secrets.json` or credentials to git
- `OAUTHLIB_INSECURE_TRANSPORT=1` is for local development only
- Tokens are stored locally in `~/.credentials/`

## Reference

- MCP Server: https://github.com/taylorwilsdon/google_workspace_mcp
- Google Cloud Console: https://console.cloud.google.com/
