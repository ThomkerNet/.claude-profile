#
# Claude Code Profile Installer (Windows)
#
# This script sets up a complete Claude Code environment including:
# - Settings and hooks
# - MCP servers
# - All dependencies
#
# Usage:
#   irm https://raw.githubusercontent.com/ample-engineer/.claude/main/install.ps1 | iex
# Or after cloning:
#   cd ~/.claude; .\install.ps1

$ErrorActionPreference = "Stop"

function Write-Info { param($msg) Write-Host "ℹ $msg" -ForegroundColor Blue }
function Write-Success { param($msg) Write-Host "✓ $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "⚠ $msg" -ForegroundColor Yellow }
function Write-Err { param($msg) Write-Host "✗ $msg" -ForegroundColor Red }

$ClaudeHome = "$env:USERPROFILE\.claude"
$RepoUrl = "https://github.com/ample-engineer/.claude.git"

Write-Host ""
Write-Host "╔════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     Claude Code Profile Installer          ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

Write-Info "Platform: Windows"

# Step 1: Prerequisites
Write-Host ""
Write-Host "── Step 1: Prerequisites ──" -ForegroundColor Cyan

# Check/Install Git
if (Get-Command git -ErrorAction SilentlyContinue) {
    Write-Success "Git installed: $(git --version)"
} else {
    Write-Info "Git not found. Attempting to install..."
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements
        # Refresh PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        if (Get-Command git -ErrorAction SilentlyContinue) {
            Write-Success "Git installed via winget"
        } else {
            Write-Err "Git installation failed. Please install manually from: https://git-scm.com/download/win"
            exit 1
        }
    } else {
        Write-Err "Git is not installed and winget is not available."
        Write-Info "Install Git from: https://git-scm.com/download/win"
        Write-Info "Or install winget (App Installer) from Microsoft Store"
        exit 1
    }
}

# Check/Install Node.js
if (Get-Command node -ErrorAction SilentlyContinue) {
    Write-Success "Node.js installed: $(node --version)"
} else {
    Write-Info "Node.js not found. Attempting to install..."
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget install --id OpenJS.NodeJS.LTS -e --source winget --accept-package-agreements --accept-source-agreements
        # Refresh PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        if (Get-Command node -ErrorAction SilentlyContinue) {
            Write-Success "Node.js installed via winget: $(node --version)"
        } else {
            Write-Warn "Node.js installation may require terminal restart"
            Write-Info "If npm commands fail, restart terminal and re-run this script"
        }
    } else {
        Write-Warn "Node.js not found and winget unavailable"
        Write-Info "Install from: https://nodejs.org/"
        Write-Info "MCP servers and CLI tools require Node.js"
    }
}

# Check/Install bun
$BunPath = $null
$BunPaths = @(
    "$env:USERPROFILE\.bun\bin\bun.exe",
    "$env:LOCALAPPDATA\bun\bin\bun.exe"
)

foreach ($path in $BunPaths) {
    if (Test-Path $path) {
        $BunPath = $path
        break
    }
}

if (-not $BunPath) {
    $BunCmd = Get-Command bun -ErrorAction SilentlyContinue
    if ($BunCmd) { $BunPath = $BunCmd.Source }
}

if (-not $BunPath) {
    Write-Info "Installing Bun..."
    try {
        irm https://bun.sh/install.ps1 | iex
        $BunPath = "$env:USERPROFILE\.bun\bin\bun.exe"
        Write-Success "Bun installed"
    } catch {
        Write-Err "Failed to install Bun: $_"
        exit 1
    }
} else {
    Write-Success "Bun installed: $BunPath"
}

# Check/Install Claude Code CLI
if (Get-Command claude -ErrorAction SilentlyContinue) {
    Write-Success "Claude Code CLI installed"
} else {
    Write-Info "Installing Claude Code CLI..."
    if (Get-Command npm -ErrorAction SilentlyContinue) {
        try {
            npm install -g @anthropic-ai/claude-code 2>$null
            # Refresh PATH
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
            if (Get-Command claude -ErrorAction SilentlyContinue) {
                Write-Success "Claude Code CLI installed"
            } else {
                Write-Warn "Claude Code CLI installed but not in PATH yet"
                Write-Info "Restart terminal and run 'claude' to verify"
            }
        } catch {
            Write-Warn "Could not auto-install Claude Code CLI: $_"
            Write-Info "Install manually: npm install -g @anthropic-ai/claude-code"
        }
    } else {
        Write-Warn "npm not available, skipping Claude CLI install"
        Write-Info "Install Node.js first, then: npm install -g @anthropic-ai/claude-code"
    }
}

