# Message Queue Module
# Handles message queuing between Telegram and Claude sessions

$script:QueueDir = "$env:USERPROFILE\.claude\hooks\telegram\queues"

function Initialize-Queue {
    if (-not (Test-Path $script:QueueDir)) {
        New-Item -ItemType Directory -Path $script:QueueDir -Force | Out-Null
    }
}

function Get-QueuePath {
    param([string]$SessionId)
    return Join-Path $script:QueueDir "$SessionId.json"
}

function Get-Queue {
    param([string]$SessionId)

    Initialize-Queue
    $path = Get-QueuePath $SessionId

    if (Test-Path $path) {
        return Get-Content $path | ConvertFrom-Json
    }

    return @{
        session_id = $SessionId
        messages = @()
        pending_question = $null
    }
}

function Save-Queue {
    param(
        [string]$SessionId,
        $Queue
    )

    Initialize-Queue
    $path = Get-QueuePath $SessionId
    $Queue | ConvertTo-Json -Depth 10 | Set-Content $path
}

function Add-Message {
    param(
        [string]$SessionId,
        [string]$Text,
        [string]$From = "user"
    )

    $queue = Get-Queue $SessionId

    $message = @{
        id = [guid]::NewGuid().ToString()
        text = $Text
        from = $From
        timestamp = (Get-Date).ToString("o")
        read = $false
    }

    $messages = @($queue.messages) + $message
    $queue.messages = $messages

    Save-Queue $SessionId $queue
    return $message
}

function Get-UnreadMessages {
    param([string]$SessionId)

    $queue = Get-Queue $SessionId
    return @($queue.messages | Where-Object { $_.read -eq $false -and $_.from -eq "user" })
}

function Mark-MessagesRead {
    param([string]$SessionId)

    $queue = Get-Queue $SessionId

    foreach ($msg in $queue.messages) {
        $msg.read = $true
    }

    Save-Queue $SessionId $queue
}

function Set-PendingQuestion {
    param(
        [string]$SessionId,
        [string]$Question,
        [string]$QuestionId = $null
    )

    $queue = Get-Queue $SessionId

    $queue.pending_question = @{
        id = if ($QuestionId) { $QuestionId } else { [guid]::NewGuid().ToString() }
        text = $Question
        asked_at = (Get-Date).ToString("o")
        answered = $false
        answer = $null
    }

    Save-Queue $SessionId $queue
    return $queue.pending_question.id
}

function Get-PendingQuestion {
    param([string]$SessionId)

    $queue = Get-Queue $SessionId
    return $queue.pending_question
}

function Set-QuestionAnswer {
    param(
        [string]$SessionId,
        [string]$Answer
    )

    $queue = Get-Queue $SessionId

    if ($queue.pending_question) {
        $queue.pending_question.answered = $true
        $queue.pending_question.answer = $Answer
        $queue.pending_question.answered_at = (Get-Date).ToString("o")
        Save-Queue $SessionId $queue
        return $true
    }

    return $false
}

function Clear-PendingQuestion {
    param([string]$SessionId)

    $queue = Get-Queue $SessionId
    $queue.pending_question = $null
    Save-Queue $SessionId $queue
}

function Get-Answer {
    param(
        [string]$SessionId,
        [int]$TimeoutSeconds = 300,
        [int]$PollIntervalSeconds = 2
    )

    $elapsed = 0

    while ($elapsed -lt $TimeoutSeconds) {
        $queue = Get-Queue $SessionId

        if ($queue.pending_question -and $queue.pending_question.answered) {
            $answer = $queue.pending_question.answer
            Clear-PendingQuestion $SessionId
            return $answer
        }

        Start-Sleep -Seconds $PollIntervalSeconds
        $elapsed += $PollIntervalSeconds
    }

    # Timeout
    Clear-PendingQuestion $SessionId
    return $null
}

# Export functions
Export-ModuleMember -Function @(
    'Initialize-Queue',
    'Add-Message',
    'Get-UnreadMessages',
    'Mark-MessagesRead',
    'Set-PendingQuestion',
    'Get-PendingQuestion',
    'Set-QuestionAnswer',
    'Clear-PendingQuestion',
    'Get-Answer'
)
