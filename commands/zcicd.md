# Zero-Friction Commit with CI/CD Monitoring

> **Description:** Commit, push, and monitor CI/CD pipeline - auto-fix failures

## Usage

```bash
/zcicd                  # Commit, push, and watch CI/CD
/zcicd "custom message" # Commit with custom message + watch CI/CD
```

## What It Does

1. **Run /z** - Execute the standard zero-friction commit (stage, commit, push)
2. **Detect CI/CD** - Identify the pipeline system (GitHub Actions, GitLab CI, etc.)
3. **Watch pipeline** - Monitor until completion
4. **On failure** - Attempt automatic fix, then peer review if needed
5. **Iterate** - Continue until pipeline passes or manual intervention needed

---

## Execution Steps

### Step 1: Commit and Push

Execute `/z` to stage, commit, and push all changes.

### Step 2: Detect CI/CD System

```bash
# Check for GitHub Actions
ls -la .github/workflows/ 2>/dev/null

# Check for GitLab CI
ls -la .gitlab-ci.yml 2>/dev/null

# Check for other CI configs
ls -la Jenkinsfile .circleci/ .travis.yml azure-pipelines.yml 2>/dev/null
```

### Step 3: Watch Pipeline Status

**For GitHub Actions:**

```bash
# Get the latest workflow run
gh run list --limit 1

# Watch the run (blocking until complete)
gh run watch

# Or check status non-blocking
gh run list --limit 1 --json status,conclusion,name,headBranch
```

**For GitLab CI:**

```bash
# Check pipeline status via API
glab pipeline list --per-page 1
glab pipeline status
```

### Step 4: Handle Results

#### If Pipeline Succeeds ✅

```
✅ CI/CD passed! All checks green.
```

Done - no further action needed.

#### If Pipeline Fails ❌

Execute the failure recovery workflow:

```
❌ CI/CD failed. Analyzing failure...
```

---

## Failure Recovery Workflow

### Phase 1: Analyze Failure

```bash
# Get failed run details
gh run view --log-failed

# Or get full logs
gh run view --log
```

Parse the logs to identify:
- Which job failed
- Which step failed
- Error messages and stack traces
- Test names if test failure

### Phase 2: First Fix Attempt

Based on failure type, attempt automatic fix:

| Failure Type | Auto-Fix Strategy |
|--------------|-------------------|
| **ruff format** | Run `ruff format <files>` locally to fix formatting |
| **ruff check** | Run `ruff check --fix <files>` to auto-fix lint issues |
| **Test failure** | Read failing test, analyze assertion, fix code or test |
| **Type error** | Read error, fix type issues |
| **Build error** | Analyze build output, fix imports/syntax |
| **Dependency issue** | Update lockfile, check versions |

#### Auto-Fix: Ruff Format Errors

If the failure log contains "Would reformat:" entries from `ruff format --check`:

```bash
# Extract files that need formatting from CI logs
# Look for lines like: "Would reformat: servers/tkn-azure/server.py"

# Run ruff format on affected files
ruff format <file1> <file2> ...

# Or format entire directories
ruff format servers/ tests/
```

#### Auto-Fix: Ruff Lint Errors

If the failure log contains ruff check errors (F401, E501, etc.):

```bash
# Run ruff with auto-fix
ruff check --fix servers/ tests/

# For unfixable issues, read the error and fix manually
```

#### Auto-Fix: Other Lint/Format Tools

| Tool | Command |
|------|---------|
| **black** | `black <files>` |
| **prettier** | `prettier --write <files>` |
| **eslint** | `eslint --fix <files>` |
| **isort** | `isort <files>` |

```bash
# After fixing, commit and push
git add -A
git commit -m "Fix CI failure: <description>

🤖 Generated with Claude Code"
git push
```

Then return to **Step 3** to watch the new run.

### Phase 3: If First Fix Fails - AI Peer Review

If the automatic fix didn't resolve the issue:

```
⚠️ First fix attempt failed. Running AI peer review...
```

