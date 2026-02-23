Set the custom session label to: $ARGUMENTS

Store this label in a session-specific file keyed by the Claude Code process PID.
Walk the process tree to find the Claude Code process (named like a semver, e.g. "2.1.50")
so it matches what the statusline resolves regardless of invocation depth.

If $ARGUMENTS is non-empty, set the label:
```bash
_p=$$; _cpid=$PPID
for _d in 1 2 3 4 5; do
    _pp=$(ps -p "$_p" -o ppid= 2>/dev/null | tr -d ' ')
    _pc=$(ps -p "$_pp" -o comm= 2>/dev/null | tr -d ' ')
    if [[ "$_pc" =~ ^[0-9]+\.[0-9] ]] || [[ "$_pc" == "claude" ]]; then
        _cpid=$_pp; break
    fi
    _p=$_pp
done
echo -n "$ARGUMENTS" > "${HOME}/.claude/.session-label-${_cpid}"
```

If $ARGUMENTS is empty, clear the label:
```bash
_p=$$; _cpid=$PPID
for _d in 1 2 3 4 5; do
    _pp=$(ps -p "$_p" -o ppid= 2>/dev/null | tr -d ' ')
    _pc=$(ps -p "$_pp" -o comm= 2>/dev/null | tr -d ' ')
    if [[ "$_pc" =~ ^[0-9]+\.[0-9] ]] || [[ "$_pc" == "claude" ]]; then
        _cpid=$_pp; break
    fi
    _p=$_pp
done
rm -f "${HOME}/.claude/.session-label-${_cpid}"
```

Confirm the label has been set (or cleared), and mention the session PID used.