# Check/Install Gemini CLI
if (Get-Command gemini -ErrorAction SilentlyContinue) {
    Write-Success "Gemini CLI installed"
} else {
    Write-Info "Installing Gemini CLI..."
    if (Get-Command npm -ErrorAction SilentlyContinue) {
        try {
            npm install -g @google/gemini-cli 2>$null
            if (Get-Command gemini -ErrorAction SilentlyContinue) {
                Write-Success "Gemini CLI installed"
                Write-Info "Run 'gemini' to login interactively on first use"
            } else {
                Write-Warn "Gemini CLI install may have failed"
                Write-Info "Try manually: npm install -g @google/gemini-cli"
            }
        } catch {
            Write-Warn "Could not install Gemini CLI: $_"
            Write-Info "Install manually: npm install -g @google/gemini-cli"
        }
    } else {
        Write-Warn "npm not found, skipping Gemini CLI install"
        Write-Info "Install Node.js first, then: npm install -g @google/gemini-cli"
    }
}

# Check/Install GitHub Copilot CLI (for terminal assistance & GitHub operations)
$CopilotInstalled = $false
if (Get-Command copilot -ErrorAction SilentlyContinue) {
    Write-Success "GitHub Copilot CLI installed"
    $CopilotInstalled = $true
} else {
    Write-Info "Installing GitHub Copilot CLI..."
    # Try winget first (preferred on Windows)
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        try {
            winget install --id GitHub.Copilot -e --source winget --accept-package-agreements --accept-source-agreements 2>$null
            # Refresh PATH
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
            if (Get-Command copilot -ErrorAction SilentlyContinue) {
                Write-Success "GitHub Copilot CLI installed via winget"
                $CopilotInstalled = $true
            }
        } catch {
            Write-Warn "winget install failed, trying npm..."
        }
    }

    # Fall back to npm
    if (-not $CopilotInstalled -and (Get-Command npm -ErrorAction SilentlyContinue)) {
        try {
            npm install -g @github/copilot 2>$null
            # Refresh PATH
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
            if (Get-Command copilot -ErrorAction SilentlyContinue) {
                Write-Success "GitHub Copilot CLI installed via npm"
                $CopilotInstalled = $true
            } else {
                Write-Warn "GitHub Copilot CLI installed but not in PATH yet (restart terminal)"
                $CopilotInstalled = $true
            }
        } catch {
            Write-Warn "Could not install GitHub Copilot CLI: $_"
            Write-Info "Install manually: winget install GitHub.Copilot"
            Write-Info "  or: npm install -g @github/copilot"
            Write-Info "Requires GitHub Copilot Pro subscription"
        }
    } elseif (-not $CopilotInstalled) {
        Write-Warn "winget and npm not available, skipping GitHub Copilot CLI install"
        Write-Info "Install manually: winget install GitHub.Copilot"
    }
}

# Check/Install Bitwarden CLI (for Vaultwarden)
$BwInstalled = $false
if (Get-Command bw -ErrorAction SilentlyContinue) {
    Write-Success "Bitwarden CLI installed"
    $BwInstalled = $true
} else {
    Write-Info "Installing Bitwarden CLI..."
    if (Get-Command npm -ErrorAction SilentlyContinue) {
        try {
            npm install -g @bitwarden/cli 2>$null
            # Refresh PATH
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
            if (Get-Command bw -ErrorAction SilentlyContinue) {
                Write-Success "Bitwarden CLI installed"
                $BwInstalled = $true
            } else {
                Write-Warn "Bitwarden CLI install may have failed"
                Write-Info "Try manually: npm install -g @bitwarden/cli"
            }
        } catch {
            Write-Warn "Could not install Bitwarden CLI: $_"
            Write-Info "Install manually: npm install -g @bitwarden/cli"
        }
    } else {
        Write-Warn "npm not found, skipping Bitwarden CLI install"
    }
}

