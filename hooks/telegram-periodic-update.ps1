# Claude Code Periodic Update Script
# Sends status updates to Telegram at configured intervals
# Only sends if user is idle (no keyboard/mouse activity)
# Run this in background: Start-Job -FilePath ~/.claude/hooks/telegram-periodic-update.ps1

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

$configPath = "$env:USERPROFILE\.claude\hooks\telegram-config.json"

# Check if config exists
if (-not (Test-Path $configPath)) {
    Write-Error "Config not found at $configPath"
    exit 1
}

$config = Get-Content $configPath | ConvertFrom-Json
$botToken = $config.bot_token
$chatId = $config.chat_id
$intervalMinutes = if ($config.update_interval_minutes) { $config.update_interval_minutes } else { 30 }
$idleThresholdSeconds = if ($config.idle_threshold_seconds) { $config.idle_threshold_seconds } else { 180 }

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

function Get-ClaudeStatus {
    # Check if Claude Code is running
    $claudeProcess = Get-Process -Name "claude" -ErrorAction SilentlyContinue

    if ($claudeProcess) {
        # Try to get recent activity from stats-cache if available
        $statsPath = "$env:USERPROFILE\.claude\stats-cache.json"
        $status = "🟢 *Claude Code is running*"

        if (Test-Path $statsPath) {
            try {
                $stats = Get-Content $statsPath | ConvertFrom-Json
                $status += "`n`n📊 *Session Stats:*"
                if ($stats.tokens) {
                    $status += "`nTokens: $($stats.tokens)"
                }
                if ($stats.cost) {
                    $status += "`nCost: `$$([math]::Round($stats.cost, 4))"
                }
            } catch {}
        }

        return $status
    } else {
        return "⚪ *Claude Code is idle*`n`nNo active session detected."
    }
}

# Send initial notification
Send-TelegramMessage "📊 *Periodic Updates Started*`n`nYou'll receive status updates every $intervalMinutes minutes.`n`nSend /stop to this bot to pause updates."

# Main loop
while ($true) {
    Start-Sleep -Seconds ($intervalMinutes * 60)

    # Only send if user is idle
    $idleSeconds = [IdleTime]::GetIdleSeconds()
    if ($idleSeconds -lt $idleThresholdSeconds) {
        continue  # User is active, skip this update
    }

    $status = Get-ClaudeStatus
    $timestamp = Get-Date -Format "HH:mm"
    $idleMinutes = [math]::Floor($idleSeconds / 60)

    Send-TelegramMessage "$status`n`n⏰ Update at $timestamp`n🕐 Idle: $idleMinutes min"
}
