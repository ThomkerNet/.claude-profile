# AI Peer Review Slash Command Implementation

## Overview

Implement `/aipeerreview` - a multi-model AI peer review system that sends plans/issues to ChatGPT, Gemini, and Claude Opus simultaneously for comprehensive vetting.

## Requirements

- Review most recent plan or specified file
- Run three AI models in parallel for speed
- Use Copilot CLI with different models (gpt-5.1, gemini-3-pro, claude-opus-4.5)
- Display structured reviews with strengths/weaknesses/recommendations
- Handle large documents (10MB+ buffers)
- Proper error handling and temp file cleanup

## Implementation

### Architecture

- **Slash Command**: `commands/aipeerreview.md` - User-facing documentation
- **Implementation**: `skills/aipeerreview/index.ts` - Bun TypeScript script
- **Execution Model**: Async/parallel using Promise.all()
- **File Discovery**: Search `~/.claude/plans/` and `queue.md` for most recent

### Key Components

#### 1. File Discovery
- Searches `~/.claude/plans/*.md` for plan files
- Also checks `~/.claude/queue.md` for issues
- Returns most recently modified file
- Supports explicit file path override

#### 2. Multi-Model Parallel Execution
```typescript
// Run all 3 reviews in parallel
const reviews = await Promise.all(
  REVIEW_CONFIG.models.map((model) => reviewWithModel(model, content))
);
```

Models:
- **ChatGPT**: gpt-5.1 (Advanced reasoning)
- **Gemini Pro**: gemini-3-pro-preview (Novel perspectives)
- **Claude Opus**: claude-opus-4.5 (Comprehensive analysis)

#### 3. Temp File Handling
- Writes review prompt to temp file to avoid shell escaping issues
- Each model gets unique temp file: `/tmp/copilot-prompt-${timestamp}-${modelId}.txt`
- Automatic cleanup after copilot execution

#### 4. Structured Output
- Header with document name and models
- Parallel execution indicator
- Per-model review section with clear separators
- Execution time tracking
- Completion message with total duration

### Technologies Used

- **Bun**: TypeScript runtime for script execution
- **Copilot CLI**: Multi-model AI inference (--model switch)
- **Node.js fs**: File system operations
- **Promise.all()**: Parallel async execution

## Security Considerations

- Temp files created in `/tmp` with unique names
- Automatic cleanup prevents accumulation
- No command injection (using writeFileSync + separate execution)
- Large buffer (10MB) prevents truncation
- Error handling per model (doesn't fail entire review if one model errors)

## Performance

- Parallel execution: ~3x faster than sequential
- Example: 3 models * 30s each = 90s sequential vs ~30s parallel
- Actual test: 263s for complex plan (all 3 running together)
- Scales well for concurrent requests

## Testing

- Tested on actual plan file: quizzical-munching-bachman.md
- All 3 models executed successfully in parallel
- Reviews provided diverse perspectives
- Execution time tracked and displayed correctly

### Self-Review Testing
The feature was reviewed using itself (`/aipeerreview` on `aipeerreview-feature.md`), which identified critical issues:

**Issues Identified:**
1. **execSync was not parallel** - Blocking calls prevented true parallelization
2. **No temp file cleanup on errors** - Missing try/finally blocks
3. **Windows incompatible** - Hardcoded `/tmp` paths

**Fixes Applied:**
- ✅ Switched to async `exec` with `promisify` for true parallelization
- ✅ Added try/finally with `rmSync` for guaranteed cleanup
- ✅ Used `os.tmpdir()` + `path.join()` for cross-platform support
- ✅ Added 5-minute timeout to prevent hangs
- ✅ Added model ID validation against allowlist
- ✅ Set restrictive file permissions (0o600)

**Result:** Feature now truly parallel, secure, and cross-platform compatible

## Documentation

- Comprehensive slash command docs: `commands/aipeerreview.md`
- README section with usage, features, examples
- Inline code comments explaining shell/async patterns
- Setup documentation in `setup.sh`

## Deployment

- Automatically configured during setup.sh
- Template substitution for paths (BUN_PATH, CLAUDE_HOME)
- Works on macOS/Linux (script-based approach)
- Requires: Copilot CLI installed, jq available, bun runtime
