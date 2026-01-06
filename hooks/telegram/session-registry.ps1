# Session Registry Module
# Manages Claude Code session tracking for Telegram integration

$script:RegistryPath = "$env:USERPROFILE\.claude\hooks\telegram\sessions.json"
$script:QueueDir = "$env:USERPROFILE\.claude\hooks\telegram\queues"

function Initialize-Registry {
    if (-not (Test-Path $script:QueueDir)) {
        New-Item -ItemType Directory -Path $script:QueueDir -Force | Out-Null
    }
    if (-not (Test-Path $script:RegistryPath)) {
        @{
            sessions = @{}
            default_session = $null
            paused = $false
        } | ConvertTo-Json | Set-Content $script:RegistryPath
    }
}

function Get-Registry {
    Initialize-Registry
    Get-Content $script:RegistryPath | ConvertFrom-Json
}

function Save-Registry {
    param($Registry)
    $Registry | ConvertTo-Json -Depth 10 | Set-Content $script:RegistryPath
}

function New-SessionId {
    # Generate short 3-char ID (e.g., A3X)
    $chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    $id = ""
    for ($i = 0; $i -lt 3; $i++) {
        $id += $chars[(Get-Random -Maximum $chars.Length)]
    }
    return $id
}

function Register-Session {
    param(
        [string]$Description = "Claude Code Session"
    )

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
        $registry.sessions = @{}
    }
    $registry.sessions | Add-Member -NotePropertyName $sessionId -NotePropertyValue $session -Force

    # Set as default if first session
    if (-not $registry.default_session) {
        $registry.default_session = $sessionId
    }

    Save-Registry $registry

    # Create queue file
    $queuePath = Join-Path $script:QueueDir "$sessionId.json"
    @{
        session_id = $sessionId
        messages = @()
        pending_question = $null
    } | ConvertTo-Json | Set-Content $queuePath

    return $sessionId
}

function Unregister-Session {
    param([string]$SessionId)

    $registry = Get-Registry

    if ($registry.sessions.PSObject.Properties.Name -contains $SessionId) {
        $registry.sessions.PSObject.Properties.Remove($SessionId)

        # Update default if needed
        if ($registry.default_session -eq $SessionId) {
            $remaining = $registry.sessions.PSObject.Properties.Name | Select-Object -First 1
            $registry.default_session = $remaining
        }

        Save-Registry $registry

        # Remove queue file
        $queuePath = Join-Path $script:QueueDir "$SessionId.json"
        if (Test-Path $queuePath) {
            Remove-Item $queuePath -Force
        }
    }
}

function Get-ActiveSessions {
    $registry = Get-Registry
    $sessions = @()

    foreach ($prop in $registry.sessions.PSObject.Properties) {
        $session = $prop.Value
        $sessions += [PSCustomObject]@{
            Id = $prop.Name
            Description = $session.description
            Created = $session.created
            Status = $session.status
            IsDefault = ($prop.Name -eq $registry.default_session)
        }
    }

    return $sessions
}

function Set-DefaultSession {
    param([string]$SessionId)

    $registry = Get-Registry
    if ($registry.sessions.PSObject.Properties.Name -contains $SessionId) {
        $registry.default_session = $SessionId
        Save-Registry $registry
        return $true
    }
    return $false
}

function Get-DefaultSession {
    $registry = Get-Registry
    return $registry.default_session
}

function Set-Paused {
    param([bool]$Paused)

    $registry = Get-Registry
    $registry.paused = $Paused
    Save-Registry $registry
}

function Get-IsPaused {
    $registry = Get-Registry
    return $registry.paused -eq $true
}

function Update-SessionActivity {
    param([string]$SessionId)

    $registry = Get-Registry
    if ($registry.sessions.PSObject.Properties.Name -contains $SessionId) {
        $registry.sessions.$SessionId.last_activity = (Get-Date).ToString("o")
        Save-Registry $registry
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Initialize-Registry',
    'Register-Session',
    'Unregister-Session',
    'Get-ActiveSessions',
    'Set-DefaultSession',
    'Get-DefaultSession',
    'Set-Paused',
    'Get-IsPaused',
    'Update-SessionActivity',
    'New-SessionId'
)
