# Claude Code Status Line - Cross-platform (Windows/macOS/Linux)
# Reads JSON input from stdin and outputs formatted status

$input = [Console]::In.ReadToEnd()
$data = $input | ConvertFrom-Json

# Extract values
$model = $data.model.display_name
$currentDir = Split-Path -Leaf $data.workspace.current_dir

# Read custom session label if it exists (set via /cname command)
$customLabel = ""
$homeDir = if ($env:HOME) { $env:HOME } else { $env:USERPROFILE }
$labelFile = Join-Path $homeDir ".claude/.session-label"
if (Test-Path $labelFile) {
    $customLabel = (Get-Content $labelFile -Raw).Trim()
    if ($customLabel) {
        $customLabel = " | $customLabel"
    }
}

# Context window metrics
$inputTokens = $data.context_window.total_input_tokens
$outputTokens = $data.context_window.total_output_tokens
$contextSize = $data.context_window.context_window_size

# Cost metrics
$costUsd = $data.cost.total_cost_usd
$linesAdded = $data.cost.total_lines_added
$linesRemoved = $data.cost.total_lines_removed

# Format tokens as Xk
function Format-Tokens($num) {
    if ($num -ge 1000) {
        return "$([math]::Floor($num / 1000))k"
    }
    return $num
}

$totalTokens = $inputTokens + $outputTokens

# Get git branch if in a repo
$gitBranch = ""
try {
    $branch = git branch --show-current 2>$null
    if ($branch) {
        $gitBranch = " | $branch"
    }
} catch {}

# Calculate context usage percentage
$contextPct = if ($contextSize -gt 0) { [math]::Round(($totalTokens / $contextSize) * 100, 1) } else { 0 }

# Output formatted status
Write-Host "[$model] $currentDir$gitBranch$customLabel"
Write-Host "Tokens: $(Format-Tokens $totalTokens) ($(Format-Tokens $inputTokens)+$(Format-Tokens $outputTokens)) | Ctx: $contextPct%"
Write-Host "Cost: `$$([math]::Round($costUsd, 4)) | +$linesAdded -$linesRemoved lines"
