# Claude Profile Setup Script (Windows)
# Run this after cloning the .claude repo to configure for your system

$ErrorActionPreference = "Stop"

$ClaudeHome = "$env:USERPROFILE\.claude"
Set-Location $ClaudeHome

Write-Host "Setting up Claude profile..." -ForegroundColor Cyan

# Find bun
$BunPath = $null
$BunPaths = @(
    "$env:USERPROFILE\.bun\bin\bun.exe",
    "$env:LOCALAPPDATA\bun\bin\bun.exe",
    "C:\Program Files\bun\bun.exe"
)

foreach ($path in $BunPaths) {
    if (Test-Path $path) {
        $BunPath = $path
        break
    }
}

if (-not $BunPath) {
    $BunCmd = Get-Command bun -ErrorAction SilentlyContinue
    if ($BunCmd) {
        $BunPath = $BunCmd.Source
    }
}

if (-not $BunPath) {
    Write-Host "Bun not found. Installing..." -ForegroundColor Yellow
    Invoke-RestMethod https://bun.sh/install.ps1 | Invoke-Expression
    $BunPath = "$env:USERPROFILE\.bun\bin\bun.exe"
}

Write-Host "Bun: $BunPath" -ForegroundColor Green

# Convert to forward slashes for JSON/command compatibility
$BunPathForward = $BunPath -replace '\\', '/'
$ClaudeHomeForward = $ClaudeHome -replace '\\', '/'

# Generate settings.json from template
if (Test-Path "settings.template.json") {
    Write-Host "Generating settings.json..." -ForegroundColor Cyan
    $template = Get-Content "settings.template.json" -Raw
    $settings = $template -replace '\{\{BUN_PATH\}\}', $BunPathForward
    $settings = $settings -replace '\{\{CLAUDE_HOME\}\}', $ClaudeHomeForward
    $settings | Set-Content "settings.json" -Encoding UTF8
    Write-Host "settings.json generated" -ForegroundColor Green
}

# Generate vault commands from templates
Write-Host "Generating vault commands..." -ForegroundColor Cyan
$vaultTemplates = Get-ChildItem "commands/vault*.template.md" -ErrorAction SilentlyContinue
foreach ($template in $vaultTemplates) {
    $content = Get-Content $template.FullName -Raw
    $content = $content -replace '\{\{BUN_PATH\}\}', $BunPathForward
    $content = $content -replace '\{\{CLAUDE_HOME\}\}', $ClaudeHomeForward
    $outputName = $template.Name -replace '\.template\.md$', '.md'
    $content | Set-Content "commands/$outputName" -Encoding UTF8
}
Write-Host "Vault commands generated" -ForegroundColor Green

Write-Host ""
Write-Host "Setup complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Restart Claude Code"
Write-Host "  2. Use /aipeerreview for AI peer reviews"
