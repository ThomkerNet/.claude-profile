# Claude Code Telegram Notification Hook
# Sends notifications to Telegram when Claude needs input or completes tasks
# Only sends if user is idle (no keyboard/mouse activity)

param(
    [string]$Message = "",
    [string]$Type = "info"
)

# Get user idle time using Windows API
Add-Type @"
using System;
using System.Runtime.InteropServices;

public struct LASTINPUTINFO {
    public uint cbSize;
    public uint dwTime;
}

public class IdleTime {
    [DllImport("user32.dll")]
    public static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);

    public static int GetIdleSeconds() {
        LASTINPUTINFO lii = new LASTINPUTINFO();
        lii.cbSize = (uint)Marshal.SizeOf(typeof(LASTINPUTINFO));
        if (GetLastInputInfo(ref lii)) {
            return (Environment.TickCount - (int)lii.dwTime) / 1000;
        }
        return 0;
    }
}
"@

# Load config first to get idle threshold
$configPath = "$env:USERPROFILE\.claude\hooks\telegram-config.json"
if (-not (Test-Path $configPath)) {
    Write-Error "Telegram config not found. Please create $configPath with bot_token and chat_id"
    exit 1
}

$config = Get-Content $configPath | ConvertFrom-Json
$botToken = $config.bot_token
$chatId = $config.chat_id

# Check if user is idle (default: 3 minutes = 180 seconds)
$idleThresholdSeconds = if ($config.idle_threshold_seconds) { $config.idle_threshold_seconds } else { 180 }
$idleSeconds = [IdleTime]::GetIdleSeconds()

if ($idleSeconds -lt $idleThresholdSeconds) {
    # User is active, skip notification
    exit 0
}

if (-not $botToken -or -not $chatId) {
    Write-Error "Missing bot_token or chat_id in config"
    exit 1
}

# Read hook input from stdin if no message provided
if (-not $Message) {
    $input = [Console]::In.ReadToEnd()
    if ($input) {
        try {
            $hookData = $input | ConvertFrom-Json

            # Format message based on hook type
            $hookType = $hookData.hook_type
            $sessionId = $hookData.session_id

            switch ($hookType) {
                "Stop" {
                    $stopReason = $hookData.stop_hook_data.stop_reason
                    $transcriptPath = $hookData.stop_hook_data.transcript_path

                    switch ($stopReason) {
                        "user_input_needed" {
                            $Message = "🔔 *Claude needs your input*`n`nSession: ``$sessionId```n`nClaude is waiting for your decision or response."
                            $Type = "decision"
                        }
                        "end_turn" {
                            $Message = "✅ *Claude completed a task*`n`nSession: ``$sessionId```n`nClaude finished processing and is ready for next instructions."
                            $Type = "complete"
                        }
                        "interrupt" {
                            $Message = "⏸️ *Claude was interrupted*`n`nSession: ``$sessionId``"
                            $Type = "info"
                        }
                        default {
                            $Message = "ℹ️ *Claude stopped*`n`nReason: $stopReason`nSession: ``$sessionId``"
                            $Type = "info"
                        }
                    }
                }
                "PreToolUse" {
                    $toolName = $hookData.pre_tool_use_hook_data.tool_name
                    # Only notify for sensitive tools if configured
                    if ($config.notify_on_tools -and $config.notify_on_tools -contains $toolName) {
                        $Message = "🔧 *Tool requires attention*`n`nTool: ``$toolName```nSession: ``$sessionId``"
                        $Type = "decision"
                    } else {
                        exit 0  # Skip notification
                    }
                }
                default {
                    $Message = "ℹ️ *Claude Code Event*`n`nHook: $hookType`nSession: ``$sessionId``"
                    $Type = "info"
                }
            }
        } catch {
            $Message = "⚠️ *Claude Code notification*`n`nRaw: $input"
            $Type = "info"
        }
    }
}

if (-not $Message) {
    exit 0
}

# Add emoji based on type if not already present
if ($Message -notmatch "^[🔔✅⏸️ℹ️⚠️🔧💬📊]") {
    switch ($Type) {
        "decision" { $Message = "🔔 $Message" }
        "complete" { $Message = "✅ $Message" }
        "update"   { $Message = "📊 $Message" }
        default    { $Message = "ℹ️ $Message" }
    }
}

# Send to Telegram
$uri = "https://api.telegram.org/bot$botToken/sendMessage"
$body = @{
    chat_id = $chatId
    text = $Message
    parse_mode = "Markdown"
}

try {
    $response = Invoke-RestMethod -Uri $uri -Method Post -Body $body -ContentType "application/x-www-form-urlencoded"
    if ($response.ok) {
        Write-Host "Notification sent"
    } else {
        Write-Error "Telegram API error: $($response.description)"
    }
} catch {
    Write-Error "Failed to send Telegram notification: $_"
}