# Configure Bitwarden for Vaultwarden server
if ($BwInstalled) {
    $VaultwardenServer = "https://vaultwarden.thomker.net"
    Write-Info "Configuring Bitwarden for Vaultwarden..."
    try {
        & bw config server $VaultwardenServer 2>$null
        Write-Success "Bitwarden configured for $VaultwardenServer"
    } catch {
        Write-Warn "Could not configure Bitwarden server (may already be set)"
    }
}

# Step 2: Clone or Update Repository
Write-Host ""
Write-Host "── Step 2: Repository ──" -ForegroundColor Cyan

if (Test-Path "$ClaudeHome\.git") {
    Write-Info "Existing repo found, updating..."
    Push-Location $ClaudeHome
    try {
        git pull --rebase 2>$null
        Write-Success "Repository updated"
    } catch {
        Write-Warn "Git pull failed, continuing with existing files"
    }
    Pop-Location
} else {
    if (Test-Path $ClaudeHome) {
        $BackupPath = "$env:USERPROFILE\.claude.backup.$(Get-Date -Format 'yyyyMMddHHmmss')"
        Write-Info "Backing up existing ~/.claude to $BackupPath"
        Move-Item $ClaudeHome $BackupPath
    }
    Write-Info "Cloning repository..."
    git clone $RepoUrl $ClaudeHome
    Write-Success "Repository cloned"
}

Set-Location $ClaudeHome

# Step 3: Generate settings.json
Write-Host ""
Write-Host "── Step 3: Configuration ──" -ForegroundColor Cyan

$BunPathForward = $BunPath -replace '\\', '/'
$ClaudeHomeForward = $ClaudeHome -replace '\\', '/'

if (Test-Path "settings.template.json") {
    Write-Info "Generating settings.json..."
    $template = Get-Content "settings.template.json" -Raw
    $settings = $template -replace '\{\{BUN_PATH\}\}', $BunPathForward
    $settings = $settings -replace '\{\{CLAUDE_HOME\}\}', $ClaudeHomeForward
    $settings | Set-Content "settings.json" -Encoding UTF8
    Write-Success "settings.json generated"
}

# Step 4: Generate slash commands from templates
Write-Info "Generating slash commands..."

if (-not (Test-Path "commands")) { New-Item -ItemType Directory -Path "commands" | Out-Null }

# Generate from templates
$templates = @("vault")
foreach ($name in $templates) {
    $templatePath = "commands/$name.template.md"
    if (Test-Path $templatePath) {
        $content = Get-Content $templatePath -Raw
        $content = $content -replace '\{\{BUN_PATH\}\}', $BunPathForward
        $content = $content -replace '\{\{CLAUDE_HOME\}\}', $ClaudeHomeForward
        $content | Set-Content "commands/$name.md" -Encoding UTF8
    }
}

Write-Success "Slash commands generated"

# Step 5: Apply secrets from repo
Write-Host ""
Write-Host "── Step 5: Secrets ──" -ForegroundColor Cyan

$SecretsPath = "$ClaudeHome\secrets.json"
if (Test-Path $SecretsPath) {
    Write-Info "Applying secrets from secrets.json..."
    try {
        $secrets = Get-Content $SecretsPath -Raw | ConvertFrom-Json

        # Set Firecrawl API key as environment variable
        if ($secrets.api_keys.firecrawl -and $secrets.api_keys.firecrawl -ne "YOUR_FIRECRAWL_API_KEY") {
            Write-Info "Setting Firecrawl API key..."
            [System.Environment]::SetEnvironmentVariable('FIRECRAWL_API_KEY', $secrets.api_keys.firecrawl, 'User')
            Write-Success "Firecrawl API key set as user environment variable"
        }

        # Set LiteLLM config as environment variables
        if ($secrets.litellm.base_url) {
            [System.Environment]::SetEnvironmentVariable('LITELLM_BASE_URL', $secrets.litellm.base_url, 'User')
            Write-Success "LiteLLM base URL set"
        }
        if ($secrets.litellm.api_key) {
            [System.Environment]::SetEnvironmentVariable('LITELLM_API_KEY', $secrets.litellm.api_key, 'User')
            Write-Success "LiteLLM API key set"
        }

        Write-Success "Secrets applied"
    } catch {
        Write-Warn "Could not parse secrets.json: $_"
    }
} else {
    Write-Info "No secrets.json found - copy secrets.template.json to secrets.json and fill in values"
}

