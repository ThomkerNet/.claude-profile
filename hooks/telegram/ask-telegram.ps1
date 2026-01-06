# Ask Via Telegram
# Helper script for Claude to ask questions and get answers via Telegram
#
# Usage:
#   # Register session (run once at start)
#   .\ask-telegram.ps1 -Register -Description "Working on feature X"
#
#   # Ask a question and wait for answer
#   .\ask-telegram.ps1 -Ask "Should I proceed with option A or B?"
#
#   # Unregister session (run at end)
#   .\ask-telegram.ps1 -Unregister

param(
    [switch]$Register,
    [switch]$Unregister,
    [string]$Ask,
    [string]$Description = "Claude Code Session",
    [int]$Timeout = 300,
    [switch]$GetSessionId
)

$configPath = "$env:USERPROFILE\.claude\hooks\telegram-config.json"
$registryPath = "$env:USERPROFILE\.claude\hooks\telegram\sessions.json"
$queueDir = "$env:USERPROFILE\.claude\hooks\telegram\queues"
$sessionIdFile = "$env:USERPROFILE\.claude\hooks\telegram\current_session_$PID.txt"

# Load config
if (-not (Test-Path $configPath)) {
    Write-Error "Config not found at $configPath"
    exit 1
}

$config = Get-Content $configPath | ConvertFrom-Json
$botToken = $config.bot_token
$chatId = $config.chat_id

function Send-TelegramMessage {
    param([string]$Text)

    $encoded = [System.Web.HttpUtility]::UrlEncode($Text)
    $uri = "https://api.telegram.org/bot$botToken/sendMessage?chat_id=$chatId&text=$encoded&parse_mode=Markdown"

    try {
        $response = Invoke-RestMethod -Uri $uri -Method Get
        return $response.ok
    } catch {
        Write-Error "Failed to send: $_"
        return $false
    }
}

function Get-Registry {
    if (Test-Path $registryPath) {
        return Get-Content $registryPath | ConvertFrom-Json
    }
    return @{ sessions = @{}; default_session = $null; paused = $false }
}

function Save-Registry {
    param($Registry)
    $Registry | ConvertTo-Json -Depth 10 | Set-Content $registryPath
}

function New-SessionId {
    $chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    $id = ""
    for ($i = 0; $i -lt 3; $i++) {
        $id += $chars[(Get-Random -Maximum $chars.Length)]
    }
    return $id
}

function Get-CurrentSessionId {
    if (Test-Path $sessionIdFile) {
        return Get-Content $sessionIdFile
    }
    return $null
}

# Ensure queue directory exists
if (-not (Test-Path $queueDir)) {
    New-Item -ItemType Directory -Path $queueDir -Force | Out-Null
}

# Handle -GetSessionId
if ($GetSessionId) {
    $sid = Get-CurrentSessionId
    if ($sid) {
        Write-Output $sid
    }
    exit 0
}

# Handle -Register
if ($Register) {
    $registry = Get-Registry
    $sessionId = New-SessionId

    # Ensure unique
    while ($registry.sessions.PSObject.Properties.Name -contains $sessionId) {
        $sessionId = New-SessionId
    }

    $session = @{
        id = $sessionId
        description = $Description
        created = (Get-Date).ToString("o")
        last_activity = (Get-Date).ToString("o")
        status = "active"
        pid = $PID
    }

    # Add to registry
    if (-not $registry.sessions) {
        $registry | Add-Member -NotePropertyName "sessions" -NotePropertyValue @{} -Force
    }
    $registry.sessions | Add-Member -NotePropertyName $sessionId -NotePropertyValue $session -Force

    # Set as default
    $registry.default_session = $sessionId

    Save-Registry $registry

    # Create queue file
    $queuePath = Join-Path $queueDir "$sessionId.json"
    @{
        session_id = $sessionId
        messages = @()
        pending_question = $null
    } | ConvertTo-Json | Set-Content $queuePath

    # Save session ID for this process
    $sessionId | Set-Content $sessionIdFile

    # Notify via Telegram
    Send-TelegramMessage "🆕 *New Session Started*`n`nID: ``$sessionId```nDescription: $Description`n`n_This is now the default session._" | Out-Null

    Write-Output $sessionId
    exit 0
}

# Handle -Unregister
if ($Unregister) {
    $sessionId = Get-CurrentSessionId

    if ($sessionId) {
        $registry = Get-Registry

        if ($registry.sessions.PSObject.Properties.Name -contains $sessionId) {
            $registry.sessions.PSObject.Properties.Remove($sessionId)

            # Update default if needed
            if ($registry.default_session -eq $sessionId) {
                $remaining = $registry.sessions.PSObject.Properties.Name | Select-Object -First 1
                $registry.default_session = $remaining
            }

            Save-Registry $registry

            # Remove queue file
            $queuePath = Join-Path $queueDir "$sessionId.json"
            if (Test-Path $queuePath) {
                Remove-Item $queuePath -Force
            }
        }

        # Remove session ID file
        Remove-Item $sessionIdFile -Force -ErrorAction SilentlyContinue

        # Notify via Telegram
        Send-TelegramMessage "👋 *Session Ended*`n`nID: ``$sessionId``" | Out-Null

        Write-Output "Session $sessionId unregistered"
    } else {
        Write-Error "No active session for this process"
    }
    exit 0
}

# Handle -Ask
if ($Ask) {
    $sessionId = Get-CurrentSessionId

    if (-not $sessionId) {
        Write-Error "No active session. Run with -Register first."
        exit 1
    }

    $queuePath = Join-Path $queueDir "$sessionId.json"

    if (-not (Test-Path $queuePath)) {
        Write-Error "Queue not found for session $sessionId"
        exit 1
    }

    # Set pending question
    $queue = Get-Content $queuePath | ConvertFrom-Json
    $questionId = [guid]::NewGuid().ToString()

    $queue.pending_question = @{
        id = $questionId
        text = $Ask
        asked_at = (Get-Date).ToString("o")
        answered = $false
        answer = $null
    }

    $queue | ConvertTo-Json -Depth 10 | Set-Content $queuePath

    # Send question to Telegram
    Send-TelegramMessage "🔔 *[$sessionId] Claude needs your input*`n`n$Ask" | Out-Null

    # Poll for answer
    $elapsed = 0
    $pollInterval = 2

    while ($elapsed -lt $Timeout) {
        Start-Sleep -Seconds $pollInterval
        $elapsed += $pollInterval

        $queue = Get-Content $queuePath | ConvertFrom-Json

        if ($queue.pending_question -and $queue.pending_question.answered) {
            $answer = $queue.pending_question.answer

            # Clear pending question
            $queue.pending_question = $null
            $queue | ConvertTo-Json -Depth 10 | Set-Content $queuePath

            # Check for abort
            if ($answer -eq "ABORT_REQUESTED") {
                Write-Error "ABORT_REQUESTED"
                exit 2
            }

            Write-Output $answer
            exit 0
        }
    }

    # Timeout
    $queue.pending_question = $null
    $queue | ConvertTo-Json -Depth 10 | Set-Content $queuePath

    Send-TelegramMessage "⏰ *[$sessionId] Question timed out*`n`nNo response received." | Out-Null
    Write-Error "Timeout waiting for answer"
    exit 1
}

# No action specified
Write-Host @"
Usage:
  .\ask-telegram.ps1 -Register [-Description "desc"]  # Start session
  .\ask-telegram.ps1 -Ask "Question?"                 # Ask and wait
  .\ask-telegram.ps1 -Unregister                      # End session
  .\ask-telegram.ps1 -GetSessionId                    # Get current session ID
"@
