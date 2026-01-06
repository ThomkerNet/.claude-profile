# Telegram Listener
# Background service that polls for Telegram messages and routes them to session queues
# Run as: Start-Job -FilePath ~/.claude/hooks/telegram/telegram-listener.ps1

$ErrorActionPreference = "Continue"

# Load config
$configPath = "$env:USERPROFILE\.claude\hooks\telegram-config.json"
if (-not (Test-Path $configPath)) {
    Write-Error "Config not found at $configPath"
    exit 1
}

$config = Get-Content $configPath | ConvertFrom-Json
$botToken = $config.bot_token
$chatId = $config.chat_id

# Paths
$registryPath = "$env:USERPROFILE\.claude\hooks\telegram\sessions.json"
$queueDir = "$env:USERPROFILE\.claude\hooks\telegram\queues"
$lastUpdateFile = "$env:USERPROFILE\.claude\hooks\telegram\last_update_id.txt"

# Ensure directories exist
if (-not (Test-Path $queueDir)) {
    New-Item -ItemType Directory -Path $queueDir -Force | Out-Null
}

function Get-Registry {
    if (Test-Path $registryPath) {
        return Get-Content $registryPath | ConvertFrom-Json
    }
    return @{ sessions = @{}; default_session = $null; paused = $false }
}

function Send-TelegramMessage {
    param([string]$Text)

    $uri = "https://api.telegram.org/bot$botToken/sendMessage"
    $body = @{
        chat_id = $chatId
        text = $Text
        parse_mode = "Markdown"
    }

    try {
        Invoke-RestMethod -Uri $uri -Method Post -Body $body -ContentType "application/x-www-form-urlencoded" | Out-Null
    } catch {
        Write-Error "Failed to send: $_"
    }
}

function Get-LastUpdateId {
    if (Test-Path $lastUpdateFile) {
        return [int](Get-Content $lastUpdateFile)
    }
    return 0
}

function Set-LastUpdateId {
    param([int]$UpdateId)
    $UpdateId | Set-Content $lastUpdateFile
}

function Add-ToQueue {
    param(
        [string]$SessionId,
        [string]$Text,
        [switch]$IsInstruction
    )

    $queuePath = Join-Path $queueDir "$SessionId.json"

    if (Test-Path $queuePath) {
        $queue = Get-Content $queuePath | ConvertFrom-Json

        # Ensure instructions array exists
        if (-not $queue.instructions) {
            $queue | Add-Member -NotePropertyName "instructions" -NotePropertyValue @() -Force
        }

        if ($IsInstruction) {
            # Add as instruction for Claude to execute
            $instruction = @{
                id = [guid]::NewGuid().ToString()
                text = $Text
                received_at = (Get-Date).ToString("o")
                acknowledged = $false
            }
            $queue.instructions = @($queue.instructions) + $instruction
            Send-TelegramMessage "📨 Instruction queued for ``$SessionId``"
        }
        # Check if there's a pending question - if so, answer it
        elseif ($queue.pending_question -and -not $queue.pending_question.answered) {
            $queue.pending_question.answered = $true
            $queue.pending_question.answer = $Text
            $queue.pending_question.answered_at = (Get-Date).ToString("o")
        } else {
            # Add as regular message
            $message = @{
                id = [guid]::NewGuid().ToString()
                text = $Text
                from = "user"
                timestamp = (Get-Date).ToString("o")
                read = $false
            }
            $queue.messages = @($queue.messages) + $message
        }

        $queue | ConvertTo-Json -Depth 10 | Set-Content $queuePath
        return $true
    }
    return $false
}

