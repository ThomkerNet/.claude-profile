# Check Instructions Hook
# Called periodically to check for pending Telegram instructions
# Outputs instructions to stdout for Claude to process

param(
    [switch]$Acknowledge,
    [string]$InstructionId
)

$configPath = "$env:USERPROFILE\.claude\hooks\telegram-config.json"
$queueDir = "$env:USERPROFILE\.claude\hooks\telegram\queues"
$sessionIdFile = "$env:USERPROFILE\.claude\hooks\telegram\current_session_$PID.txt"

# Try to find current session
$sessionId = $null

# First check PID-specific file
if (Test-Path $sessionIdFile) {
    $sessionId = Get-Content $sessionIdFile
}

# If not found, check for any active session (fallback)
if (-not $sessionId) {
    $registryPath = "$env:USERPROFILE\.claude\hooks\telegram\sessions.json"
    if (Test-Path $registryPath) {
        $registry = Get-Content $registryPath | ConvertFrom-Json
        $sessionId = $registry.default_session
    }
}

if (-not $sessionId) {
    # No session, nothing to check
    exit 0
}

$queuePath = Join-Path $queueDir "$sessionId.json"

if (-not (Test-Path $queuePath)) {
    exit 0
}

$queue = Get-Content $queuePath | ConvertFrom-Json

# Handle acknowledgment
if ($Acknowledge -and $InstructionId) {
    if ($queue.instructions) {
        $queue.instructions = @($queue.instructions | Where-Object { $_.id -ne $InstructionId })
        $queue | ConvertTo-Json -Depth 10 | Set-Content $queuePath
    }
    exit 0
}

# Check for unacknowledged instructions
if ($queue.instructions) {
    $pending = @($queue.instructions | Where-Object { -not $_.acknowledged })

    if ($pending.Count -gt 0) {
        # Return instructions as JSON for Claude to parse
        $output = @{
            session_id = $sessionId
            instructions = $pending
        }
        $output | ConvertTo-Json -Depth 10
        exit 0
    }
}

# No pending instructions
exit 0
