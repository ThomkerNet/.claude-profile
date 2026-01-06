# Bitwarden wrapper completions for zsh
# Source this file in your .zshrc: source ~/.claude/tools/bitwarden/completions.zsh

# Reuse bw completions for bw-tkn and bw-bnx
# First, ensure bw completions are loaded
if (( ! $+functions[_bw] )); then
    eval "$(bw completion --shell zsh 2>/dev/null)"
fi

# Create completion functions that delegate to _bw
compdef _bw bw-tkn
compdef _bw bw-bnx
