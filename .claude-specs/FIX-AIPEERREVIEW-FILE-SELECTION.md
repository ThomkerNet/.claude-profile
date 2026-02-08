> **ARCHIVED:** This spec is obsolete. The local `/aipeerreview` scripts have been removed in favor of the `tkn-aipeerreview` MCP server.

# Spec: Fix AI Peer Review File Selection

**Generated:** 2026-01-09
**Target:** ~/.claude/scripts/aipeerreview/index.ts
**Priority:** High - Currently reviews wrong files

---

## Problem

When `/aipeerreview` is invoked without a file argument, it looks for the most recently modified `.md` file in `~/.claude/plans/`. This is wrong because:

1. The user expects it to review what they just worked on in the current session
2. Plans in `~/.claude/plans/` are often unrelated to current work
3. No integration with Claude Code's context (recent files, git diff, etc.)

**Current behavior (lines 249-310):**
```typescript
function findMostRecentPlan(filePath?: string): string {
  // Falls back to ~/.claude/plans/*.md sorted by mtime
}
```

---

## Proposed Fix

### Option A: Git-aware (Recommended)

When no file specified, review files from recent git activity:

```typescript
function findRecentWorkingFiles(): string[] {
  // 1. Get uncommitted changes: git diff --name-only HEAD
  // 2. Get recently committed: git diff --name-only HEAD~3
  // 3. Filter to reviewable extensions (.ts, .tsx, .yml, .yaml, .py, etc.)
  // 4. Concatenate contents or review individually
}
```

### Option B: CWD-aware

Look for recently modified files in current working directory:

```typescript
function findRecentCwdFiles(extensions: string[]): string[] {
  // 1. Walk cwd recursively (excluding node_modules, .git, etc.)
  // 2. Filter by extension and mtime (last 1 hour)
  // 3. Return sorted by mtime descending
}
```

### Option C: Explicit mode switching

Add `--mode` flag:
- `--mode git` - Review git changes (default)
- `--mode plan` - Review from ~/.claude/plans/
- `--mode file <path>` - Explicit file (current behavior with arg)

---

## Implementation Changes

### 1. Update `findMostRecentPlan()` → `findReviewTarget()`

```typescript
function findReviewTarget(filePath?: string): string | string[] {
  if (filePath) return resolve(filePath);

  // Try git diff first
  const gitChanges = getGitChangedFiles();
  if (gitChanges.length > 0) {
    console.log(`📂 Auto-detected ${gitChanges.length} changed files from git`);
    return gitChanges;
  }

  // Fallback to plans directory
  return findMostRecentPlan();
}

function getGitChangedFiles(): string[] {
  try {
    const result = execSync('git diff --name-only HEAD 2>/dev/null', { encoding: 'utf-8' });
    const staged = execSync('git diff --cached --name-only 2>/dev/null', { encoding: 'utf-8' });

    const files = [...new Set([...result.split('\n'), ...staged.split('\n')])]
      .filter(f => f.trim())
      .filter(f => REVIEWABLE_EXTENSIONS.some(ext => f.endsWith(ext)))
      .map(f => resolve(f));

    return files;
  } catch {
    return [];
  }
}

const REVIEWABLE_EXTENSIONS = [
  '.ts', '.tsx', '.js', '.jsx',
  '.py', '.go', '.rs', '.java',
  '.yml', '.yaml', '.json',
  '.tf', '.hcl',
  '.md'
];
```

### 2. Handle multiple files

```typescript
// In main()
const targets = findReviewTarget(filePath);
const files = Array.isArray(targets) ? targets : [targets];

// Concatenate for review or review each separately
const content = files.map(f => {
  const name = basename(f);
  return `## File: ${name}\n\n\`\`\`${getExtension(f)}\n${readFileSync(f, 'utf-8')}\n\`\`\``;
}).join('\n\n---\n\n');
```

### 3. Add mode flags

```typescript
// In parseArgs()
if (arg === '--mode' || arg === '-m') {
  const mode = args[++i];
  if (!['git', 'plan', 'file'].includes(mode)) {
    console.error(`Invalid mode: ${mode}`);
    process.exit(1);
  }
  return { mode, ... };
}
```

---

## Acceptance Criteria

- [ ] `/aipeerreview` with no args reviews git changes in cwd
- [ ] `/aipeerreview` falls back to plans if no git changes
- [ ] `/aipeerreview --mode plan` forces plans directory
- [ ] `/aipeerreview <file>` still works as before
- [ ] Multiple changed files are concatenated with clear separators
- [ ] Shows which files will be reviewed before starting

---

## Testing

```bash
# In a git repo with changes
cd ~/git-bnx/BriefHours/BriefHours-WebApp
git diff --name-only  # Should show deploy.yml
/aipeerreview  # Should review deploy.yml, not random plan

# Force plan mode
/aipeerreview --mode plan  # Should use ~/.claude/plans/

# Explicit file (unchanged)
/aipeerreview src/app/api/health/route.ts
```
