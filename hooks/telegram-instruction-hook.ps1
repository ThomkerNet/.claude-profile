# Telegram Instruction Hook
# Checks for pending instructions from Telegram and outputs them
# This hook runs on Notification events to periodically check the queue

$queueDir = "$env:USERPROFILE\.claude\hooks\telegram\queues"
$registryPath = "$env:USERPROFILE\.claude\hooks\telegram\sessions.json"

# Find current/default session
$sessionId = $null

if (Test-Path $registryPath) {
    $registry = Get-Content $registryPath | ConvertFrom-Json
    $sessionId = $registry.default_session
}

if (-not $sessionId) {
    exit 0
}

$queuePath = Join-Path $queueDir "$sessionId.json"

if (-not (Test-Path $queuePath)) {
    exit 0
}

$queue = Get-Content $queuePath | ConvertFrom-Json

# Check for pending instructions
if ($queue.instructions) {
    $pending = @($queue.instructions | Where-Object { -not $_.acknowledged })

    if ($pending.Count -gt 0) {
        # Mark as acknowledged so we don't repeat
        foreach ($instr in $queue.instructions) {
            $instr.acknowledged = $true
        }
        $queue | ConvertTo-Json -Depth 10 | Set-Content $queuePath

        # Output instruction text for Claude to see
        # This gets injected into the conversation via the hook output
        $instructionTexts = $pending | ForEach-Object { $_.text }
        $combined = $instructionTexts -join "`n"

        Write-Output "TELEGRAM_INSTRUCTION:$combined"
    }
}