1. **Gather context:**
   - Failed test/build output
   - Relevant source files
   - Recent changes that may have caused the issue

2. **Run peer review:**
   ```
   /aipeerreview -t bug <failing_files>
   ```

3. **Apply peer review recommendations**

4. **Commit and push fix:**
   ```bash
   git add -A
   git commit -m "Fix CI failure (peer reviewed): <description>

   🤖 Generated with Claude Code"
   git push
   ```

5. Return to **Step 3** to watch the new run.

### Phase 4: Escalation

If after peer review the pipeline still fails:

```
🚨 CI/CD still failing after peer review.

**Summary of attempts:**
1. First fix: <what was tried>
2. Peer review fix: <what was tried>

**Current failure:**
<error details>

**Recommended next steps:**
- <specific suggestions>

Manual intervention may be required.
```

Stop and report to user for guidance.

---

## GitHub Actions Commands Reference

```bash
# List recent runs
gh run list --limit 5

# Watch current run (blocks until complete)
gh run watch

# View specific run
gh run view <run-id>

# View failed logs only
gh run view <run-id> --log-failed

# View full logs
gh run view <run-id> --log

# Re-run failed jobs
gh run rerun <run-id> --failed

# Check workflow files
gh workflow list
gh workflow view <workflow-name>
```

---

## Example Workflow

```
📊 Running /z...
✅ Committed and pushed: "Add new validation logic"

🔍 Detecting CI/CD system...
   Found: GitHub Actions (.github/workflows/ci.yml)

⏳ Watching pipeline...
   Run #1234: In progress...
   Job: test (node 18) - Running...
   Job: test (node 18) - Failed ❌

❌ CI/CD failed. Analyzing failure...

📋 Failure Analysis:
   Job: test
   Step: Run tests
   Error: ValidationError: expected 'foo' but got 'bar'
   File: src/validators.test.ts:45

🔧 Attempting fix...
   Reading src/validators.ts and src/validators.test.ts
   Issue: Validation logic returns wrong format
   Fix: Update return value format

📤 Pushing fix...
✅ Committed: "Fix validation return format"

⏳ Watching pipeline...
   Run #1235: In progress...
   Job: test (node 18) - Passed ✅
   Job: lint - Passed ✅
   Job: build - Passed ✅

✅ CI/CD passed! All checks green.

✨ Done! Changes committed and CI/CD verified.
```

---

## Configuration

### Max Retry Attempts

The workflow will attempt:
- 1 automatic fix
- 1 peer-reviewed fix
- Then escalate to user

### Timeout

If watching pipeline for more than 15 minutes, provide status update and ask if user wants to continue waiting.

---

## Quick Detection: Common CI Failure Patterns

When analyzing `gh run view --log-failed`, look for these patterns:

| Log Pattern | Failure Type | Auto-Fix Command |
|-------------|--------------|------------------|
| `Would reformat:` | ruff format | `ruff format <files>` |
| `F401 [*]` imported but unused | ruff lint | `ruff check --fix` |
| `E501` line too long | ruff lint | `ruff check --fix` or manual |
| `error: Process completed with exit code 1` + lint step | Formatting/lint | Check which linter failed |
| `FAILED tests/` | pytest failure | Read test, fix code |
| `ModuleNotFoundError` | Missing dependency | `pip install` or update requirements |
| `SyntaxError` | Python syntax | Fix the syntax error |
| `TypeScript error TS` | Type error | Fix type annotations |

### Priority Order for Fixes

1. **Formatting issues** - Always fix first (ruff format, black, prettier)
2. **Lint issues** - Fix auto-fixable ones, then manual
3. **Type errors** - Usually straightforward to fix
4. **Test failures** - May need deeper analysis
5. **Build errors** - Check imports, dependencies

---

## Notes

- Works best with GitHub Actions (uses `gh` CLI)
- Requires `gh` CLI authenticated (`gh auth status`)
- For GitLab, requires `glab` CLI
- Other CI systems: manual log checking may be needed
