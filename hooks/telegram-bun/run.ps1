# Cross-platform wrapper for telegram-bun scripts (Windows)
# Usage: run.ps1 <script-name> [args...]
# Example: run.ps1 check.ts

param(
    [Parameter(Position=0, Mandatory=$true)]
    [string]$ScriptName,

    [Parameter(Position=1, ValueFromRemainingArguments=$true)]
    [string[]]$Args
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Find bun executable
$BunPaths = @(
    "$env:USERPROFILE\.bun\bin\bun.exe",
    "$env:LOCALAPPDATA\bun\bin\bun.exe",
    "C:\Program Files\bun\bun.exe"
)

$BunCmd = $null
foreach ($path in $BunPaths) {
    if (Test-Path $path) {
        $BunCmd = $path
        break
    }
}

# Try PATH as fallback
if (-not $BunCmd) {
    $BunCmd = Get-Command bun -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
}

if (-not $BunCmd) {
    Write-Error "Error: bun not found"
    exit 1
}

$FullScriptPath = Join-Path $ScriptDir $ScriptName
& $BunCmd run $FullScriptPath @Args
