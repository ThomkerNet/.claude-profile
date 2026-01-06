---
name: tmuxhelp
description: Quick reference for tmux commands. Shows common session, window, and pane operations.
---

# tmux Quick Reference

## Session Management

| Action | Command |
|--------|---------|
| New session | `tmux new -s name` |
| List sessions | `tmux ls` |
| Attach to session | `tmux attach -t name` or `tmux a -t name` |
| Detach from session | `Ctrl+b d` |
| Kill session | `tmux kill-session -t name` |
| Rename session | `Ctrl+b $` |
| Switch session | `Ctrl+b s` (interactive list) |

## Window Management

| Action | Shortcut |
|--------|----------|
| New window | `Ctrl+b c` |
| Next window | `Ctrl+b n` |
| Previous window | `Ctrl+b p` |
| Window by number | `Ctrl+b 0-9` |
| Rename window | `Ctrl+b ,` |
| Close window | `Ctrl+b &` or `exit` |
| List windows | `Ctrl+b w` (interactive) |

## Pane Management

| Action | Shortcut |
|--------|----------|
| Split horizontal | `Ctrl+b "` |
| Split vertical | `Ctrl+b %` |
| Navigate panes | `Ctrl+b arrow` |
| Close pane | `Ctrl+b x` or `exit` |
| Toggle zoom | `Ctrl+b z` (fullscreen pane) |
| Resize pane | `Ctrl+b Ctrl+arrow` |
| Swap panes | `Ctrl+b {` or `Ctrl+b }` |
| Show pane numbers | `Ctrl+b q` (then number to jump) |

## Copy Mode (scrollback)

| Action | Shortcut |
|--------|----------|
| Enter copy mode | `Ctrl+b [` |
| Exit copy mode | `q` or `Esc` |
| Scroll up/down | `Page Up/Down` or arrow keys |
| Search backward | `Ctrl+r` or `?` |
| Search forward | `/` |
| Start selection | `Space` (in copy mode) |
| Copy selection | `Enter` (in copy mode) |
| Paste | `Ctrl+b ]` |

## Session Persistence (tmux-resurrect)

| Action | Shortcut |
|--------|----------|
| Save session | `Ctrl+b Ctrl+s` |
| Restore session | `Ctrl+b Ctrl+r` |

## Useful Commands

```bash
# Kill all sessions
tmux kill-server

# List all key bindings
tmux list-keys

# Reload config
tmux source-file ~/.tmux.conf

# Run command in new window
tmux new-window "htop"

# Send keys to a pane
tmux send-keys -t session:window.pane "command" Enter
```

## Prefix Key

Default: `Ctrl+b`

All shortcuts above starting with `Ctrl+b` mean: press `Ctrl+b`, release, then press the next key.
