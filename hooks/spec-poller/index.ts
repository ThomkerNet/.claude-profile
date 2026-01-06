#!/usr/bin/env bun
/**
 * Spec Poller - Stop Hook
 *
 * When Claude would stop and wait for user input, this hook:
 * 1. Checks for new *-SPEC.md files in the current project
 * 2. If found, blocks the stop and injects context to process the spec
 * 3. If not found, polls every 30 seconds for up to 1 hour
 * 4. After timeout, allows Claude to stop normally
 *
 * This enables agent-to-agent handoff without user interaction.
 */

import { existsSync, readdirSync, readFileSync, writeFileSync, mkdirSync, statSync, realpathSync, unlinkSync } from "fs";
import { join, dirname } from "path";
import { homedir } from "os";

interface HookInput {
  cwd?: string;
  workspace?: { current_dir: string };
  session_id?: string;
  stop_hook_active?: boolean;
}

interface PollerState {
  pollStartTime: number;
  processedSpecs: string[];  // Hashes of specs we've already processed this session
  pollCount: number;
}

interface SpecInfo {
  path: string;
  name: string;
  title: string;
  from: string;
  priority: string;
  content: string;
  hash: string;
}

const CLAUDE_HOME = join(homedir(), ".claude");
const SESSION_ID = process.env.CLAUDE_SESSION_ID || `session-${process.pid}`;
const STATE_FILE = join(CLAUDE_HOME, `.spec-poller-state-${SESSION_ID}.json`);
const ENABLED_FILE = join(CLAUDE_HOME, ".spec-poller-enabled");
const POLL_INTERVAL_MS = 30 * 1000;  // 30 seconds
const MAX_POLL_DURATION_MS = 3 * 60 * 60 * 1000;  // 3 hours
const MAX_POLLS = Math.floor(MAX_POLL_DURATION_MS / POLL_INTERVAL_MS);  // ~360 polls
const MAX_PROCESSED_SPECS = 100;  // Limit to prevent unbounded growth
const MAX_SPEC_SIZE_BYTES = 100 * 1024;  // 100KB max spec file size
const STATE_FILE_MAX_AGE_MS = 24 * 60 * 60 * 1000;  // 24 hours

/**
 * Check if spec polling is enabled
 */
function isPollingEnabled(): boolean {
  return existsSync(ENABLED_FILE);
}

/**
 * Clean up old state files (older than 24 hours)
 */
function cleanupOldStateFiles(): void {
  try {
    const files = readdirSync(CLAUDE_HOME);
    const now = Date.now();

    for (const file of files) {
      if (!file.startsWith(".spec-poller-state-")) continue;

      const filePath = join(CLAUDE_HOME, file);
      try {
        const stats = statSync(filePath);
        if (now - stats.mtimeMs > STATE_FILE_MAX_AGE_MS) {
          unlinkSync(filePath);
        }
      } catch {
        // Ignore errors for individual files
      }
    }
  } catch {
    // Ignore cleanup errors
  }
}

/**
 * Simple hash for deduplication
 */
function simpleHash(str: string): string {
  let hash = 0;
  for (let i = 0; i < str.length; i++) {
    const char = str.charCodeAt(i);
    hash = ((hash << 5) - hash) + char;
    hash = hash & hash;
  }
  return Math.abs(hash).toString(16).padStart(8, '0');
}

/**
 * Read poller state
 */
function readState(): PollerState {
  try {
    if (existsSync(STATE_FILE)) {
      const state = JSON.parse(readFileSync(STATE_FILE, "utf-8"));
      // Reset if poll started more than MAX_POLL_DURATION ago (stale state)
      if (Date.now() - state.pollStartTime > MAX_POLL_DURATION_MS + 60000) {
        return { pollStartTime: Date.now(), processedSpecs: [], pollCount: 0 };
      }
      // Trim processedSpecs if too large (keep most recent)
      if (state.processedSpecs?.length > MAX_PROCESSED_SPECS) {
        state.processedSpecs = state.processedSpecs.slice(-MAX_PROCESSED_SPECS);
      }
      return state;
    }
  } catch {
    // Ignore errors
  }
  return { pollStartTime: Date.now(), processedSpecs: [], pollCount: 0 };
}

/**
 * Write poller state
 */
function writeState(state: PollerState): void {
  try {
    mkdirSync(dirname(STATE_FILE), { recursive: true });
    writeFileSync(STATE_FILE, JSON.stringify(state, null, 2));
  } catch {
    // Ignore errors
  }
}

/**
 * Parse YAML frontmatter
 */
function parseFrontmatter(content: string): Record<string, string> {
  const frontmatter: Record<string, string> = {};
  const match = content.match(/^---\n([\s\S]*?)\n---/);

  if (match) {
    for (const line of match[1].split("\n")) {
      const colonIdx = line.indexOf(":");
      if (colonIdx > 0) {
        const key = line.slice(0, colonIdx).trim();
        const value = line.slice(colonIdx + 1).trim();
        frontmatter[key] = value;
      }
    }
  }

  return frontmatter;
}

/**
 * Find new specs in the current project
 */
