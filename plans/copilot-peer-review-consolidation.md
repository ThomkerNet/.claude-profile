# Plan: Consolidate Peer Review to Copilot CLI

## Peer Review Feedback (GPT-5.1 + Claude Opus)

**Incorporated changes:**
- Add verification step before removing Gemini CLI
- Archive `agents/gemini.md` instead of deleting
- Keep Gemini CLI as fallback for multimodal (images, PDFs)
- Add migration/fallback documentation
- Centralize model recommendations

---

## Current State

### Files with AI peer review functionality:

| File | Current Approach | Action |
|------|------------------|--------|
| `commands/review.md` | Uses `gemini -p` | Update to `copilot -p` |
| `skills/solution-review/SKILL.md` | Uses `gemini -p` extensively | Update to `copilot -p` |
| `agents/gemini.md` | Standalone Gemini agent | Archive (keep for multimodal) |
| `commands/aipeerreview.md` | Already uses Copilot CLI | Keep as-is |
| `skills/aipeerreview/index.ts` | Uses Copilot with multiple models | Keep as-is |
| `CLAUDE.md` | Documents `gemini -p` prominently | Update to emphasize Copilot |
| `skills/profile-reference/SKILL.md` | Documents both tools | Update to emphasize Copilot |

### Available Copilot Models:
```
Claude:  claude-sonnet-4.5 (default), claude-haiku-4.5, claude-opus-4.5, claude-sonnet-4
GPT:     gpt-5.2, gpt-5.1, gpt-5.1-codex, gpt-5, gpt-5-mini, gpt-4.1
Gemini:  gemini-3-pro-preview
```

---

## Implementation Order

1. [x] Update plan with peer review feedback
2. [ ] Verify Copilot multimodal capabilities
3. [ ] Update `CLAUDE.md` - Central documentation
4. [ ] Update `commands/review.md` - User-facing command
5. [ ] Update `skills/solution-review/SKILL.md` - Skill documentation
6. [ ] Update `skills/profile-reference/SKILL.md` - Reference docs
7. [ ] Archive `agents/gemini.md` to `agents/gemini.md.archived`
8. [ ] Test `copilot -p` commands work correctly

---

## Detailed Changes

### CLAUDE.md Multi-LLM Section

```markdown
## Multi-LLM Tools

| Tool | Use | Command |
|------|-----|---------|
| **Claude** | Complex coding, refactoring, architecture | (current) |
| **Copilot** | Peer review, second opinions, multi-model | `copilot -p "..."` |
| **Gemini** | Multimodal only (images, PDFs) | `gemini -p "..."` |

**Copilot models:** `--model claude-opus-4.5`, `--model gpt-5.1`, `--model gemini-3-pro-preview`

**Fallback:** If Copilot unavailable, use `gemini -p "..."` directly.
```

### Model Recommendations (Centralized)

| Task | Recommended Model | Command |
|------|-------------------|---------|
| Security review | GPT-5.1 | `copilot --model gpt-5.1 -p "..."` |
| Architecture review | Claude Opus | `copilot --model claude-opus-4.5 -p "..."` |
| Code review | Default (Sonnet) | `copilot -p "..."` |
| Alternative perspective | Gemini | `copilot --model gemini-3-pro-preview -p "..."` |
| Multimodal (images) | Gemini CLI | `gemini -p "..."` (standalone) |

---

## Key Benefits

1. **Unified interface** - One tool for all text-based models
2. **Better model selection** - Choose optimal model per task
3. **Single license** - Copilot Pro covers all models
4. **Cleaner profile** - Less duplication
5. **Fallback preserved** - Gemini CLI for multimodal + emergencies

---

## Rollback Plan

If Copilot has issues:
1. Restore `agents/gemini.md` from `.archived`
2. Revert to `gemini -p` in affected files
3. Git history preserves all previous versions
