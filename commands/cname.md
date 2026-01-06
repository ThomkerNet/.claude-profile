Set the custom session label to: $ARGUMENTS

Store this label in ~/.claude/.session-label so the status line can read it.

Cross-platform command:
```powershell
$homeDir = if ($env:HOME) { $env:HOME } else { $env:USERPROFILE }
"$ARGUMENTS" | Out-File -FilePath (Join-Path $homeDir ".claude/.session-label") -Encoding utf8 -NoNewline
```

Confirm the label has been set.