function findNewSpecs(projectDir: string, processedHashes: string[]): SpecInfo[] {
  const specDir = join(projectDir, ".claude-specs");
  const newSpecs: SpecInfo[] = [];

  if (!existsSync(specDir)) {
    return newSpecs;
  }

  // Get real path of spec directory for path traversal protection
  let realSpecDir: string;
  try {
    realSpecDir = realpathSync(specDir);
  } catch {
    return newSpecs;
  }

  try {
    const files = readdirSync(specDir);

    for (const file of files) {
      if (!file.match(/-SPEC\.(md|MD)$/i)) continue;

      const specPath = join(specDir, file);

      // Path traversal protection: ensure file is within spec directory
      try {
        const realSpecPath = realpathSync(specPath);
        if (!realSpecPath.startsWith(realSpecDir)) {
          continue;  // Skip files outside spec directory (symlink attack)
        }
      } catch {
        continue;  // Skip if we can't resolve the path
      }

      // File size check: skip files larger than MAX_SPEC_SIZE_BYTES
      try {
        const stats = statSync(specPath);
        if (stats.size > MAX_SPEC_SIZE_BYTES) {
          continue;  // Skip oversized files
        }
      } catch {
        continue;  // Skip if we can't stat the file
      }

      const content = readFileSync(specPath, "utf-8");
      const hash = simpleHash(content);

      // Skip if already processed this session
      if (processedHashes.includes(hash)) continue;

      const frontmatter = parseFrontmatter(content);

      newSpecs.push({
        path: specPath,
        name: file,
        title: frontmatter.title || file.replace(/-SPEC\.(md|MD)$/i, ""),
        from: frontmatter.from || "another agent",
        priority: frontmatter.priority || "medium",
        content,
        hash
      });
    }

    // Sort by priority (high first)
    newSpecs.sort((a, b) => {
      const priorityOrder = { high: 0, medium: 1, low: 2 };
      return (priorityOrder[a.priority as keyof typeof priorityOrder] ?? 1) -
             (priorityOrder[b.priority as keyof typeof priorityOrder] ?? 1);
    });

  } catch {
    // Ignore errors
  }

  return newSpecs;
}

/**
 * Sleep for a duration
 */
function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function main() {
  const input = await Bun.stdin.text();

  if (!input) {
    process.exit(0);
  }

  // Check if polling is enabled (off by default)
  if (!isPollingEnabled()) {
    // Polling disabled - allow stop without any action
    console.log(JSON.stringify({ decision: "approve" }));
    return;
  }

  // Cleanup old state files periodically (runs on each poll)
  cleanupOldStateFiles();

  try {
    const hookData: HookInput = JSON.parse(input);
    const cwd = hookData.cwd || hookData.workspace?.current_dir || process.cwd();

    // Read current state
    let state = readState();

    // Check for new specs
    const newSpecs = findNewSpecs(cwd, state.processedSpecs);

    if (newSpecs.length > 0) {
      // Found specs! Block the stop and inject context
      const spec = newSpecs[0];  // Process one at a time

      // Mark this spec as processed
      state.processedSpecs.push(spec.hash);
      state.pollCount = 0;  // Reset poll count for next idle period
      writeState(state);

      // Build context with full spec content
      const context = `<spec-handoff>
## 📋 Incoming Spec from ${spec.from}

A new specification has been dropped in this project by another agent. Please process it now.

**File:** \`${spec.name}\`
**Title:** ${spec.title}
**Priority:** ${spec.priority}
**From:** ${spec.from}

### Full Spec Content:

\`\`\`markdown
${spec.content}
\`\`\`

---

**Your task:**
1. Read and understand this spec
2. Create a detailed implementation plan
3. Identify the files that need to be changed
4. Ask the user for approval before implementing

${newSpecs.length > 1 ? `\n*Note: ${newSpecs.length - 1} more spec(s) waiting after this one.*` : ""}
</spec-handoff>`;

      // Block the stop and continue with the spec
      console.log(JSON.stringify({
        decision: "block",
        hookSpecificOutput: {
          additionalContext: context
        }
      }));
      return;
    }

    // No specs found - should we keep polling?
    const elapsedTime = Date.now() - state.pollStartTime;

    if (elapsedTime < MAX_POLL_DURATION_MS && state.pollCount < MAX_POLLS) {
      // Still within polling window - wait and check again
      state.pollCount++;
      writeState(state);

      const remainingMinutes = Math.round((MAX_POLL_DURATION_MS - elapsedTime) / 60000);

      // Wait for poll interval
      await sleep(POLL_INTERVAL_MS);

      // Check again after waiting
      const specsAfterWait = findNewSpecs(cwd, state.processedSpecs);

      if (specsAfterWait.length > 0) {
        const spec = specsAfterWait[0];
        state.processedSpecs.push(spec.hash);
        state.pollCount = 0;
        writeState(state);

        const context = `<spec-handoff>
## 📋 Incoming Spec from ${spec.from}

A new specification has arrived! Processing now.

**File:** \`${spec.name}\`
**Title:** ${spec.title}
**Priority:** ${spec.priority}

### Full Spec Content:

\`\`\`markdown
${spec.content}
\`\`\`

---

**Your task:**
1. Read and understand this spec
2. Create a detailed implementation plan
3. Identify the files that need to be changed
4. Ask the user for approval before implementing
</spec-handoff>`;

        console.log(JSON.stringify({
          decision: "block",
          hookSpecificOutput: {
            additionalContext: context
          }
        }));
        return;
      }

      // Still no specs - block and show waiting status
      console.log(JSON.stringify({
        decision: "block",
        hookSpecificOutput: {
          additionalContext: `<spec-polling status="waiting">
Polling for incoming specs... (${state.pollCount}/${MAX_POLLS} checks, ~${remainingMinutes} minutes remaining)

No new specs found in \`.claude-specs/\`. Waiting for work from other agents.

To stop polling and end the session, type: **stop** or press Ctrl+C
</spec-polling>`
        }
      }));
      return;
    }

    // Polling timeout reached - allow stop
    state.pollStartTime = Date.now();  // Reset for next session
    state.pollCount = 0;
    writeState(state);

    // Approve the stop (don't output anything, or output empty decision)
    console.log(JSON.stringify({
      decision: "approve"
    }));

  } catch (error) {
    // On error, approve stop
    console.log(JSON.stringify({
      decision: "approve"
    }));
  }
}

main();