function Handle-Command {
    param([string]$Command)

    $registry = Get-Registry

    switch -Regex ($Command) {
        "^/status$" {
            $sessions = @()
            foreach ($prop in $registry.sessions.PSObject.Properties) {
                $s = $prop.Value
                $isDefault = if ($prop.Name -eq $registry.default_session) { " *" } else { "" }
                $sessions += "``$($prop.Name)``$isDefault - $($s.description)"
            }

            if ($sessions.Count -eq 0) {
                Send-TelegramMessage "📋 *No active sessions*`n`nStart Claude Code to create a session."
            } else {
                $paused = if ($registry.paused) { "`n`n⏸️ Notifications paused" } else { "" }
                Send-TelegramMessage "📋 *Active Sessions:*`n`n$($sessions -join "`n")$paused`n`n_* = default session_"
            }
        }

        "^/switch\s+(\w+)$" {
            $targetSession = $Matches[1].ToUpper()
            if ($registry.sessions.PSObject.Properties.Name -contains $targetSession) {
                $registry.default_session = $targetSession
                $registry | ConvertTo-Json -Depth 10 | Set-Content $registryPath
                Send-TelegramMessage "✅ Switched to session ``$targetSession``"
            } else {
                Send-TelegramMessage "❌ Session ``$targetSession`` not found"
            }
        }

        "^/abort\s+(\w+)$" {
            $targetSession = $Matches[1].ToUpper()
            if ($registry.sessions.PSObject.Properties.Name -contains $targetSession) {
                # Mark session as aborted
                $registry.sessions.$targetSession.status = "aborted"
                $registry | ConvertTo-Json -Depth 10 | Set-Content $registryPath

                # Add abort message to queue
                Add-ToQueue $targetSession "ABORT_REQUESTED"

                Send-TelegramMessage "🛑 Abort signal sent to session ``$targetSession``"
            } else {
                Send-TelegramMessage "❌ Session ``$targetSession`` not found"
            }
        }

        "^/pause$" {
            $registry.paused = $true
            $registry | ConvertTo-Json -Depth 10 | Set-Content $registryPath
            Send-TelegramMessage "⏸️ Notifications paused. Send /resume to continue."
        }

        "^/resume$" {
            $registry.paused = $false
            $registry | ConvertTo-Json -Depth 10 | Set-Content $registryPath
            Send-TelegramMessage "▶️ Notifications resumed."
        }

        "^/tell\s+([A-Z0-9]{3})\s+(.+)$" {
            $targetSession = $Matches[1].ToUpper()
            $instruction = $Matches[2]
            if ($registry.sessions.PSObject.Properties.Name -contains $targetSession) {
                Add-ToQueue $targetSession $instruction -IsInstruction
            } else {
                Send-TelegramMessage "❌ Session ``$targetSession`` not found"
            }
        }

        "^/tell\s+(.+)$" {
            # No session specified, use default
            $instruction = $Matches[1]
            if ($registry.default_session) {
                Add-ToQueue $registry.default_session $instruction -IsInstruction
            } else {
                Send-TelegramMessage "❌ No default session. Use ``/tell ABC instruction``"
            }
        }

        "^/help$" {
            Send-TelegramMessage @"
🤖 *Claude Code Telegram Commands*

*Session Management:*
/status - List active sessions
/switch ABC - Switch default session
/abort ABC - Abort a session

*Instructions:*
/tell ABC do something - Send instruction to session
/tell do something - Send to default session
! do something - Shorthand for /tell

*Notifications:*
/pause - Pause all notifications
/resume - Resume notifications

*Replying to Claude:*
- Reply directly for default session
- Prefix with session ID: ``ABC: your reply``
"@
        }

        default {
            return $false  # Not a command
        }
    }
    return $true
}

function Parse-SessionMessage {
    param([string]$Text)

    # Check for session prefix like "ABC: message"
    if ($Text -match "^([A-Z0-9]{3}):\s*(.+)$") {
        return @{
            SessionId = $Matches[1]
            Message = $Matches[2]
        }
    }

    # No prefix - use default session
    $registry = Get-Registry
    if ($registry.default_session) {
        return @{
            SessionId = $registry.default_session
            Message = $Text
        }
    }

    return $null
}

# Main loop
Send-TelegramMessage "🟢 *Telegram Listener Started*`n`nSend /help for available commands."

$lastUpdateId = Get-LastUpdateId

while ($true) {
    try {
        $offset = $lastUpdateId + 1
        $uri = "https://api.telegram.org/bot$botToken/getUpdates?offset=$offset&timeout=30"

        $response = Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 35

        if ($response.ok -and $response.result) {
            foreach ($update in $response.result) {
                $lastUpdateId = $update.update_id
                Set-LastUpdateId $lastUpdateId

                # Only process messages from our chat
                if ($update.message -and $update.message.chat.id -eq [long]$chatId) {
                    $text = $update.message.text

                    if ($text) {
                        # Check if it's a command
                        if ($text.StartsWith("/")) {
                            $handled = Handle-Command $text
                            if (-not $handled) {
                                Send-TelegramMessage "❓ Unknown command. Send /help for options."
                            }
                        }
                        # Check for ! prefix (instruction shorthand)
                        elseif ($text -match "^!\s*(.+)$") {
                            $instruction = $Matches[1]
                            $registry = Get-Registry

                            # Check for session prefix: !ABC instruction
                            if ($instruction -match "^([A-Z0-9]{3})\s+(.+)$") {
                                $targetSession = $Matches[1]
                                $instrText = $Matches[2]
                                if ($registry.sessions.PSObject.Properties.Name -contains $targetSession) {
                                    Add-ToQueue $targetSession $instrText -IsInstruction
                                } else {
                                    Send-TelegramMessage "❌ Session ``$targetSession`` not found"
                                }
                            }
                            # Use default session
                            elseif ($registry.default_session) {
                                Add-ToQueue $registry.default_session $instruction -IsInstruction
                            } else {
                                Send-TelegramMessage "❌ No default session. Use ``!ABC instruction``"
                            }
                        } else {
                            # Regular message - route to session
                            $parsed = Parse-SessionMessage $text

                            if ($parsed) {
                                $added = Add-ToQueue $parsed.SessionId $parsed.Message
                                if (-not $added) {
                                    Send-TelegramMessage "❌ Session ``$($parsed.SessionId)`` not found or inactive"
                                }
                            } else {
                                Send-TelegramMessage "❓ No active session. Start Claude Code first or use /status to check."
                            }
                        }
                    }
                }
            }
        }
    } catch {
        Write-Error "Polling error: $_"
        Start-Sleep -Seconds 5
    }
}