# Step 6: Install MCP Servers
Write-Host ""
Write-Host "── Step 6: MCP Servers ──" -ForegroundColor Cyan

$claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
if ($claudeCmd -and (Test-Path "mcp-servers.json")) {
    Write-Info "Installing MCP servers..."

    $mcpConfig = Get-Content "mcp-servers.json" -Raw | ConvertFrom-Json

    foreach ($server in $mcpConfig.servers) {
        Write-Info "  Adding MCP server: $($server.name)"
        try {
            $cmd = $server.command
            # Build environment variable arguments if present
            $envArgs = @()
            if ($server.env) {
                foreach ($key in $server.env.PSObject.Properties.Name) {
                    $value = $server.env.$key
                    $envArgs += "-e"
                    $envArgs += "$key=$value"
                }
            }
            if ($envArgs.Count -gt 0) {
                & claude mcp add $server.name --transport stdio -s user @envArgs -- $cmd 2>$null
            } else {
                & claude mcp add $server.name --transport stdio -s user -- $cmd 2>$null
            }
        } catch {
            Write-Warn "  Failed to add $($server.name) (may already exist)"
        }
    }
    Write-Success "MCP servers configured"
} else {
    Write-Warn "Claude CLI not found or mcp-servers.json missing, skipping MCP setup"
    Write-Info "Manually add MCP servers with:"
    Write-Host "  claude mcp add context7 --transport stdio -s user -- cmd /c npx -y @upstash/context7-mcp"
    Write-Host "  claude mcp add puppeteer --transport stdio -s user -- cmd /c npx -y @modelcontextprotocol/server-puppeteer"
    Write-Host "  claude mcp add firecrawl --transport stdio -s user -- cmd /c npx -y firecrawl-mcp"
    Write-Host "  claude mcp add sequential-thinking --transport stdio -s user -- cmd /c npx -y @modelcontextprotocol/server-sequential-thinking"
}

# Step 7: Environment hints
Write-Host ""
Write-Host "── Step 7: Environment Variables ──" -ForegroundColor Cyan

Write-Info "The following environment variables may be needed:"
Write-Host "  FIRECRAWL_API_KEY   - For Firecrawl MCP server"
Write-Host ""
Write-Info "Set via: [System.Environment]::SetEnvironmentVariable('VAR', 'value', 'User')"

# Step 8: Gemini & Copilot login reminders
Write-Host ""
Write-Host "── Step 8: AI CLI Logins ──" -ForegroundColor Cyan

if (Get-Command gemini -ErrorAction SilentlyContinue) {
    Write-Info "Gemini CLI needs interactive login. Run:"
    Write-Host "    gemini"
    Write-Host "  and follow the prompts to authenticate with Google."
}

if ($CopilotInstalled) {
    Write-Host ""
    Write-Info "GitHub Copilot CLI needs GitHub authentication. Run:"
    Write-Host "    copilot"
    Write-Host "  and follow the prompts to login with your GitHub account."
    Write-Host "  (Requires GitHub Copilot Pro subscription)"
}

# Done!
Write-Host ""
Write-Host "╔════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║           Installation Complete!           ║" -ForegroundColor Green
Write-Host "╚════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Success "Claude Code profile installed to: $ClaudeHome"
Write-Host ""
Write-Info "Next steps:"
Write-Host "  1. Restart your terminal (to load new PATH/env vars)"
Write-Host "  2. Run 'claude' to start Claude Code"
Write-Host "  3. Run 'gemini' to login to Gemini (for second opinions)"
if ($CopilotInstalled) {
    Write-Host "  4. Run 'copilot' to login to GitHub Copilot (for terminal help)"
}
if ($BwInstalled) {
    Write-Host ""
    Write-Host "  Vaultwarden setup (one-time):"
    Write-Host "     bw login"
    Write-Host "     bw unlock"
    Write-Host "  Then use /vault in Claude to access credentials"
}
Write-Host ""
